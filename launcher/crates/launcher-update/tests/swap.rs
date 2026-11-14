// SPDX-License-Identifier: MIT

use launcher_update::{old_path, rollback, swap_exe, UpdateError};
use std::fs;
use std::path::{Path, PathBuf};
use tempfile::tempdir;

fn write(dir: &Path, name: &str, content: &[u8]) -> PathBuf {
    let path = dir.join(name);
    fs::write(&path, content).unwrap();
    path
}

#[test]
fn swaps_the_new_exe_in_and_keeps_the_old_one() {
    let dir = tempdir().unwrap();
    let current = write(dir.path(), "launcher.exe", b"old exe");
    let new = write(dir.path(), "download.exe", b"new exe");

    swap_exe(&current, &new).unwrap();

    assert_eq!(fs::read(&current).unwrap(), b"new exe");
    let old = old_path(&current);
    assert_eq!(old, dir.path().join("launcher.exe.old"));
    assert_eq!(fs::read(&old).unwrap(), b"old exe");
    assert!(!new.exists());
}

#[test]
fn replaces_an_older_old_file() {
    let dir = tempdir().unwrap();
    let current = write(dir.path(), "launcher.exe", b"old exe");
    let new = write(dir.path(), "download.exe", b"new exe");
    fs::write(old_path(&current), b"ancient exe").unwrap();

    swap_exe(&current, &new).unwrap();

    assert_eq!(fs::read(old_path(&current)).unwrap(), b"old exe");
}

#[test]
fn restores_the_old_exe_when_the_new_one_cannot_be_moved() {
    let dir = tempdir().unwrap();
    let current = write(dir.path(), "launcher.exe", b"old exe");
    let new = dir.path().join("download.exe");

    assert!(swap_exe(&current, &new).is_err());

    assert_eq!(fs::read(&current).unwrap(), b"old exe");
    assert!(!old_path(&current).exists());
}

#[test]
fn fails_before_moving_anything_when_the_new_exe_is_missing() {
    let dir = tempdir().unwrap();
    let current = write(dir.path(), "launcher.exe", b"old exe");
    let new = dir.path().join("download.exe");

    let err = swap_exe(&current, &new).unwrap_err();

    assert!(matches!(err, UpdateError::NewNotFile { .. }));
    assert_eq!(fs::read(&current).unwrap(), b"old exe");
    assert!(!old_path(&current).exists());
    assert!(!new.exists());
}

#[test]
fn refuses_a_new_exe_in_another_directory() {
    let current_dir = tempdir().unwrap();
    let new_dir = tempdir().unwrap();
    let current = write(current_dir.path(), "launcher.exe", b"old exe");
    let new = write(new_dir.path(), "download.exe", b"new exe");

    let err = swap_exe(&current, &new).unwrap_err();

    assert!(matches!(err, UpdateError::DifferentParents { .. }));
    assert_eq!(fs::read(&current).unwrap(), b"old exe");
    assert!(!old_path(&current).exists());
    assert_eq!(fs::read(&new).unwrap(), b"new exe");
}

#[test]
fn fails_when_the_current_exe_is_missing() {
    let dir = tempdir().unwrap();
    let current = dir.path().join("launcher.exe");
    let new = write(dir.path(), "download.exe", b"new exe");

    assert!(swap_exe(&current, &new).is_err());

    assert!(new.exists());
    assert!(!old_path(&current).exists());
}

#[test]
fn rollback_puts_the_old_exe_back() {
    let dir = tempdir().unwrap();
    let current = write(dir.path(), "launcher.exe", b"broken exe");
    fs::write(old_path(&current), b"good exe").unwrap();

    rollback(&current).unwrap();

    assert_eq!(fs::read(&current).unwrap(), b"good exe");
    assert!(!old_path(&current).exists());
}

#[test]
fn rollback_fails_without_an_old_file() {
    let dir = tempdir().unwrap();
    let current = write(dir.path(), "launcher.exe", b"current exe");

    assert!(rollback(&current).is_err());

    assert_eq!(fs::read(&current).unwrap(), b"current exe");
}
