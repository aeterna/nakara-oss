// SPDX-License-Identifier: MIT

//! Start Rongroi Connect with the handoff contract v1 (ADR 0002 decision 8).
//!
//! Connect accepts exactly one argument `--from-launcher`, then reads one
//! line from stdin: an `rr1.` pairing code, at most 4096 bytes, ended by `\n`
//! or EOF. It writes nothing back; the caller learns only the exit code:
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
//! The launcher never retries a code by itself.

use std::fmt;
use std::io::{self, Write};
use std::path::Path;
use std::process::{Child, ChildStdin, Command, ExitStatus, Stdio};
use std::sync::mpsc::{self, TryRecvError};
use std::thread;
use std::time::{Duration, Instant};

/// Maximum size of a pairing code, in bytes.
pub const MAX_CODE_BYTES: usize = 4096;

/// The prefix every pairing code starts with.
const CODE_PREFIX: &str = "rr1.";

/// How often the timed wait polls the child before the timeout fires.
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
    /// Spawning Connect, writing to its stdin, or waiting for it failed.
    Io(io::Error),
    /// The Connect executable path is not absolute.
    NotAbsolute,
    /// The child outlived the timeout and was killed.
    Timeout,
}

impl fmt::Display for ConnectError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ConnectError::Code(err) => write!(f, "pairing code refused: {err}"),
            ConnectError::Io(err) => write!(f, "connect process failed: {err}"),
            ConnectError::NotAbsolute => write!(f, "connect executable path is not absolute"),
            ConnectError::Timeout => write!(f, "connect did not finish in time"),
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

/// Start Connect and hand it one pairing code.
///
/// The code is validated first, and `exe` must be an absolute path. Connect
/// then runs with exactly one argument, `--from-launcher`, piped stdin and
/// null stdout and stderr; nothing else about the child is changed, in
/// particular no extra environment. The code and one `\n` go to stdin from a
/// helper thread, which closes the pipe afterwards. `timeout` covers writing
/// the code and waiting for the child: a child still running when it elapses
/// is killed and [`ConnectError::Timeout`] is returned.
///
/// If Connect exits before the code is written, the pipe breaks. The wait
/// then continues within the same timeout: when the child has already exited
/// its outcome is returned, and only a still-running child is killed and
/// reported as [`ConnectError::Io`].
///
/// On Windows Connect is a GUI app, so the child is spawned normally:
/// `CREATE_NO_WINDOW` is deliberately not set.
pub fn start_connect(exe: &Path, code: &str, timeout: Duration) -> Result<Outcome, ConnectError> {
    validate_code(code).map_err(ConnectError::Code)?;
    if !exe.is_absolute() {
        return Err(ConnectError::NotAbsolute);
    }

    let child = Command::new(exe)
        .arg("--from-launcher")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(ConnectError::Io)?;

    run_child(child, code, timeout)
}

/// Write the code from a helper thread and wait for the child against one
/// deadline.
fn run_child(mut child: Child, code: &str, timeout: Duration) -> Result<Outcome, ConnectError> {
    let start = Instant::now();
    let stdin = child.stdin.take();
    let code = code.to_owned();
    let (sender, receiver) = mpsc::channel();
    if let Err(err) = thread::Builder::new().spawn(move || {
        let _ = sender.send(write_code(stdin, &code));
    }) {
        kill_and_reap(&mut child);
        return Err(ConnectError::Io(err));
    }
    wait_with_timeout(child, &receiver, start, timeout)
}

/// Write `code` and one newline to the child's stdin; the handle then drops
/// and closes the pipe.
fn write_code(stdin: Option<ChildStdin>, code: &str) -> io::Result<()> {
    let mut stdin = match stdin {
        Some(stdin) => stdin,
        None => return Err(io::Error::other("stdin was not captured")),
    };
    stdin.write_all(code.as_bytes())?;
    stdin.write_all(b"\n")?;
    stdin.flush()
}

/// Wait for the child while the code is being written, but kill it and report
/// [`ConnectError::Timeout`] once `limit` has elapsed since `start`.
fn wait_with_timeout(
    mut child: Child,
    write_result: &mpsc::Receiver<io::Result<()>>,
    start: Instant,
    limit: Duration,
) -> Result<Outcome, ConnectError> {
    loop {
        match write_result.try_recv() {
            Ok(Ok(())) => return finish_after_write(&mut child, start, limit),
            Ok(Err(err)) => return finish_after_write_error(&mut child, start, limit, err),
            Err(TryRecvError::Disconnected) => {
                let err = io::Error::other("stdin writer thread stopped without a result");
                return finish_after_write_error(&mut child, start, limit, err);
            }
            Err(TryRecvError::Empty) => {}
        }

        match child.try_wait() {
            Ok(Some(status)) => return Ok(Outcome::from_exit(status)),
            Ok(None) => {}
            Err(err) => {
                kill_and_reap(&mut child);
                return Err(ConnectError::Io(err));
            }
        }

        if start.elapsed() >= limit {
            kill_and_reap(&mut child);
            return Err(ConnectError::Timeout);
        }
        thread::sleep(POLL_INTERVAL);
    }
}

/// Wait for a child whose code was written, killing it at the deadline.
fn finish_after_write(
    child: &mut Child,
    start: Instant,
    limit: Duration,
) -> Result<Outcome, ConnectError> {
    match wait_until(child, start, limit) {
        Ok(Some(status)) => Ok(Outcome::from_exit(status)),
        Ok(None) => {
            kill_and_reap(child);
            Err(ConnectError::Timeout)
        }
        Err(err) => Err(ConnectError::Io(err)),
    }
}

/// Wait for a child whose code write failed: if it is still running at the
/// deadline, kill it and report the write error.
fn finish_after_write_error(
    child: &mut Child,
    start: Instant,
    limit: Duration,
    err: io::Error,
) -> Result<Outcome, ConnectError> {
    match wait_until(child, start, limit) {
        Ok(Some(status)) => Ok(Outcome::from_exit(status)),
        Ok(None) => {
            kill_and_reap(child);
            Err(ConnectError::Io(err))
        }
        Err(wait_err) => Err(ConnectError::Io(wait_err)),
    }
}

/// Poll the child until it exits or the deadline passes. A failed poll kills
/// and reaps the child before the error is returned.
fn wait_until(
    child: &mut Child,
    start: Instant,
    limit: Duration,
) -> io::Result<Option<ExitStatus>> {
    loop {
        match child.try_wait() {
            Ok(Some(status)) => return Ok(Some(status)),
            Ok(None) => {}
            Err(err) => {
                kill_and_reap(child);
                return Err(err);
            }
        }
        if start.elapsed() >= limit {
            return Ok(None);
        }
        thread::sleep(POLL_INTERVAL);
    }
}

/// Kill the child and reap it, ignoring errors from either step.
fn kill_and_reap(child: &mut Child) {
    let _ = child.kill();
    let _ = child.wait();
}

#[cfg(test)]
mod tests {
    use super::*;

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

    // -- write errors

    #[cfg(unix)]
    fn exit_command(code: i32) -> Command {
        let mut command = Command::new("sh");
        command.arg("-c").arg(format!("exit {code}"));
        command
    }

    #[cfg(windows)]
    fn exit_command(code: i32) -> Command {
        let mut command = Command::new("cmd");
        command.arg("/C").arg("exit").arg(code.to_string());
        command
    }

    #[cfg(any(unix, windows))]
    #[test]
    fn a_write_error_returns_the_child_exit_code() {
        let mut command = exit_command(12);
        command
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        let mut child = command.spawn().expect("the exit helper should spawn");
        // The missing stdin handle makes the writer report an error at once.
        drop(child.stdin.take());

        let outcome = run_child(child, "rr1.exit0", Duration::from_secs(5));
        assert_eq!(outcome.expect("the child should exit"), Outcome::Refused);
    }
}
