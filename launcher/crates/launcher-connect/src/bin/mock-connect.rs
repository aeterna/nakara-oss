// SPDX-License-Identifier: MIT

//! A mock of Rongroi Connect for the handoff integration tests.
//!
//! Built only with the `mock` feature:
//! `cargo test -p launcher-connect --features mock`.
//!
//! It follows the handoff contract v1 (Connect ADR 0002) as far as the tests
//! need it. On Windows its argv must be exactly one
//! `--from-launcher=<pipe name>` with a valid pipe name, or it exits 12. It
//! then reads one line from that named pipe, at most 4097 bytes, ended by
//! `\n` or the end of the stream, and writes nothing back. A line names its
//! exit code after `rr1.exit` (`rr1.exit16` exits 16; no directive exits 0)
//! and may delay the exit with `rr1.sleep<N>` (N milliseconds, for the
//! launcher's timeout test). Any other line exits 12 (refused).
//!
//! `MOCK_CONNECT_EARLY=<n>` makes the mock exit n straight away, after the
//! argv check and before it opens the pipe. Other targets exit 12.

/// Process exit code for every refusal.
const REFUSED: i32 = 12;

fn main() {
    std::process::exit(run());
}

/// Other targets have no named pipes, so the mock always refuses.
#[cfg(not(windows))]
fn run() -> i32 {
    REFUSED
}

#[cfg(windows)]
fn run() -> i32 {
    use launcher_connect::is_launch_pipe_name;

    let args: Vec<String> = std::env::args().collect();
    let name = match args.as_slice() {
        [_, arg] => match arg.strip_prefix(FLAG) {
            Some(name) => name,
            None => return REFUSED,
        },
        _ => return REFUSED,
    };
    if !is_launch_pipe_name(name) {
        return REFUSED;
    }
    if let Ok(value) = std::env::var(EARLY_ENV) {
        return value.parse::<i32>().unwrap_or(REFUSED);
    }
    match read_line(name) {
        Some(line) => answer(&line),
        None => REFUSED,
    }
}

/// The flag that carries the pipe name.
#[cfg(windows)]
const FLAG: &str = "--from-launcher=";

/// The variable that makes the mock exit early with its value.
#[cfg(windows)]
const EARLY_ENV: &str = "MOCK_CONNECT_EARLY";

/// Read cap: one line of at most 4096 code bytes plus one `\n`.
#[cfg(windows)]
const LINE_LIMIT: u64 = 4097;

/// Win32 error for a pipe whose client end has gone.
#[cfg(windows)]
const ERROR_BROKEN_PIPE: i32 = 109;

/// Win32 error for a pipe that is not connected.
#[cfg(windows)]
const ERROR_PIPE_NOT_CONNECTED: i32 = 233;

/// Win32 error for a pipe with no free instance yet.
#[cfg(windows)]
const ERROR_PIPE_BUSY: i32 = 231;

/// How long the mock keeps retrying a busy pipe.
#[cfg(windows)]
const OPEN_RETRY: std::time::Duration = std::time::Duration::from_secs(5);

/// Read one line from the pipe, at most `LINE_LIMIT` bytes, ended by `\n` or
/// the end of the stream. Extra input after the first line is ignored. None
/// means the pipe could not be opened or read, or the line is not UTF-8. An
/// over-long line is left for the code check.
#[cfg(windows)]
fn read_line(name: &str) -> Option<String> {
    use std::io::{BufRead, BufReader, Read};

    let pipe = open_pipe(name)?;
    let mut buf = Vec::new();
    let mut reader = BufReader::new(pipe.take(LINE_LIMIT));
    match reader.read_until(b'\n', &mut buf) {
        Ok(_) => {}
        // The server disconnects after the last byte, which ends the stream.
        Err(err)
            if err.raw_os_error() == Some(ERROR_BROKEN_PIPE)
                || err.raw_os_error() == Some(ERROR_PIPE_NOT_CONNECTED) => {}
        Err(_) => return None,
    }
    let text = std::str::from_utf8(&buf).ok()?;
    Some(text.strip_suffix('\n').unwrap_or(text).to_owned())
}

/// Open the pipe for reading. A busy pipe is retried for a short while.
#[cfg(windows)]
fn open_pipe(name: &str) -> Option<std::fs::File> {
    use std::fs::OpenOptions;

    let deadline = std::time::Instant::now() + OPEN_RETRY;
    loop {
        match OpenOptions::new().read(true).open(name) {
            Ok(file) => return Some(file),
            Err(err)
                if err.raw_os_error() == Some(ERROR_PIPE_BUSY)
                    && std::time::Instant::now() < deadline =>
            {
                std::thread::sleep(std::time::Duration::from_millis(10));
            }
            Err(_) => return None,
        }
    }
}

/// Validate the line, then work out the exit code and optional delay from it.
#[cfg(windows)]
fn answer(line: &str) -> i32 {
    use std::time::Duration;

    if launcher_connect::validate_code(line).is_err() {
        return REFUSED;
    }
    let mut exit_code = 0;
    if let Some(digits) = digits_after(line, "rr1.exit") {
        match digits.parse::<i32>() {
            Ok(code) => exit_code = code,
            Err(_) => return REFUSED,
        }
    }
    if let Some(ms) = digits_after(line, "rr1.sleep") {
        match ms.parse::<u64>() {
            Ok(millis) => std::thread::sleep(Duration::from_millis(millis)),
            Err(_) => return REFUSED,
        }
    }
    exit_code
}

/// ASCII digits directly after `name` in `line`, when the name is there and
/// is followed by at least one digit.
#[cfg(windows)]
fn digits_after<'a>(line: &'a str, name: &str) -> Option<&'a str> {
    let start = line.find(name)? + name.len();
    let rest = &line[start..];
    let end = rest
        .find(|c: char| !c.is_ascii_digit())
        .unwrap_or(rest.len());
    if end == 0 {
        return None; // a bare `rr1.exit` counts as no directive
    }
    Some(&rest[..end])
}
