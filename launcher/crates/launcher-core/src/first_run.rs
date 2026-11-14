// SPDX-License-Identifier: MIT

//! Remembers that the player has read the first-run privacy notice. The marker is a local file; nothing is sent anywhere.

use std::path::{Path, PathBuf};

/// Bump when the notice text changes so players see it again.
pub const NOTICE_VERSION: u32 = 1;

const MARKER_NAME: &str = "privacy-notice-seen";
const TEMP_NAME: &str = "privacy-notice-seen.tmp";

/// The marker file inside `dir`.
pub fn marker_path(dir: &Path) -> PathBuf {
    dir.join(MARKER_NAME)
}

/// Whether the current notice version has been seen.
///
/// True only when the marker exists and its trimmed content parses as a
/// version at least [`NOTICE_VERSION`]. Any read error or bad content is false.
pub fn seen(dir: &Path) -> bool {
    let content = match std::fs::read_to_string(marker_path(dir)) {
        Ok(content) => content,
        Err(_) => return false,
    };
    match content.trim().parse::<u32>() {
        Ok(version) => version >= NOTICE_VERSION,
        Err(_) => false,
    }
}

/// Records that the current notice version has been seen.
///
/// Writes a sibling temporary file and renames it over the marker so a
/// partially written marker is never observed.
pub fn mark_seen(dir: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(dir)?;
    let temp = dir.join(TEMP_NAME);
    std::fs::write(&temp, NOTICE_VERSION.to_string())?;
    std::fs::rename(temp, marker_path(dir))
}
