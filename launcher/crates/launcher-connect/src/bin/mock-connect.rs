// SPDX-License-Identifier: MIT

//! A mock of Rongroi Connect for the handoff integration tests.
//!
//! Built only with the `mock` feature:
//! `cargo test -p launcher-connect --features mock`.
//!
//! It follows the handoff contract v1 (Connect ADR 0002) as far as the tests
//! need it: argv exactly `--from-launcher`, one stdin line of at most 4097
//! bytes ended by `\n` or EOF, nothing written back, and the contract exit
//! codes. A line names its exit code after `rr1.exit` (`rr1.exit16` exits 16;
//! no directive exits 0) and may delay the exit with `rr1.sleep<N>` (N
//! milliseconds, for the launcher's timeout test). Any other line exits 12
//! (refused).
//!
//! A line that contains `rr1.early12` is refused with exit 12 as soon as those
//! bytes are read, before the rest of the line, so the caller's stdin write can
//! hit a closed pipe.

use std::io::Read;
use std::process::exit;
use std::thread::sleep;
use std::time::Duration;

/// Stdin read cap: one line of at most 4096 code bytes plus one `\n`.
const LINE_LIMIT: u64 = 4097;

/// A line containing this text is refused before the rest of stdin is read.
const EARLY_REFUSAL: &str = "rr1.early12";

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 2 || args[1] != "--from-launcher" {
        exit(12);
    }
    exit(match read_line() {
        Ok(line) => answer(&line),
        Err(()) => 12,
    });
}

/// Read one line from stdin, at most `LINE_LIMIT` bytes, ended by `\n` or
/// EOF. Extra input after the first line is ignored. Returns Err for invalid
/// UTF-8, a read error, or the early refusal; an over-long line is left for
/// the code check.
fn read_line() -> Result<String, ()> {
    let mut buf = Vec::new();
    let stdin = std::io::stdin().lock();
    let mut reader = stdin.take(LINE_LIMIT);
    let mut byte = [0u8; 1];
    loop {
        if reader.read(&mut byte).map_err(|_| ())? == 0 {
            break;
        }
        buf.push(byte[0]);
        if buf.ends_with(EARLY_REFUSAL.as_bytes()) {
            return Err(());
        }
        if byte[0] == b'\n' {
            break;
        }
    }
    let line = std::str::from_utf8(&buf).map_err(|_| ())?;
    let line = line.strip_suffix('\n').unwrap_or(line);
    Ok(line.to_owned())
}

/// Validate the line, then work out the exit code and optional delay from it.
fn answer(line: &str) -> i32 {
    if launcher_connect::validate_code(line).is_err() {
        return 12;
    }
    let mut exit_code = 0;
    if let Some(digits) = digits_after(line, "rr1.exit") {
        match digits.parse::<i32>() {
            Ok(code) => exit_code = code,
            Err(_) => return 12,
        }
    }
    if let Some(ms) = digits_after(line, "rr1.sleep") {
        match ms.parse::<u64>() {
            Ok(millis) => sleep(Duration::from_millis(millis)),
            Err(_) => return 12,
        }
    }
    exit_code
}

/// ASCII digits directly after `name` in `line`, when the name is there and
/// is followed by at least one digit.
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
