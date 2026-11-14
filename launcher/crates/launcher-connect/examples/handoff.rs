// SPDX-License-Identifier: MIT

//! Handoff driver for the K4 spike (ADR 0002 decision 8): start Rongroi
//! Connect with a pairing code read from a file, then print the outcome and
//! the raw exit code.
//!
//! Usage:
//!
//! ```text
//! cargo run -p launcher-connect --example handoff -- <connect.exe> <code-file>
//! ```
//!
//! The file holds the `rr1.` code; a trailing `\n` or `\r` is ignored. The
//! Connect path must be absolute, and the driver waits up to 30 minutes for
//! Connect to exit. The launcher never retries a code by itself: run it again
//! by hand if needed.

use std::path::Path;
use std::process::exit;
use std::time::Duration;

use launcher_connect::start_connect;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 3 {
        eprintln!("usage: handoff <connect.exe> <code-file>");
        exit(2);
    }
    let code = match std::fs::read_to_string(&args[2]) {
        Ok(code) => code,
        Err(err) => {
            eprintln!("handoff: cannot read {}: {err}", args[2]);
            exit(2);
        }
    };
    let code = code.trim_end_matches(['\r', '\n']);

    match start_connect(Path::new(&args[1]), code, Duration::from_secs(30 * 60)) {
        Ok(outcome) => {
            println!("{outcome:?}");
            match outcome.exit_code() {
                Some(exit_code) => println!("exit code: {exit_code}"),
                None => println!("exit code: none (killed by a signal)"),
            }
        }
        Err(err) => {
            eprintln!("handoff: {err}");
            exit(1);
        }
    }
}
