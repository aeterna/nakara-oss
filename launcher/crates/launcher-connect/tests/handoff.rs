// SPDX-License-Identifier: MIT

#![cfg(feature = "mock")]

//! Integration tests for the handoff contract v1 (ADR 0002 decision 8),
//! driving `src/bin/mock-connect.rs` through `start_connect`.
//!
//! Run with: `cargo test -p launcher-connect --features mock`

use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use launcher_connect::{start_connect, CodeError, ConnectError, Outcome};

fn mock_path() -> &'static Path {
    Path::new(env!("CARGO_BIN_EXE_mock-connect"))
}

/// Run Connect through the real handoff: start it, write the code, map the
/// exit code.
fn run_connect(code: &str) -> Result<Outcome, ConnectError> {
    start_connect(mock_path(), code, None)
}

/// Run the mock binary directly: feed `stdin_text` (read by the mock before
/// it answers), then collect its exit code and everything it wrote to stdout
/// and stderr.
fn run_mock_raw(args: &[&str], stdin_text: &[u8]) -> (Option<i32>, Vec<u8>, Vec<u8>) {
    let mut child = Command::new(mock_path())
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("mock-connect should spawn");
    child
        .stdin
        .take()
        .expect("piped stdin should be captured")
        .write_all(stdin_text)
        .expect("mock-connect should accept the line while it reads");
    let output = child
        .wait_with_output()
        .expect("mock-connect should finish");
    (output.status.code(), output.stdout, output.stderr)
}

/// Run the mock binary directly without writing to stdin: for the argv
/// refusals, where the mock exits before it reads.
fn run_mock_raw_no_input(args: &[&str]) -> (Option<i32>, Vec<u8>, Vec<u8>) {
    let mut child = Command::new(mock_path())
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("mock-connect should spawn");
    drop(child.stdin.take());
    let output = child
        .wait_with_output()
        .expect("mock-connect should finish");
    (output.status.code(), output.stdout, output.stderr)
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
fn the_mock_refuses_any_other_argument() {
    let (code, out, err) = run_mock_raw_no_input(&["--from-launcher", "extra"]);
    assert_eq!(code, Some(12));
    assert!(out.is_empty());
    assert!(err.is_empty());
}

#[test]
fn the_mock_refuses_a_missing_argument() {
    let (code, out, err) = run_mock_raw_no_input(&[]);
    assert_eq!(code, Some(12));
    assert!(out.is_empty());
    assert!(err.is_empty());
}

#[test]
fn the_mock_refuses_a_bad_line() {
    let (code, out, err) = run_mock_raw(&["--from-launcher"], b"nope\n");
    assert_eq!(code, Some(12));
    assert!(out.is_empty());
    assert!(err.is_empty());

    let (code, out, err) = run_mock_raw(&["--from-launcher"], b"rr1.a b\n");
    assert_eq!(code, Some(12));
    assert!(out.is_empty());
    assert!(err.is_empty());
}

#[test]
fn the_mock_refuses_an_over_long_line() {
    let mut line = b"rr1.".to_vec();
    line.resize(4097, b'x');
    assert_eq!(line.len(), 4097);
    let (code, out, err) = run_mock_raw(&["--from-launcher"], &line);
    assert_eq!(code, Some(12));
    assert!(out.is_empty());
    assert!(err.is_empty());
}

#[test]
fn the_mock_accepts_a_line_ended_by_eof() {
    let (code, out, err) = run_mock_raw(&["--from-launcher"], b"rr1.exit16");
    assert_eq!(code, Some(16));
    assert!(out.is_empty());
    assert!(err.is_empty());
}

#[test]
fn the_mock_writes_nothing_back() {
    let (_, out, err) = run_mock_raw(&["--from-launcher"], b"rr1.exit0\n");
    assert!(out.is_empty());
    assert!(err.is_empty());
}

#[test]
fn an_over_long_code_is_refused_before_the_child_starts() {
    let code = format!("rr1.{}", "x".repeat(4093));
    assert_eq!(code.len(), 4097);
    let outcome = start_connect(mock_path(), &code, None);
    assert!(
        matches!(outcome, Err(ConnectError::Code(CodeError::TooLong))),
        "{outcome:?}"
    );
}

#[test]
fn a_timeout_kills_the_child_and_reports_timeout() {
    let start = Instant::now();
    let outcome = start_connect(
        mock_path(),
        "rr1.sleep5000",
        Some(Duration::from_millis(200)),
    );
    assert!(matches!(outcome, Err(ConnectError::Timeout)), "{outcome:?}");
    let elapsed = start.elapsed();
    assert!(
        elapsed < Duration::from_secs(3),
        "the child should be killed, not waited out"
    );
}

#[test]
fn a_missing_executable_is_an_io_error() {
    let outcome = start_connect(
        Path::new("definitely-not-a-connect-binary"),
        "rr1.exit0",
        None,
    );
    assert!(matches!(outcome, Err(ConnectError::Io(_))), "{outcome:?}");
}
