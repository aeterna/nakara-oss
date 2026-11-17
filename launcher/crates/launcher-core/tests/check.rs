// SPDX-License-Identifier: MIT

use std::fs::{self, File};
use std::path::{Path, PathBuf};

use launcher_core::check::check_profile;

const EXAMPLE: &str = include_str!("../../../profiles/example/server.toml");
const FEED: &str = "https://feed.example.com/profile.json";
const UPDATE_KEY: &str = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";

fn example() -> String {
    EXAMPLE.replace("\r\n", "\n")
}

fn test_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("launcher-check-{name}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("test directory should be created");
    dir
}

fn replace_once(text: &str, from: &str, to: &str) -> String {
    assert!(text.contains(from), "fixture has no {from:?}");
    text.replacen(from, to, 1)
}

fn with_theme_line(line: &str) -> String {
    replace_once(&example(), "[theme]\n", &format!("[theme]\n{line}\n"))
}

fn with_server_fields(fields: &str) -> String {
    replace_once(
        &example(),
        "contact_email = \"team@example.com\"\n",
        &format!("contact_email = \"team@example.com\"\n{fields}\n"),
    )
}

fn write_asset(root: &Path, path: &str, len: u64) {
    let file = root.join(path);
    fs::create_dir_all(file.parent().expect("asset path should have a parent"))
        .expect("assets directory should be created");
    File::create(&file)
        .and_then(|file| file.set_len(len))
        .expect("asset file should be created");
}

#[test]
fn valid_example_has_no_errors() {
    let dir = test_dir("valid_example_has_no_errors");

    let report = check_profile(&example(), &dir);

    assert!(
        report.errors.is_empty(),
        "unexpected errors: {:?}",
        report.errors
    );
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn invalid_toml_reports_one_error_and_stops() {
    let dir = test_dir("invalid_toml_reports_one_error_and_stops");
    let text = replace_once(&example(), "schema = 1", "schema = [");

    let report = check_profile(&text, &dir);

    assert_eq!(report.errors.len(), 1);
    assert!(
        report.errors[0].starts_with("could not parse profile:"),
        "unexpected error: {:?}",
        report.errors
    );
    assert!(report.warnings.is_empty());
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn missing_wordmark_file_is_an_error() {
    let dir = test_dir("missing_wordmark_file_is_an_error");
    let text = with_theme_line("wordmark = \"assets/wordmark.png\"");

    let report = check_profile(&text, &dir);

    assert_eq!(
        report.errors,
        vec![format!(
            "theme.wordmark: file assets/wordmark.png not found under {}",
            dir.display()
        )]
    );
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn wordmark_directory_is_not_a_regular_file() {
    let dir = test_dir("wordmark_directory_is_not_a_regular_file");
    fs::create_dir_all(dir.join("assets/wordmark.png"))
        .expect("wordmark directory should be created");
    let text = with_theme_line("wordmark = \"assets/wordmark.png\"");

    let report = check_profile(&text, &dir);

    assert_eq!(
        report.errors,
        vec![format!(
            "theme.wordmark: assets/wordmark.png under {} is not a regular file",
            dir.display()
        )]
    );
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn assets_over_five_megabytes_are_an_error() {
    let dir = test_dir("assets_over_five_megabytes_are_an_error");
    let size = 5 * 1024 * 1024 + 1;
    write_asset(&dir, "assets/wordmark.png", size);
    let text = with_theme_line("wordmark = \"assets/wordmark.png\"");

    let report = check_profile(&text, &dir);

    assert_eq!(
        report.errors,
        vec![format!(
            "theme assets: total size {size} bytes is over the 5 MiB limit (5242880 bytes)"
        )]
    );
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn missing_feed_is_a_warning() {
    let dir = test_dir("missing_feed_is_a_warning");
    let text = with_server_fields(&format!(
        "release_repo = \"example/releases\"\nupdate_keys = [\"{UPDATE_KEY}\"]"
    ));

    let report = check_profile(&text, &dir);

    assert!(
        report.errors.is_empty(),
        "unexpected errors: {:?}",
        report.errors
    );
    assert_eq!(
        report.warnings,
        vec!["server.feed is not set: the Home page shows no news".to_string()]
    );
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn empty_update_keys_with_release_repo_is_a_warning() {
    let dir = test_dir("empty_update_keys_with_release_repo_is_a_warning");
    let text = with_server_fields(&format!(
        "feed = \"{FEED}\"\nrelease_repo = \"example/releases\""
    ));

    let report = check_profile(&text, &dir);

    assert!(
        report.errors.is_empty(),
        "unexpected errors: {:?}",
        report.errors
    );
    assert_eq!(
        report.warnings,
        vec!["server.update_keys is empty: the launcher will never report updates".to_string()]
    );
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn missing_release_repo_is_a_warning() {
    let dir = test_dir("missing_release_repo_is_a_warning");
    let text = with_server_fields(&format!("feed = \"{FEED}\""));

    let report = check_profile(&text, &dir);

    assert!(
        report.errors.is_empty(),
        "unexpected errors: {:?}",
        report.errors
    );
    assert_eq!(
        report.warnings,
        vec!["server.release_repo is not set: the launcher never checks for updates".to_string()]
    );
    let _ = fs::remove_dir_all(&dir);
}
