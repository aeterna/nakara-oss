// SPDX-License-Identifier: MIT

//! Start Rongroi Connect with the handoff contract v1 (ADR 0002 decision 8).
//!
//! The launcher creates a named pipe that only the current user can open,
//! starts Connect with the one argument `--from-launcher=<pipe name>`, and
//! writes one line to the pipe: an `rr1.` pairing code, at most 4096 bytes,
//! ended by `\n`. Connect reads that line and writes nothing back. The
//! caller learns only the exit code:
//!
//! | exit | meaning |
//! |------|---------|
//! | 0    | server accepted a report |
//! | 16   | server accepted a declined answer |
//! | 10   | internal error |
//! | 11   | player closed Connect before anything was sent |
//! | 12   | refused (argument, code or policy) |
//! | 13   | sidecar failed |
//! | 14   | record refused before upload |
//! | 15   | upload failed |
//!
//! The handoff runs on Windows only. Elsewhere [`start_connect`] returns
//! [`ConnectError::Unsupported`] without starting anything.
//!
//! The launcher never retries a code by itself.

use std::fmt;
use std::io;
use std::path::Path;
use std::process::ExitStatus;
use std::time::Duration;

#[cfg(windows)]
use std::process::{Child, Command, Stdio};
#[cfg(windows)]
use std::thread;
#[cfg(windows)]
use std::time::Instant;

/// The Windows named pipe code: CreateNamedPipeW, overlapped I/O, SDDL.
#[cfg(windows)]
#[doc(hidden)]
pub mod pipe;

/// Maximum size of a pairing code, in bytes.
pub const MAX_CODE_BYTES: usize = 4096;

/// The prefix every pairing code starts with.
const CODE_PREFIX: &str = "rr1.";

/// The prefix of every launch pipe name.
const PIPE_PREFIX: &str = r"\\.\pipe\rongroi-launch-";

/// The flag that carries the pipe name to Connect.
const LAUNCH_FLAG: &str = "--from-launcher=";

/// Lowercase hex digits after the prefix: 16 random bytes.
const PIPE_HEX_DIGITS: usize = 32;

/// How often a timed wait polls the child and the pipe.
#[cfg(windows)]
const POLL_INTERVAL: Duration = Duration::from_millis(10);

/// Why a pairing code was rejected.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CodeError {
    /// The code does not start with `rr1.`.
    Prefix,
    /// The code is longer than 4096 bytes.
    TooLong,
    /// The code holds bytes outside printable ASCII (0x21-0x7E): a space, a
    /// line break, a control character, or a non-ASCII byte such as a BOM.
    NotPrintable,
}

impl fmt::Display for CodeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CodeError::Prefix => write!(f, "code does not start with {CODE_PREFIX}"),
            CodeError::TooLong => write!(f, "code is longer than {MAX_CODE_BYTES} bytes"),
            CodeError::NotPrintable => write!(f, "code has bytes outside printable ASCII"),
        }
    }
}

impl std::error::Error for CodeError {}

/// What the Connect exit code means (handoff contract v1).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outcome {
    /// Exit 0: the server accepted a report.
    ReportAccepted,
    /// Exit 16: the server accepted a declined answer.
    DeclineAccepted,
    /// Exit 10: internal error.
    Internal,
    /// Exit 11: the player closed Connect before anything was sent.
    ClosedByPlayer,
    /// Exit 12: refused (argument, code or policy).
    Refused,
    /// Exit 13: sidecar failed.
    Sidecar,
    /// Exit 14: the record was refused before upload.
    RecordRefused,
    /// Exit 15: upload failed.
    UploadFailed,
    /// An exit code the contract does not name.
    Unknown(i32),
    /// The child died to a signal, so there is no exit code.
    Signal,
}

impl Outcome {
    /// Map a child exit status to its contract meaning.
    pub fn from_exit(status: ExitStatus) -> Outcome {
        match status.code() {
            Some(0) => Outcome::ReportAccepted,
            Some(10) => Outcome::Internal,
            Some(11) => Outcome::ClosedByPlayer,
            Some(12) => Outcome::Refused,
            Some(13) => Outcome::Sidecar,
            Some(14) => Outcome::RecordRefused,
            Some(15) => Outcome::UploadFailed,
            Some(16) => Outcome::DeclineAccepted,
            Some(code) => Outcome::Unknown(code),
            None => Outcome::Signal,
        }
    }

    /// True when Connect reported that something reached the server: a
    /// report accepted (0) or a declined answer accepted (16).
    pub fn sent_something(&self) -> bool {
        matches!(self, Outcome::ReportAccepted | Outcome::DeclineAccepted)
    }

    /// The raw exit code this outcome stands for, when there was one.
    pub fn exit_code(&self) -> Option<i32> {
        match self {
            Outcome::ReportAccepted => Some(0),
            Outcome::DeclineAccepted => Some(16),
            Outcome::Internal => Some(10),
            Outcome::ClosedByPlayer => Some(11),
            Outcome::Refused => Some(12),
            Outcome::Sidecar => Some(13),
            Outcome::RecordRefused => Some(14),
            Outcome::UploadFailed => Some(15),
            Outcome::Unknown(code) => Some(*code),
            Outcome::Signal => None,
        }
    }
}

/// Why a Connect run failed before an exit code could be mapped.
#[derive(Debug)]
pub enum ConnectError {
    /// The pairing code was rejected by [`validate_code`].
    Code(CodeError),
    /// Creating the pipe, starting Connect, or waiting for it failed.
    Io(io::Error),
    /// The Connect executable path is not absolute.
    NotAbsolute,
    /// The deadline passed; the child was killed.
    Timeout,
    /// The client on the pipe is not the Connect process the launcher started.
    PipeClientMismatch {
        /// The process id of the child the launcher started.
        expected: u32,
        /// The process id of the client that connected.
        got: u32,
    },
    /// The handoff needs Windows named pipes; this target has none.
    Unsupported,
}

impl fmt::Display for ConnectError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ConnectError::Code(err) => write!(f, "pairing code refused: {err}"),
            ConnectError::Io(err) => write!(f, "connect handoff failed: {err}"),
            ConnectError::NotAbsolute => write!(f, "connect executable path is not absolute"),
            ConnectError::Timeout => write!(f, "connect did not finish in time"),
            ConnectError::PipeClientMismatch { expected, got } => write!(
                f,
                "pipe client {got} is not the started connect process {expected}"
            ),
            ConnectError::Unsupported => write!(f, "connect handoff needs Windows"),
        }
    }
}

impl std::error::Error for ConnectError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            ConnectError::Code(err) => Some(err),
            ConnectError::Io(err) => Some(err),
            ConnectError::NotAbsolute => None,
            ConnectError::Timeout => None,
            ConnectError::PipeClientMismatch { .. } => None,
            ConnectError::Unsupported => None,
        }
    }
}

/// Check a pairing code against the handoff contract: it must start with
/// `rr1.`, be at most 4096 bytes, and hold printable ASCII only (0x21-0x7E).
/// Nothing is trimmed: any space, line break, control character or non-ASCII
/// byte refuses the code.
pub fn validate_code(code: &str) -> Result<&str, CodeError> {
    if !code.starts_with(CODE_PREFIX) {
        return Err(CodeError::Prefix);
    }
    if code.len() > MAX_CODE_BYTES {
        return Err(CodeError::TooLong);
    }
    if !code.bytes().all(|byte| (0x21..=0x7E).contains(&byte)) {
        return Err(CodeError::NotPrintable);
    }
    Ok(code)
}

/// The pipe name for 16 random bytes: the prefix and 32 lowercase hex digits.
pub fn pipe_name_from(bytes: [u8; 16]) -> String {
    let hex: String = bytes.iter().map(|byte| format!("{byte:02x}")).collect();
    format!("{PIPE_PREFIX}{hex}")
}

/// The one argument Connect is started with, for a pipe name.
pub fn launch_argument(pipe_name: &str) -> String {
    format!("{LAUNCH_FLAG}{pipe_name}")
}

/// True only for a name in the exact launch pipe pattern: the prefix and
/// 32 lowercase hex digits, nothing more.
pub fn is_launch_pipe_name(name: &str) -> bool {
    name.strip_prefix(PIPE_PREFIX).is_some_and(|hex| {
        hex.len() == PIPE_HEX_DIGITS
            && hex
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    })
}

/// Start Connect and hand it one pairing code through a named pipe.
///
/// The code is validated first, and `exe` must be an absolute path. The pipe
/// is created before Connect starts, so a name clash fails before anything
/// runs. Connect gets exactly one argument, `--from-launcher=<pipe name>`,
/// and null stdin, stdout and stderr.
///
/// `timeout` covers the whole handoff: waiting for the client, writing the
/// code, and waiting for Connect to exit. A child still running at the
/// deadline is killed and [`ConnectError::Timeout`] is returned.
///
/// Only Windows has the handoff. Elsewhere this returns
/// [`ConnectError::Unsupported`] after the same checks, without spawning.
#[cfg(windows)]
pub fn start_connect(exe: &Path, code: &str, timeout: Duration) -> Result<Outcome, ConnectError> {
    start_connect_with_env(exe, code, timeout, &[])
}

/// Start Connect and hand it one pairing code through a named pipe.
///
/// The code is validated first, and `exe` must be an absolute path. The pipe
/// is created before Connect starts, so a name clash fails before anything
/// runs. Connect gets exactly one argument, `--from-launcher=<pipe name>`,
/// and null stdin, stdout and stderr.
///
/// `timeout` covers the whole handoff: waiting for the client, writing the
/// code, and waiting for Connect to exit. A child still running at the
/// deadline is killed and [`ConnectError::Timeout`] is returned.
///
/// Only Windows has the handoff. Elsewhere this returns
/// [`ConnectError::Unsupported`] after the same checks, without spawning.
#[cfg(not(windows))]
pub fn start_connect(exe: &Path, code: &str, _timeout: Duration) -> Result<Outcome, ConnectError> {
    validate_code(code).map_err(ConnectError::Code)?;
    if !exe.is_absolute() {
        return Err(ConnectError::NotAbsolute);
    }
    Err(ConnectError::Unsupported)
}

/// [`start_connect`] with extra environment variables for the child. Only
/// the tests use it; it is not part of the handoff.
#[cfg(windows)]
#[doc(hidden)]
pub fn start_connect_with_env(
    exe: &Path,
    code: &str,
    timeout: Duration,
    env: &[(&str, &str)],
) -> Result<Outcome, ConnectError> {
    validate_code(code).map_err(ConnectError::Code)?;
    if !exe.is_absolute() {
        return Err(ConnectError::NotAbsolute);
    }
    let deadline = Instant::now()
        .checked_add(timeout)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "timeout is too long"))
        .map_err(ConnectError::Io)?;

    let name = pipe::random_pipe_name().map_err(ConnectError::Io)?;
    let mut server = pipe::ServerPipe::create(&name).map_err(ConnectError::Io)?;
    let mut child = Command::new(exe)
        .arg(launch_argument(&name))
        .envs(env.iter().copied())
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(ConnectError::Io)?;

    let expected = child.id();
    let mut line = code.as_bytes().to_vec();
    line.push(b'\n');
    let handoff = server.hand_off(&line, expected, deadline, &mut || child.try_wait());
    drop(server);

    match handoff {
        Ok(pipe::Handoff::Written) => wait_for_exit(&mut child, deadline),
        Ok(pipe::Handoff::ChildExited(status)) => Ok(Outcome::from_exit(status)),
        Ok(pipe::Handoff::Mismatch { got }) => {
            kill_and_reap(&mut child);
            Err(ConnectError::PipeClientMismatch { expected, got })
        }
        Ok(pipe::Handoff::Deadline) => {
            kill_and_reap(&mut child);
            Err(ConnectError::Timeout)
        }
        Err(err) => match child.try_wait() {
            Ok(Some(status)) => Ok(Outcome::from_exit(status)),
            _ => {
                kill_and_reap(&mut child);
                Err(ConnectError::Io(err))
            }
        },
    }
}

/// Wait for the child to exit before `deadline`. At the deadline the child
/// is killed and [`ConnectError::Timeout`] is returned.
#[cfg(windows)]
fn wait_for_exit(child: &mut Child, deadline: Instant) -> Result<Outcome, ConnectError> {
    loop {
        match child.try_wait() {
            Ok(Some(status)) => return Ok(Outcome::from_exit(status)),
            Ok(None) => {}
            Err(err) => {
                kill_and_reap(child);
                return Err(ConnectError::Io(err));
            }
        }
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            kill_and_reap(child);
            return Err(ConnectError::Timeout);
        }
        thread::sleep(POLL_INTERVAL.min(left));
    }
}

/// Kill the child and reap it, ignoring errors from either step.
#[cfg(windows)]
fn kill_and_reap(child: &mut Child) {
    let _ = child.kill();
    let _ = child.wait();
}

#[cfg(test)]
mod tests {
    use super::*;

    // -- pipe name and argument

    #[test]
    fn pipe_name_from_writes_lowercase_hex_after_the_prefix() {
        let bytes = [
            0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45, 0x67, 0x89, 0xFE, 0xDC, 0xBA, 0x98, 0x76, 0x54,
            0x32, 0x10,
        ];
        assert_eq!(
            pipe_name_from(bytes),
            r"\\.\pipe\rongroi-launch-abcdef0123456789fedcba9876543210"
        );
    }

    #[test]
    fn pipe_name_from_pads_each_byte_to_two_digits() {
        let mut bytes = [0u8; 16];
        bytes[15] = 0x0F;
        let expected = format!(r"\\.\pipe\rongroi-launch-{}0f", "0".repeat(30));
        assert_eq!(pipe_name_from(bytes), expected);
    }

    #[test]
    fn a_pipe_name_built_from_bytes_passes_the_pattern() {
        let name = pipe_name_from([0x5A; 16]);
        assert!(is_launch_pipe_name(&name), "{name}");
    }

    #[test]
    fn launch_argument_is_the_flag_and_the_pipe_name() {
        let name = pipe_name_from([0x01; 16]);
        assert_eq!(launch_argument(&name), format!("--from-launcher={name}"));
    }

    #[test]
    fn launch_argument_keeps_the_backslashes_of_the_pipe_name() {
        assert_eq!(
            launch_argument(r"\\.\pipe\rongroi-launch-00000000000000000000000000000000"),
            r"--from-launcher=\\.\pipe\rongroi-launch-00000000000000000000000000000000"
        );
    }

    #[test]
    fn accepts_exactly_the_launch_pattern() {
        let name = r"\\.\pipe\rongroi-launch-0123456789abcdef0123456789abcdef";
        assert!(is_launch_pipe_name(name));
    }

    #[test]
    fn rejects_other_pipe_names() {
        let good = r"\\.\pipe\rongroi-launch-0123456789abcdef0123456789abcdef";
        assert!(is_launch_pipe_name(good));
        assert!(!is_launch_pipe_name(&format!("{good}\n")));
        assert!(!is_launch_pipe_name(""));
        let cases = [
            // upper-case hex
            r"\\.\pipe\rongroi-launch-0123456789ABCDEF0123456789abcdef",
            // 31 and 33 digits
            r"\\.\pipe\rongroi-launch-0123456789abcdef0123456789abcde",
            r"\\.\pipe\rongroi-launch-0123456789abcdef0123456789abcdef0",
            // not hex
            r"\\.\pipe\rongroi-launch-0123456789abcdef0123456789abcdeg",
            r"\\.\pipe\other-0123456789abcdef0123456789abcdef",
            r"\\?\pipe\rongroi-launch-0123456789abcdef0123456789abcdef",
            r"//./pipe/rongroi-launch-0123456789abcdef0123456789abcdef",
            r"\\.\pipe\rongroi-launch-0123456789abcdef0123456789abcdef\extra",
            r"C:\rongroi-launch-0123456789abcdef0123456789abcdef",
        ];
        for name in cases {
            assert!(!is_launch_pipe_name(name), "{name:?}");
        }
    }

    // -- start_connect checks that run everywhere

    #[test]
    fn start_connect_refuses_a_relative_path() {
        let outcome = start_connect(Path::new("connect"), "rr1.exit0", Duration::from_secs(1));
        assert!(
            matches!(outcome, Err(ConnectError::NotAbsolute)),
            "{outcome:?}"
        );
    }

    #[cfg(not(windows))]
    #[test]
    fn start_connect_is_unsupported_off_windows() {
        let outcome = start_connect(
            Path::new("/nonexistent/connect"),
            "rr1.exit0",
            Duration::from_secs(1),
        );
        assert!(
            matches!(outcome, Err(ConnectError::Unsupported)),
            "{outcome:?}"
        );
    }

    // -- validate_code

    #[test]
    fn accepts_a_simple_code() {
        assert_eq!(validate_code("rr1.a1B-c_D.e/f~"), Ok("rr1.a1B-c_D.e/f~"));
    }

    #[test]
    fn accepts_a_code_of_exactly_max_bytes() {
        let code = format!(
            "{CODE_PREFIX}{}",
            "x".repeat(MAX_CODE_BYTES - CODE_PREFIX.len())
        );
        assert_eq!(code.len(), MAX_CODE_BYTES);
        assert_eq!(validate_code(&code), Ok(code.as_str()));
    }

    #[test]
    fn rejects_a_code_over_max_bytes() {
        let code = format!(
            "{CODE_PREFIX}{}",
            "x".repeat(MAX_CODE_BYTES - CODE_PREFIX.len() + 1)
        );
        assert_eq!(code.len(), MAX_CODE_BYTES + 1);
        assert_eq!(validate_code(&code), Err(CodeError::TooLong));
    }

    #[test]
    fn rejects_codes_without_the_rr1_prefix() {
        assert_eq!(validate_code(""), Err(CodeError::Prefix));
        assert_eq!(validate_code("rr1"), Err(CodeError::Prefix));
        assert_eq!(validate_code("rr2.abc"), Err(CodeError::Prefix));
        assert_eq!(validate_code("RR1.abc"), Err(CodeError::Prefix));
    }

    #[test]
    fn rejects_a_space_in_the_code() {
        assert_eq!(validate_code("rr1.a b"), Err(CodeError::NotPrintable));
    }

    #[test]
    fn rejects_line_breaks_in_the_code() {
        assert_eq!(validate_code("rr1.a\nb"), Err(CodeError::NotPrintable));
        assert_eq!(validate_code("rr1.a\rb"), Err(CodeError::NotPrintable));
    }

    #[test]
    fn rejects_control_characters_in_the_code() {
        assert_eq!(validate_code("rr1.a\tb"), Err(CodeError::NotPrintable));
        assert_eq!(validate_code("rr1.a\u{7}b"), Err(CodeError::NotPrintable));
    }

    #[test]
    fn rejects_non_ascii_in_the_code() {
        assert_eq!(validate_code("rr1.\u{FEFF}a"), Err(CodeError::NotPrintable));
        assert_eq!(validate_code("rr1.\u{0E01}"), Err(CodeError::NotPrintable));
    }

    // -- Outcome

    #[cfg(unix)]
    fn status_for(code: i32) -> ExitStatus {
        use std::os::unix::process::ExitStatusExt;
        ExitStatus::from_raw(code << 8)
    }

    #[cfg(windows)]
    fn status_for(code: i32) -> ExitStatus {
        use std::os::windows::process::ExitStatusExt;
        ExitStatus::from_raw(code as u32)
    }

    #[cfg(any(unix, windows))]
    #[test]
    fn maps_the_contract_exit_codes() {
        let cases = [
            (0, Outcome::ReportAccepted),
            (10, Outcome::Internal),
            (11, Outcome::ClosedByPlayer),
            (12, Outcome::Refused),
            (13, Outcome::Sidecar),
            (14, Outcome::RecordRefused),
            (15, Outcome::UploadFailed),
            (16, Outcome::DeclineAccepted),
        ];
        for (code, expected) in cases {
            assert_eq!(
                Outcome::from_exit(status_for(code)),
                expected,
                "exit {code}"
            );
        }
    }

    #[cfg(any(unix, windows))]
    #[test]
    fn maps_other_exit_codes_to_unknown() {
        assert_eq!(Outcome::from_exit(status_for(1)), Outcome::Unknown(1));
        assert_eq!(Outcome::from_exit(status_for(99)), Outcome::Unknown(99));
    }

    #[cfg(unix)]
    #[test]
    fn maps_a_signal_death_to_signal() {
        use std::os::unix::process::ExitStatusExt;
        assert_eq!(Outcome::from_exit(ExitStatus::from_raw(9)), Outcome::Signal);
    }

    #[test]
    fn only_accepted_answers_report_sending() {
        assert!(Outcome::ReportAccepted.sent_something());
        assert!(Outcome::DeclineAccepted.sent_something());
        assert!(!Outcome::Internal.sent_something());
        assert!(!Outcome::ClosedByPlayer.sent_something());
        assert!(!Outcome::Refused.sent_something());
        assert!(!Outcome::Sidecar.sent_something());
        assert!(!Outcome::RecordRefused.sent_something());
        assert!(!Outcome::UploadFailed.sent_something());
        assert!(!Outcome::Unknown(3).sent_something());
        assert!(!Outcome::Signal.sent_something());
    }

    #[test]
    fn exit_code_matches_the_mapping() {
        assert_eq!(Outcome::ReportAccepted.exit_code(), Some(0));
        assert_eq!(Outcome::DeclineAccepted.exit_code(), Some(16));
        assert_eq!(Outcome::Internal.exit_code(), Some(10));
        assert_eq!(Outcome::ClosedByPlayer.exit_code(), Some(11));
        assert_eq!(Outcome::Refused.exit_code(), Some(12));
        assert_eq!(Outcome::Sidecar.exit_code(), Some(13));
        assert_eq!(Outcome::RecordRefused.exit_code(), Some(14));
        assert_eq!(Outcome::UploadFailed.exit_code(), Some(15));
        assert_eq!(Outcome::Unknown(7).exit_code(), Some(7));
        assert_eq!(Outcome::Signal.exit_code(), None);
    }
}
