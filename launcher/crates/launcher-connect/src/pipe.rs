// SPDX-License-Identifier: MIT

//! The Windows side of the handoff: a one-instance named pipe that only the
//! current user can open. Every `unsafe` block in this crate is in this file.

use std::ffi::c_void;
use std::io;
use std::mem::size_of;
use std::process::ExitStatus;
use std::ptr::null_mut;
use std::thread;
use std::time::{Duration, Instant};

use windows_sys::Win32::Foundation::{
    CloseHandle, LocalFree, ERROR_BROKEN_PIPE, ERROR_IO_INCOMPLETE, ERROR_IO_PENDING,
    ERROR_PIPE_CONNECTED, ERROR_PIPE_NOT_CONNECTED, FALSE, HANDLE, INVALID_HANDLE_VALUE, TRUE,
};
use windows_sys::Win32::Security::Authorization::{
    ConvertSidToStringSidW, ConvertStringSecurityDescriptorToSecurityDescriptorW, SDDL_REVISION_1,
};
use windows_sys::Win32::Security::{
    GetTokenInformation, TokenUser, SECURITY_ATTRIBUTES, TOKEN_QUERY, TOKEN_USER,
};
use windows_sys::Win32::Storage::FileSystem::{
    ReadFile, WriteFile, FILE_FLAG_FIRST_PIPE_INSTANCE, FILE_FLAG_OVERLAPPED, PIPE_ACCESS_DUPLEX,
};
use windows_sys::Win32::System::Pipes::{
    ConnectNamedPipe, CreateNamedPipeW, DisconnectNamedPipe, GetNamedPipeClientProcessId,
    PIPE_REJECT_REMOTE_CLIENTS, PIPE_TYPE_BYTE, PIPE_WAIT,
};
use windows_sys::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};
use windows_sys::Win32::System::IO::{CancelIoEx, GetOverlappedResult, OVERLAPPED};

use crate::pipe_name_from;

/// Out-buffer size of the pipe, in bytes.
const OUT_BUFFER_BYTES: u32 = 8192;

/// How often a wait polls the pipe and the child.
const POLL_INTERVAL: Duration = Duration::from_millis(10);

/// How a handoff ended.
#[derive(Debug)]
pub enum Handoff {
    /// The client read the whole line and closed its end of the pipe.
    Written,
    /// The connected client is not the expected process.
    Mismatch {
        /// The process id of the client.
        got: u32,
    },
    /// The child exited before the line was read.
    ChildExited(ExitStatus),
    /// The deadline passed first.
    Deadline,
}

/// The server end of a launch pipe. The handle closes on drop.
#[derive(Debug)]
pub struct ServerPipe {
    handle: OwnedHandle,
}

impl ServerPipe {
    /// Create the pipe `name`, open to the current user only. It fails when
    /// the name is already in use.
    pub fn create(name: &str) -> io::Result<ServerPipe> {
        let sddl = user_only_sddl(&current_user_sid()?);
        let descriptor = SecurityDescriptor::from_sddl(&sddl)?;
        let attributes = SECURITY_ATTRIBUTES {
            nLength: size_of::<SECURITY_ATTRIBUTES>() as u32,
            lpSecurityDescriptor: descriptor.raw(),
            bInheritHandle: FALSE,
        };
        let handle = create_pipe(name, &attributes)?;
        Ok(ServerPipe {
            handle: OwnedHandle(handle),
        })
    }

    /// Serve `bytes` to the one client that connects, and check that its
    /// process id is `expected_pid`. `child_exit` is polled while the wait
    /// for the client, the write, and the wait for client close run; a child
    /// that exits first ends the handoff. Every wait ends at `deadline`.
    pub fn hand_off(
        &mut self,
        bytes: &[u8],
        expected_pid: u32,
        deadline: Instant,
        child_exit: &mut dyn FnMut() -> io::Result<Option<ExitStatus>>,
    ) -> io::Result<Handoff> {
        let mut connect = Overlapped::new();
        if !self.start_connect(&mut connect)? {
            match self.wait_op(&mut connect, deadline, &mut *child_exit)? {
                Wait::Done(_) => {}
                Wait::ChildExited(status) => return Ok(Handoff::ChildExited(status)),
                Wait::Deadline => return Ok(Handoff::Deadline),
            }
        }

        let got = self.client_pid()?;
        if got != expected_pid {
            return Ok(Handoff::Mismatch { got });
        }

        let mut write = Overlapped::new();
        self.start_write(&mut write, bytes)?;
        let count = match self.wait_op(&mut write, deadline, &mut *child_exit)? {
            Wait::Done(count) => count,
            Wait::ChildExited(status) => return Ok(Handoff::ChildExited(status)),
            Wait::Deadline => return Ok(Handoff::Deadline),
        };
        if count as usize != bytes.len() {
            return Err(io::Error::other("the pipe took only part of the line"));
        }

        // Wait for the client to close its end of the pipe before disconnecting.
        // No FlushFileBuffers is used so a stalling client cannot block past
        // the deadline.
        if let Some(ended) = self.wait_client_close(deadline, &mut *child_exit)? {
            return Ok(ended);
        }
        self.disconnect();
        Ok(Handoff::Written)
    }

    /// Start an overlapped connect. Returns true when a client is already
    /// connected, so no operation is pending.
    fn start_connect(&self, op: &mut Overlapped) -> io::Result<bool> {
        // SAFETY: the handle is a server pipe, and `op` lives until the
        // operation completes or is cancelled by the caller.
        let ok = unsafe { ConnectNamedPipe(self.handle.raw(), op.as_mut_ptr()) };
        if ok != FALSE || last_error_is(ERROR_PIPE_CONNECTED) {
            Ok(true)
        } else if last_error_is(ERROR_IO_PENDING) {
            Ok(false)
        } else {
            Err(last_os_error())
        }
    }

    /// Start an overlapped write. The result is read with `wait_op`.
    fn start_write(&self, op: &mut Overlapped, bytes: &[u8]) -> io::Result<()> {
        let len = u32::try_from(bytes.len()).map_err(io::Error::other)?;
        // SAFETY: `bytes` and `op` stay alive until the write completes or is
        // cancelled. An overlapped write may pass a null byte count.
        let ok = unsafe {
            WriteFile(
                self.handle.raw(),
                bytes.as_ptr().cast(),
                len,
                null_mut(),
                op.as_mut_ptr(),
            )
        };
        if ok != FALSE || last_error_is(ERROR_IO_PENDING) {
            Ok(())
        } else {
            Err(last_os_error())
        }
    }

    /// Poll an overlapped operation until it completes. A child exit or the
    /// deadline ends the wait early. The operation is cancelled and drained
    /// before that returns, so the kernel no longer uses `op`.
    fn wait_op(
        &self,
        op: &mut Overlapped,
        deadline: Instant,
        child_exit: &mut dyn FnMut() -> io::Result<Option<ExitStatus>>,
    ) -> io::Result<Wait> {
        loop {
            match self.poll_op(op) {
                Ok(Some(count)) => return Ok(Wait::Done(count)),
                Ok(None) => {}
                Err(err) => {
                    self.cancel_and_drain(op);
                    return Err(err);
                }
            }
            match child_exit() {
                Ok(Some(status)) => {
                    self.cancel_and_drain(op);
                    return Ok(Wait::ChildExited(status));
                }
                Ok(None) => {}
                Err(err) => {
                    self.cancel_and_drain(op);
                    return Err(err);
                }
            }
            let left = deadline.saturating_duration_since(Instant::now());
            if left.is_zero() {
                self.cancel_and_drain(op);
                return Ok(Wait::Deadline);
            }
            thread::sleep(POLL_INTERVAL.min(left));
        }
    }

    /// One non-blocking look at an overlapped operation: its byte count when
    /// it is done, or None while it is still running.
    fn poll_op(&self, op: &Overlapped) -> io::Result<Option<u32>> {
        let mut count = 0u32;
        // SAFETY: `op` describes an operation on this handle, `count` is a
        // valid out pointer, and FALSE for bWait means the call does not block.
        let ok = unsafe { GetOverlappedResult(self.handle.raw(), op.as_ptr(), &mut count, FALSE) };
        if ok != FALSE {
            Ok(Some(count))
        } else if last_error_is(ERROR_IO_INCOMPLETE) {
            Ok(None)
        } else {
            Err(last_os_error())
        }
    }

    /// Cancel the pending operation in `op`, then wait until the kernel has
    /// finished with it.
    fn cancel_and_drain(&self, op: &mut Overlapped) {
        // SAFETY: cancels only the operation that `op` describes, on this handle.
        unsafe { CancelIoEx(self.handle.raw(), op.as_ptr()) };
        let mut count = 0u32;
        // SAFETY: TRUE for bWait makes the call wait until the cancelled
        // operation is over, so `op` is no longer used once it returns.
        unsafe { GetOverlappedResult(self.handle.raw(), op.as_ptr(), &mut count, TRUE) };
    }

    /// The process id of the connected client.
    fn client_pid(&self) -> io::Result<u32> {
        let mut pid = 0u32;
        // SAFETY: the handle is a connected server pipe and `pid` is a valid
        // out pointer.
        let ok = unsafe { GetNamedPipeClientProcessId(self.handle.raw(), &mut pid) };
        if ok != FALSE {
            Ok(pid)
        } else {
            Err(last_os_error())
        }
    }

    /// Wait until the client closes its end of the pipe. If the client sends
    /// bytes instead, they are discarded and the wait continues. A client that
    /// never closes its end is ended at the deadline (Handoff::Deadline).
    fn wait_client_close(
        &self,
        deadline: Instant,
        child_exit: &mut dyn FnMut() -> io::Result<Option<ExitStatus>>,
    ) -> io::Result<Option<Handoff>> {
        let mut sink = [0u8; 1];
        loop {
            let mut op = Overlapped::new();
            // SAFETY: `sink` and `op` stay alive until the read completes or is
            // cancelled by `cancel_and_drain`.
            let ok = unsafe {
                ReadFile(
                    self.handle.raw(),
                    sink.as_mut_ptr().cast(),
                    1,
                    null_mut(),
                    op.as_mut_ptr(),
                )
            };
            if ok != FALSE {
                // The client sent bytes synchronously; discard and keep waiting.
                continue;
            }
            if last_error_is(ERROR_BROKEN_PIPE) || last_error_is(ERROR_PIPE_NOT_CONNECTED) {
                return Ok(None);
            }
            if !last_error_is(ERROR_IO_PENDING) {
                return Err(last_os_error());
            }

            match self.wait_read(&mut op, deadline, child_exit)? {
                ReadWait::Closed => return Ok(None),
                ReadWait::Data => continue,
                ReadWait::ChildExited(status) => return Ok(Some(Handoff::ChildExited(status))),
                ReadWait::Deadline => return Ok(Some(Handoff::Deadline)),
            }
        }
    }

    /// Poll an overlapped read until the client closes or sends bytes, or
    /// until a child exit or deadline. The pending operation is cancelled and
    /// drained before returning on child exit, deadline, or error.
    fn wait_read(
        &self,
        op: &mut Overlapped,
        deadline: Instant,
        child_exit: &mut dyn FnMut() -> io::Result<Option<ExitStatus>>,
    ) -> io::Result<ReadWait> {
        loop {
            match self.poll_op(op) {
                Ok(Some(_count)) => return Ok(ReadWait::Data),
                Ok(None) => {}
                Err(err)
                    if err.raw_os_error() == Some(ERROR_BROKEN_PIPE as i32)
                        || err.raw_os_error() == Some(ERROR_PIPE_NOT_CONNECTED as i32) =>
                {
                    return Ok(ReadWait::Closed);
                }
                Err(err) => {
                    self.cancel_and_drain(op);
                    return Err(err);
                }
            }
            match child_exit() {
                Ok(Some(status)) => {
                    self.cancel_and_drain(op);
                    return Ok(ReadWait::ChildExited(status));
                }
                Ok(None) => {}
                Err(err) => {
                    self.cancel_and_drain(op);
                    return Err(err);
                }
            }
            let left = deadline.saturating_duration_since(Instant::now());
            if left.is_zero() {
                self.cancel_and_drain(op);
                return Ok(ReadWait::Deadline);
            }
            thread::sleep(POLL_INTERVAL.min(left));
        }
    }

    /// Disconnect the server end of the pipe. Best effort: the client has
    /// already closed its end.
    fn disconnect(&self) {
        // SAFETY: the handle is a live server pipe.
        unsafe { DisconnectNamedPipe(self.handle.raw()) };
    }
}

/// The result of waiting on the client to close its end of the pipe.
enum ReadWait {
    /// The client closed its end of the pipe.
    Closed,
    /// The client wrote bytes to the pipe instead of closing.
    Data,
    /// The child exited first; the operation was cancelled.
    ChildExited(ExitStatus),
    /// The deadline passed first; the operation was cancelled.
    Deadline,
}

/// The result of waiting on one overlapped operation.
enum Wait {
    /// The operation finished, with this byte count.
    Done(u32),
    /// The child exited first; the operation was cancelled.
    ChildExited(ExitStatus),
    /// The deadline passed first; the operation was cancelled.
    Deadline,
}

/// Serve `bytes` to the first client, as if `expected_pid` were the child.
/// No child runs, so the handoff ends on a client, a mismatch or the deadline.
#[doc(hidden)]
pub fn serve_for_test(
    name: &str,
    bytes: &[u8],
    expected_pid: u32,
    timeout: Duration,
) -> io::Result<Handoff> {
    let mut server = ServerPipe::create(name)?;
    let deadline = Instant::now() + timeout;
    let mut no_child = || -> io::Result<Option<ExitStatus>> { Ok(None) };
    server.hand_off(bytes, expected_pid, deadline, &mut no_child)
}

/// A new launch pipe name, from 16 random bytes.
pub(crate) fn random_pipe_name() -> io::Result<String> {
    let mut bytes = [0u8; 16];
    getrandom::fill(&mut bytes).map_err(|err| io::Error::other(format!("random bytes: {err}")))?;
    Ok(pipe_name_from(bytes))
}

/// The SDDL that grants full access to one SID and nothing else. The DACL
/// is protected, so no inherited entry can widen it.
fn user_only_sddl(sid: &str) -> String {
    format!("D:P(A;;GA;;;{sid})")
}

/// The string form of the current user's SID.
fn current_user_sid() -> io::Result<String> {
    let token = process_token()?;
    let user = token_user(&token)?;
    sid_string(&user)
}

/// A handle to the current process token, for query only.
fn process_token() -> io::Result<OwnedHandle> {
    let mut token: HANDLE = null_mut();
    // SAFETY: GetCurrentProcess returns a pseudo-handle that needs no close,
    // and `token` is a valid out pointer.
    let ok = unsafe { OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token) };
    if ok != FALSE {
        Ok(OwnedHandle(token))
    } else {
        Err(last_os_error())
    }
}

/// The TOKEN_USER record of a token. It is kept in pointer-sized words, so
/// the SID pointer inside it is aligned.
fn token_user(token: &OwnedHandle) -> io::Result<Vec<usize>> {
    let mut needed = 0u32;
    // SAFETY: a null buffer with length 0 only asks for the size, and
    // `needed` is a valid out pointer.
    unsafe { GetTokenInformation(token.raw(), TokenUser, null_mut(), 0, &mut needed) };
    if needed == 0 {
        return Err(io::Error::other("the process token has no user"));
    }
    let mut words = vec![0usize; (needed as usize).div_ceil(size_of::<usize>())];
    let mut returned = 0u32;
    // SAFETY: `words` holds at least `needed` bytes and is aligned for
    // TOKEN_USER. `returned` is a valid out pointer.
    let ok = unsafe {
        GetTokenInformation(
            token.raw(),
            TokenUser,
            words.as_mut_ptr().cast(),
            needed,
            &mut returned,
        )
    };
    if ok != FALSE {
        Ok(words)
    } else {
        Err(last_os_error())
    }
}

/// The SID string of the user in a TOKEN_USER buffer.
fn sid_string(token_user: &[usize]) -> io::Result<String> {
    // SAFETY: `token_user` was filled by GetTokenInformation(TokenUser), so
    // it starts with a TOKEN_USER. The SID it points to lives in that buffer.
    let sid = unsafe { (*token_user.as_ptr().cast::<TOKEN_USER>()).User.Sid };
    let mut raw: *mut u16 = null_mut();
    // SAFETY: `sid` is a valid SID and `raw` is a valid out pointer.
    let ok = unsafe { ConvertSidToStringSidW(sid, &mut raw) };
    if ok == FALSE {
        return Err(last_os_error());
    }
    let text = LocalMemory(raw.cast());
    wide_to_string(text.0.cast())
}

/// A security descriptor built from SDDL. It is freed on drop.
struct SecurityDescriptor(LocalMemory);

impl SecurityDescriptor {
    fn from_sddl(sddl: &str) -> io::Result<SecurityDescriptor> {
        let wide_sddl = to_wide(sddl);
        let mut raw: *mut c_void = null_mut();
        // SAFETY: `wide_sddl` is NUL-terminated, `raw` is a valid out pointer,
        // and the size out pointer may be null.
        let ok = unsafe {
            ConvertStringSecurityDescriptorToSecurityDescriptorW(
                wide_sddl.as_ptr(),
                SDDL_REVISION_1,
                &mut raw,
                null_mut(),
            )
        };
        if ok != FALSE {
            Ok(SecurityDescriptor(LocalMemory(raw)))
        } else {
            Err(last_os_error())
        }
    }

    fn raw(&self) -> *mut c_void {
        self.0 .0
    }
}

/// Memory from a LocalAlloc-based Windows API. It is freed on drop.
struct LocalMemory(*mut c_void);

impl Drop for LocalMemory {
    fn drop(&mut self) {
        if !self.0.is_null() {
            // SAFETY: the pointer came from a LocalAlloc-based API and is
            // freed only here.
            unsafe { LocalFree(self.0) };
        }
    }
}

/// A kernel handle that closes on drop.
#[derive(Debug)]
struct OwnedHandle(HANDLE);

impl OwnedHandle {
    fn raw(&self) -> HANDLE {
        self.0
    }
}

impl Drop for OwnedHandle {
    fn drop(&mut self) {
        // SAFETY: the handle is owned by this value and is closed only here.
        unsafe { CloseHandle(self.0) };
    }
}

/// An OVERLAPPED block for one operation. It has no event: the pipe handle
/// is signaled instead, and one operation runs at a time.
struct Overlapped(OVERLAPPED);

impl Overlapped {
    fn new() -> Overlapped {
        // SAFETY: OVERLAPPED is plain data, and all-zero bytes are a valid value.
        Overlapped(unsafe { std::mem::zeroed() })
    }

    fn as_ptr(&self) -> *const OVERLAPPED {
        &self.0
    }

    fn as_mut_ptr(&mut self) -> *mut OVERLAPPED {
        &mut self.0
    }
}

/// Create the server end of the pipe with the given security attributes.
fn create_pipe(name: &str, attributes: &SECURITY_ATTRIBUTES) -> io::Result<HANDLE> {
    let wide_name = to_wide(name);
    // SAFETY: `wide_name` is NUL-terminated. `attributes` and the descriptor
    // it points to are alive for the call, which copies the descriptor.
    let handle = unsafe {
        CreateNamedPipeW(
            wide_name.as_ptr(),
            // Duplex is needed so the server handle may query the client process
            // id and wait for the client to close.
            PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE | FILE_FLAG_OVERLAPPED,
            PIPE_TYPE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
            1,
            OUT_BUFFER_BYTES,
            0,
            0,
            attributes,
        )
    };
    if handle != INVALID_HANDLE_VALUE {
        Ok(handle)
    } else {
        Err(last_os_error())
    }
}

/// Copy a NUL-terminated UTF-16 string into a Rust string.
fn wide_to_string(ptr: *const u16) -> io::Result<String> {
    // SAFETY: `ptr` is a NUL-terminated string from a Windows API. The reads
    // stop at the terminator, and the slice stays inside that string.
    let units = unsafe {
        let mut len = 0;
        while *ptr.add(len) != 0 {
            len += 1;
        }
        std::slice::from_raw_parts(ptr, len)
    };
    String::from_utf16(units).map_err(|err| io::Error::new(io::ErrorKind::InvalidData, err))
}

/// A NUL-terminated UTF-16 copy of `text`.
fn to_wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(std::iter::once(0)).collect()
}

/// The thread's last Windows error as an `io::Error`.
fn last_os_error() -> io::Error {
    io::Error::last_os_error()
}

/// True when the thread's last Windows error is `code`.
fn last_error_is(code: u32) -> bool {
    io::Error::last_os_error().raw_os_error() == Some(code as i32)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::is_launch_pipe_name;

    #[test]
    fn the_sddl_grants_full_access_to_the_user_sid_only() {
        assert_eq!(
            user_only_sddl("S-1-5-21-1-2-3-1001"),
            "D:P(A;;GA;;;S-1-5-21-1-2-3-1001)"
        );
    }

    #[test]
    fn the_current_user_sid_is_a_sid_string() {
        let sid = current_user_sid().expect("the process token should give a SID");
        assert!(sid.starts_with("S-1-"), "{sid}");
    }

    #[test]
    fn a_random_pipe_name_passes_the_pattern() {
        let name = random_pipe_name().expect("the random source should work");
        assert!(is_launch_pipe_name(&name), "{name}");
    }
}
