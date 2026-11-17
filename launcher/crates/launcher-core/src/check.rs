// SPDX-License-Identifier: MIT

//! A friendly pre-build check for a `server.toml`.
//!
//! Unlike [`crate::parse`], this also looks at the files the theme references,
//! so owners can fix a profile before `launcher-ui/build.rs` fails on it.

use std::path::Path;

/// Errors fail the check; warnings only point at likely surprises.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Report {
    pub errors: Vec<String>,
    pub warnings: Vec<String>,
}

/// Maximum total size of the referenced theme assets (ADR 0002 decision 11).
const MAX_ASSET_BYTES: u64 = 5 * 1024 * 1024;

/// Parse `text` and check the theme files it references under `root`.
///
/// Asset paths are resolved relative to `root`, the folder that holds the
/// launcher's `server.toml`. Missing files and a total size over 5 MiB are
/// errors; the returned warnings never make the profile invalid.
pub fn check_profile(text: &str, root: &Path) -> Report {
    let mut report = Report::default();

    let profile = match crate::parse(text) {
        Ok(profile) => profile,
        Err(error) => {
            report.errors.push(error.to_string());
            return report;
        }
    };

    check_parsed(&profile, root)
}

/// Check the theme files and warnings for an already-parsed `profile` under `root`.
///
/// This is everything [`check_profile`] does after parsing, for callers that
/// already have a [`crate::Profile`] and do not want to parse it twice.
pub fn check_parsed(profile: &crate::Profile, root: &Path) -> Report {
    let mut report = Report::default();

    let mut total: u64 = 0;
    for (field, path) in [
        ("theme.wordmark", profile.theme.wordmark.as_deref()),
        ("theme.background", profile.theme.background.as_deref()),
    ] {
        let Some(path) = path else {
            continue;
        };
        match std::fs::metadata(root.join(path)) {
            Ok(metadata) if metadata.is_file() => total = total.saturating_add(metadata.len()),
            Ok(_) => report.errors.push(format!(
                "{field}: {path} under {} is not a regular file",
                root.display()
            )),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => report.errors.push(
                format!("{field}: file {path} not found under {}", root.display()),
            ),
            Err(error) => report.errors.push(format!(
                "{field}: cannot read {path} under {}: {error}",
                root.display()
            )),
        }
    }

    if total > MAX_ASSET_BYTES {
        report.errors.push(format!(
            "theme assets: total size {total} bytes is over the 5 MiB limit (5242880 bytes)"
        ));
    }

    let server = &profile.server;
    if server.feed.is_none() {
        report
            .warnings
            .push("server.feed is not set: the Home page shows no news".to_string());
    }
    if server.release_repo.is_some() && server.update_keys.is_empty() {
        report.warnings.push(
            "server.update_keys is empty: the launcher will never report updates".to_string(),
        );
    }
    if server.release_repo.is_none() {
        report.warnings.push(
            "server.release_repo is not set: the launcher never checks for updates".to_string(),
        );
    }

    report
}
