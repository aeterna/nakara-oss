// SPDX-License-Identifier: MIT

//! Check a `server.toml` before building the launcher.
//!
//! Usage: `profile-check <path/to/server.toml> [--root <dir>]`. The root
//! defaults to the folder holding the profile.

use std::path::{Path, PathBuf};

use launcher_core::check::check_parsed;

fn main() {
    std::process::exit(run(std::env::args().skip(1).collect()));
}

fn run(args: Vec<String>) -> i32 {
    let mut path: Option<String> = None;
    let mut root: Option<PathBuf> = None;
    let mut args = args.into_iter();

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--root" => {
                if root.is_some() {
                    return usage_error("--root given more than once");
                }
                match args.next() {
                    Some(value) => root = Some(PathBuf::from(value)),
                    None => return usage_error("--root needs a directory"),
                }
            }
            _ if arg.starts_with('-') => {
                return usage_error(&format!("unknown option {arg}"));
            }
            _ => {
                if path.is_some() {
                    return usage_error("expected one profile path");
                }
                path = Some(arg);
            }
        }
    }

    let Some(path) = path else {
        return usage_error("missing <path/to/server.toml>");
    };

    let text = match std::fs::read_to_string(&path) {
        Ok(text) => text,
        Err(error) => {
            eprintln!("error: cannot read {path}: {error}");
            return 2;
        }
    };

    let root = root.unwrap_or_else(|| {
        Path::new(&path)
            .parent()
            .filter(|p| !p.as_os_str().is_empty())
            .map(Path::to_path_buf)
            .unwrap_or_else(|| PathBuf::from("."))
    });

    let profile = match launcher_core::parse(&text) {
        Ok(profile) => profile,
        Err(error) => {
            eprintln!("error: {error}");
            return 1;
        }
    };

    let report = check_parsed(&profile, &root);
    for error in &report.errors {
        println!("error: {error}");
    }
    for warning in &report.warnings {
        println!("warning: {warning}");
    }

    if !report.errors.is_empty() {
        return 1;
    }

    println!("OK: {} ({})", profile.server.name, profile.server.id);
    0
}

fn usage_error(message: &str) -> i32 {
    eprintln!("error: {message}");
    eprintln!("usage: profile-check <path/to/server.toml> [--root <dir>]");
    2
}
