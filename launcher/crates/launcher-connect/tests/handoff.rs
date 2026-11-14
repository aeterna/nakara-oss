// SPDX-License-Identifier: MIT

#![cfg(all(feature = "mock", windows))]

//! Integration tests for the handoff contract v1 (ADR 0002 decision 8) over
//! the named pipe, driving `src/bin/mock-connect.rs` through `start_connect`.
//!
//! Run with: `cargo test -p launcher-connect --features mock` on Windows.

use std::fs::OpenOptions;
use std::io::{ErrorKind, Read};
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread;
use std::time::{Duration, Instant};

use launcher_connect::pipe::{serve_for_test, Handoff, ServerPipe};
use launcher_connect::{
    launch_argument, pipe_name_from, start_connect, start_connect_with_env, CodeError,
    ConnectError, Outcome,
};

/// A handoff test should finish well before this; the timeout is only here to
/// keep a stuck mock from hanging the suite.
const TEST_TIMEOUT: Duration = Duration::from_secs(30);

/// Win32 error for a pipe with no free instance yet.
const ERROR_PIPE_BUSY: i32 = 231;

fn mock_path() -> &'static Path {
    Path::new(env!("CARGO_BIN_EXE_mock-connect"))
}

/// A pipe name no other test in this run uses.
fn unique_pipe_name() -> String {
    static NEXT: AtomicU64 = AtomicU64::new(1);
    let mut bytes = [0u8; 16];
    bytes[..4].copy_from_slice(&std::process::id().to_be_bytes());
    bytes[8..].copy_from_slice(&NEXT.fetch_add(1, Ordering::Relaxed).to_be_bytes());
    pipe_name_from(bytes)
}

/// Run Connect through the real handoff: start it, write the code, map the
/// exit code.
fn run_connect(code: &str) -> Result<Outcome, ConnectError> {
    start_connect(mock_path(), code, TEST_TIMEOUT)
}

/// What the mock wrote and how it exited.
struct MockRun {
    code: Option<i32>,
    stdout: Vec<u8>,
    stderr: Vec<u8>,
}

/// Run the mock through a real pipe: create it, start the mock, serve
/// `bytes` to it exactly as they are, then collect the mock's result.
fn run_mock_with_bytes(bytes: &[u8]) -> MockRun {
    let name = unique_pipe_name();
    let mut server = ServerPipe::create(&name).expect("the pipe should be created");
    let mut child = Command::new(mock_path())
        .arg(launch_argument(&name))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("the mock should spawn");
    let deadline = Instant::now() + TEST_TIMEOUT;
    let handoff = server.hand_off(bytes, child.id(), deadline, &mut || child.try_wait());
    drop(server);
    let handoff = handoff.expect("the handoff should not fail");
    if matches!(handoff, Handoff::Deadline) {
        let _ = child.kill();
    }
    let output = child.wait_with_output().expect("the mock should finish");
    MockRun {
        code: output.status.code(),
        stdout: output.stdout,
        stderr: output.stderr,
    }
}

/// Run the mock with `args` and `env` and no pipe. For refusals that happen
/// before any pipe is opened.
fn run_mock_direct(args: &[&str], env: &[(&str, &str)]) -> MockRun {
    let output = Command::new(mock_path())
        .args(args)
        .envs(env.iter().copied())
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .expect("the mock should run");
    MockRun {
        code: output.status.code(),
        stdout: output.stdout,
        stderr: output.stderr,
    }
}

/// Open the server's pipe as a client, retrying while the server is not
/// ready yet.
fn connect_as_client(name: &str) -> std::fs::File {
    let deadline = Instant::now() + TEST_TIMEOUT;
    loop {
        match OpenOptions::new().read(true).open(name) {
            Ok(file) => return file,
            Err(err)
                if Instant::now() < deadline
                    && (err.kind() == ErrorKind::NotFound
                        || err.raw_os_error() == Some(ERROR_PIPE_BUSY)) =>
            {
                thread::sleep(Duration::from_millis(5));
            }
            Err(err) => panic!("the client should connect to {name}: {err}"),
        }
    }
}

#[test]
fn report_accepted_is_exit_zero() {
    assert_eq!(run_connect("rr1.exit0").unwrap(), Outcome::ReportAccepted);
}

#[test]
fn a_line_without_exit_directive_defaults_to_zero() {
    assert_eq!(run_connect("rr1.pairing").unwrap(), Outcome::ReportAccepted);
}

#[test]
fn decline_accepted_is_exit_sixteen() {
    assert_eq!(run_connect("rr1.exit16").unwrap(), Outcome::DeclineAccepted);
}

#[test]
fn internal_error_is_exit_ten() {
    assert_eq!(run_connect("rr1.exit10").unwrap(), Outcome::Internal);
}

#[test]
fn closed_by_player_is_exit_eleven() {
    assert_eq!(run_connect("rr1.exit11").unwrap(), Outcome::ClosedByPlayer);
}

#[test]
fn refused_is_exit_twelve() {
    assert_eq!(run_connect("rr1.exit12").unwrap(), Outcome::Refused);
}

#[test]
fn sidecar_failed_is_exit_thirteen() {
    assert_eq!(run_connect("rr1.exit13").unwrap(), Outcome::Sidecar);
}

#[test]
fn record_refused_is_exit_fourteen() {
    assert_eq!(run_connect("rr1.exit14").unwrap(), Outcome::RecordRefused);
}

#[test]
fn upload_failed_is_exit_fifteen() {
    assert_eq!(run_connect("rr1.exit15").unwrap(), Outcome::UploadFailed);
}

#[test]
fn an_exit_code_outside_the_contract_is_unknown() {
    assert_eq!(run_connect("rr1.exit7").unwrap(), Outcome::Unknown(7));
}

#[test]
fn sent_something_follows_the_real_exit_codes() {
    assert!(run_connect("rr1.exit0").unwrap().sent_something());
    assert!(run_connect("rr1.exit16").unwrap().sent_something());
    assert!(!run_connect("rr1.exit11").unwrap().sent_something());
    assert!(!run_connect("rr1.exit12").unwrap().sent_something());
}

#[test]
fn the_mock_refuses_an_extra_argument() {
    let name = unique_pipe_name();
    let run = run_mock_direct(&[&launch_argument(&name), "extra"], &[]);
    assert_eq!(run.code, Some(12));
    assert!(run.stdout.is_empty());
    assert!(run.stderr.is_empty());
}

#[test]
fn the_mock_refuses_a_missing_argument() {
    let run = run_mock_direct(&[], &[]);
    assert_eq!(run.code, Some(12));
    assert!(run.stdout.is_empty());
    assert!(run.stderr.is_empty());
}

#[test]
fn the_mock_refuses_a_wrong_flag() {
    let name = unique_pipe_name();
    let run = run_mock_direct(&[&format!("--from-stdin={name}")], &[]);
    assert_eq!(run.code, Some(12));
}

#[test]
fn the_mock_refuses_a_pipe_name_outside_the_pattern() {
    let run = run_mock_direct(&[r"--from-launcher=\\.\pipe\not-ours"], &[]);
    assert_eq!(run.code, Some(12));
}

#[test]
fn the_early_env_exits_before_the_pipe_is_opened() {
    // No pipe exists under this name, so reaching the open would exit 12.
    let name = unique_pipe_name();
    let run = run_mock_direct(&[&launch_argument(&name)], &[("MOCK_CONNECT_EARLY", "16")]);
    assert_eq!(run.code, Some(16));
}

#[test]
fn the_early_env_does_not_skip_the_argv_check() {
    let run = run_mock_direct(&["--from-launcher=bad"], &[("MOCK_CONNECT_EARLY", "16")]);
    assert_eq!(run.code, Some(12));
}

#[test]
fn the_mock_refuses_a_bad_line() {
    let run = run_mock_with_bytes(b"nope\n");
    assert_eq!(run.code, Some(12));
    assert!(run.stdout.is_empty());
    assert!(run.stderr.is_empty());

    let run = run_mock_with_bytes(b"rr1.a b\n");
    assert_eq!(run.code, Some(12));
    assert!(run.stdout.is_empty());
    assert!(run.stderr.is_empty());
}

#[test]
fn the_mock_refuses_an_over_long_line() {
    let mut line = b"rr1.".to_vec();
    line.resize(4097, b'x');
    assert_eq!(line.len(), 4097);
    let run = run_mock_with_bytes(&line);
    assert_eq!(run.code, Some(12));
    assert!(run.stdout.is_empty());
    assert!(run.stderr.is_empty());
}

#[test]
fn the_mock_accepts_a_line_ended_by_the_end_of_the_stream() {
    let run = run_mock_with_bytes(b"rr1.exit16");
    assert_eq!(run.code, Some(16));
    assert!(run.stdout.is_empty());
    assert!(run.stderr.is_empty());
}

#[test]
fn the_mock_writes_nothing_back() {
    let run = run_mock_with_bytes(b"rr1.exit0\n");
    assert_eq!(run.code, Some(0));
    assert!(run.stdout.is_empty());
    assert!(run.stderr.is_empty());
}

#[test]
fn an_over_long_code_is_refused_before_the_child_starts() {
    let code = format!("rr1.{}", "x".repeat(4093));
    assert_eq!(code.len(), 4097);
    let outcome = start_connect(mock_path(), &code, TEST_TIMEOUT);
    assert!(
        matches!(outcome, Err(ConnectError::Code(CodeError::TooLong))),
        "{outcome:?}"
    );
}

#[test]
fn a_timeout_kills_the_child_and_reports_timeout() {
    let start = Instant::now();
    let outcome = start_connect(mock_path(), "rr1.sleep5000", Duration::from_millis(200));
    assert!(matches!(outcome, Err(ConnectError::Timeout)), "{outcome:?}");
    let elapsed = start.elapsed();
    assert!(
        elapsed < Duration::from_secs(3),
        "the child should be killed, not waited out"
    );
}

#[test]
fn a_child_that_exits_before_it_connects_reports_its_exit_code() {
    // MOCK_CONNECT_EARLY makes the mock exit 12 before it opens the pipe. The
    // handoff must report that exit code, not wait for a client.
    let outcome = start_connect_with_env(
        mock_path(),
        "rr1.exit0",
        TEST_TIMEOUT,
        &[("MOCK_CONNECT_EARLY", "12")],
    );
    assert!(matches!(outcome, Ok(Outcome::Refused)), "{outcome:?}");

    let outcome = start_connect_with_env(
        mock_path(),
        "rr1.exit0",
        TEST_TIMEOUT,
        &[("MOCK_CONNECT_EARLY", "16")],
    );
    assert!(
        matches!(outcome, Ok(Outcome::DeclineAccepted)),
        "{outcome:?}"
    );
}

#[test]
fn a_client_that_is_not_the_expected_process_is_refused_without_a_write() {
    // The test process is the client, and the expected pid is another one,
    // so the server must refuse before writing a byte.
    let name = unique_pipe_name();
    let own_pid = std::process::id();
    let expected = own_pid.wrapping_add(1);
    let server_name = name.clone();
    let server =
        thread::spawn(move || serve_for_test(&server_name, b"rr1.exit0\n", expected, TEST_TIMEOUT));

    let mut client = connect_as_client(&name);
    let mut received = Vec::new();
    let _ = client.read_to_end(&mut received);
    assert!(received.is_empty(), "{received:?}");

    let handoff = server
        .join()
        .expect("the server thread should not panic")
        .expect("the handoff should not fail");
    assert!(
        matches!(handoff, Handoff::Mismatch { got } if got == own_pid),
        "{handoff:?}"
    );
}

#[test]
fn the_expected_client_reads_the_whole_line_and_the_handoff_completes() {
    let name = unique_pipe_name();
    let own_pid = std::process::id();
    let server_name = name.clone();
    let server =
        thread::spawn(move || serve_for_test(&server_name, b"rr1.exit0\n", own_pid, TEST_TIMEOUT));

    let mut client = connect_as_client(&name);
    let mut line = [0u8; 10];
    client
        .read_exact(&mut line)
        .expect("the whole line should arrive");
    assert_eq!(&line, b"rr1.exit0\n");

    let handoff = server
        .join()
        .expect("the server thread should not panic")
        .expect("the handoff should not fail");
    assert!(matches!(handoff, Handoff::Written), "{handoff:?}");
}

#[test]
fn a_second_create_with_the_same_name_fails() {
    let name = unique_pipe_name();
    let first = ServerPipe::create(&name).expect("the first create should succeed");
    let second = ServerPipe::create(&name);
    assert!(second.is_err(), "a second instance must not be created");
    drop(first);
}

#[test]
fn a_missing_executable_is_an_io_error() {
    let missing = mock_path().with_file_name("definitely-not-a-connect-binary");
    let outcome = start_connect(&missing, "rr1.exit0", TEST_TIMEOUT);
    assert!(matches!(outcome, Err(ConnectError::Io(_))), "{outcome:?}");
}

#[test]
fn a_relative_executable_is_refused_without_spawning() {
    let outcome = start_connect(Path::new("mock-connect"), "rr1.exit0", TEST_TIMEOUT);
    assert!(
        matches!(outcome, Err(ConnectError::NotAbsolute)),
        "{outcome:?}"
    );
}
