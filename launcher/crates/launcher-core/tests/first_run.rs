// SPDX-License-Identifier: MIT

use launcher_core::first_run::{mark_seen, marker_path, seen};
use std::path::PathBuf;

fn test_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "launcher-first-run-{name}-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&dir);
    dir
}

fn write_marker(dir: &std::path::Path, content: &str) {
    std::fs::create_dir_all(dir).expect("test directory should be created");
    std::fs::write(marker_path(dir), content).expect("marker should be written");
}

#[test]
fn fresh_missing_directory_is_not_seen() {
    let dir = test_dir("fresh_missing_directory_is_not_seen");

    assert!(!seen(&dir));

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn mark_seen_creates_marker_for_missing_directory() {
    let dir = test_dir("mark_seen_creates_marker_for_missing_directory");

    mark_seen(&dir).expect("marker should be written");

    assert!(seen(&dir));
    let content = std::fs::read_to_string(marker_path(&dir)).expect("marker should be readable");
    assert_eq!(content, "1");

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn old_version_is_not_seen() {
    let dir = test_dir("old_version_is_not_seen");
    write_marker(&dir, "0");

    assert!(!seen(&dir));

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn garbage_content_is_not_seen() {
    let dir = test_dir("garbage_content_is_not_seen");
    write_marker(&dir, "garbage");

    assert!(!seen(&dir));

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn whitespace_is_trimmed() {
    let dir = test_dir("whitespace_is_trimmed");
    write_marker(&dir, "  1\n");

    assert!(seen(&dir));

    let _ = std::fs::remove_dir_all(&dir);
}
