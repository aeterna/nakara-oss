// SPDX-License-Identifier: MIT

use ed25519_dalek::{Signer, SigningKey, VerifyingKey};
use launcher_update::manifest::{MAX_FILE_BYTES, MAX_TOTAL_BYTES};
use launcher_update::{verify_file, verify_manifest, Channel, FileEntry, UpdateError, Verified};
use semver::Version;
use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};
use tempfile::tempdir;
use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;

const SEED_A: [u8; 32] = [7; 32];
const SEED_B: [u8; 32] = [11; 32];
const DIGEST: &str = "0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f";
const EXPIRES: &str = "2030-01-01T00:00:00Z";
const PRODUCT: &str = "aeterna";

fn key_bytes(seed: [u8; 32]) -> [u8; 32] {
    SigningKey::from_bytes(&seed).verifying_key().to_bytes()
}

fn signed(seed: [u8; 32], manifest: &[u8]) -> Vec<u8> {
    SigningKey::from_bytes(&seed)
        .sign(manifest)
        .to_bytes()
        .to_vec()
}

fn entry(name: &str, sha256: &str, size: u64) -> String {
    format!(r#"{{"name":"{name}","sha256":"{sha256}","size":{size}}}"#)
}

fn manifest(
    expires: &str,
    version: &str,
    product: &str,
    channel: &str,
    files: &[String],
) -> String {
    format!(
        r#"{{"schema":1,"product":"{product}","version":"{version}","channel":"{channel}","expires":"{expires}","files":[{}]}}"#,
        files.join(",")
    )
}

fn good_manifest(version: &str) -> String {
    manifest(
        EXPIRES,
        version,
        PRODUCT,
        "stable",
        &[entry("launcher.exe", DIGEST, 5)],
    )
}

fn current() -> Version {
    Version::parse("1.2.2").unwrap()
}

fn now() -> OffsetDateTime {
    OffsetDateTime::parse("2026-01-01T00:00:00Z", &Rfc3339).unwrap()
}

fn keys() -> [[u8; 32]; 1] {
    [key_bytes(SEED_A)]
}

fn verify(bytes: &[u8]) -> Result<Verified, UpdateError> {
    verify_manifest(
        bytes,
        &signed(SEED_A, bytes),
        &keys(),
        PRODUCT,
        &current(),
        Channel::Stable,
        now(),
    )
}

fn invalid_public_key() -> [u8; 32] {
    for prefix in 0..=u8::MAX {
        let mut key = [0u8; 32];
        key[0] = prefix;
        if VerifyingKey::from_bytes(&key).is_err() {
            return key;
        }
    }
    panic!("no invalid ed25519 public key found");
}

fn write_file(dir: &Path, name: &str, content: &[u8]) -> PathBuf {
    let path = dir.join(name);
    std::fs::write(&path, content).unwrap();
    path
}

fn sha256_hex(content: &[u8]) -> String {
    Sha256::digest(content)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

#[test]
fn accepts_a_signed_manifest() {
    let verified = verify(good_manifest("1.2.3").as_bytes()).unwrap();

    assert_eq!(verified.schema, 1);
    assert_eq!(verified.product, "aeterna");
    assert_eq!(verified.version, Version::parse("1.2.3").unwrap());
    assert_eq!(verified.channel, Channel::Stable);
    assert_eq!(
        verified.expires,
        OffsetDateTime::parse(EXPIRES, &Rfc3339).unwrap()
    );
    assert_eq!(verified.files.len(), 1);
    assert_eq!(verified.files[0].name, "launcher.exe");
    assert_eq!(verified.files[0].sha256, DIGEST);
    assert_eq!(verified.files[0].size, 5);
}

#[test]
fn accepts_when_the_second_key_signs() {
    let bytes = good_manifest("1.2.3");

    let verified = verify_manifest(
        bytes.as_bytes(),
        &signed(SEED_A, bytes.as_bytes()),
        &[key_bytes(SEED_B), key_bytes(SEED_A)],
        PRODUCT,
        &current(),
        Channel::Stable,
        now(),
    )
    .unwrap();

    assert_eq!(verified.version, Version::parse("1.2.3").unwrap());
}

#[test]
fn accepts_a_manifest_of_exactly_64_kib() {
    let mut bytes = good_manifest("1.2.3").into_bytes();
    bytes.resize(64 * 1024, b' ');

    let verified = verify_manifest(
        &bytes,
        &signed(SEED_A, &bytes),
        &keys(),
        PRODUCT,
        &current(),
        Channel::Stable,
        now(),
    )
    .unwrap();

    assert_eq!(verified.version, Version::parse("1.2.3").unwrap());
}

#[test]
fn rejects_a_wrong_signature() {
    let bytes = good_manifest("1.2.3");
    let mut sig = signed(SEED_A, bytes.as_bytes());
    sig[0] ^= 0xff;

    let err = verify_manifest(
        bytes.as_bytes(),
        &sig,
        &keys(),
        PRODUCT,
        &current(),
        Channel::Stable,
        now(),
    )
    .unwrap_err();

    assert!(matches!(err, UpdateError::Signature));
}

#[test]
fn rejects_a_signature_that_is_not_64_bytes() {
    let bytes = good_manifest("1.2.3");
    let sig = signed(SEED_A, bytes.as_bytes());

    let err = verify_manifest(
        bytes.as_bytes(),
        &sig[..63],
        &keys(),
        PRODUCT,
        &current(),
        Channel::Stable,
        now(),
    )
    .unwrap_err();

    assert!(matches!(err, UpdateError::Signature));
}

#[test]
fn rejects_a_manifest_signed_by_an_unknown_key() {
    let bytes = good_manifest("1.2.3");

    let err = verify_manifest(
        bytes.as_bytes(),
        &signed(SEED_A, bytes.as_bytes()),
        &[key_bytes(SEED_B)],
        PRODUCT,
        &current(),
        Channel::Stable,
        now(),
    )
    .unwrap_err();

    assert!(matches!(err, UpdateError::Signature));
}

#[test]
fn rejects_an_invalid_public_key() {
    let bytes = good_manifest("1.2.3");

    let err = verify_manifest(
        bytes.as_bytes(),
        &signed(SEED_A, bytes.as_bytes()),
        &[invalid_public_key()],
        PRODUCT,
        &current(),
        Channel::Stable,
        now(),
    )
    .unwrap_err();

    assert!(matches!(err, UpdateError::Key));
}

#[test]
fn rejects_unknown_fields() {
    let bytes =
        br#"{"schema":1,"product":"aeterna","version":"1.2.3","channel":"stable","expires":"2030-01-01T00:00:00Z","files":[],"note":"extra"}"#;

    let err = verify(bytes).unwrap_err();

    assert!(matches!(err, UpdateError::Manifest(_)));
}

#[test]
fn rejects_malformed_json() {
    let err = verify(b"{not json").unwrap_err();

    assert!(matches!(err, UpdateError::Manifest(_)));
}

#[test]
fn rejects_a_schema_other_than_1() {
    let bytes = r#"{"schema":2,"product":"aeterna","version":"1.2.3","channel":"stable","expires":"2030-01-01T00:00:00Z","files":[]}"#;

    let err = verify(bytes.as_bytes()).unwrap_err();

    assert_eq!(err, UpdateError::Schema(2));
}

#[test]
fn rejects_a_wrong_product() {
    let bytes = manifest(EXPIRES, "1.2.3", "other", "stable", &[]);

    let err = verify(bytes.as_bytes()).unwrap_err();

    assert_eq!(
        err,
        UpdateError::Product {
            expected: "aeterna".to_owned(),
            got: "other".to_owned(),
        }
    );
}

#[test]
fn rejects_a_wrong_channel() {
    let bytes = manifest(EXPIRES, "1.2.3", PRODUCT, "beta", &[]);

    let err = verify(bytes.as_bytes()).unwrap_err();

    assert_eq!(
        err,
        UpdateError::Channel {
            expected: Channel::Stable,
            got: Channel::Beta,
        }
    );
}

#[test]
fn rejects_an_expired_manifest() {
    let bytes = manifest("2020-01-01T00:00:00Z", "1.2.3", PRODUCT, "stable", &[]);

    let err = verify(bytes.as_bytes()).unwrap_err();

    assert_eq!(
        err,
        UpdateError::Expired(OffsetDateTime::parse("2020-01-01T00:00:00Z", &Rfc3339).unwrap())
    );
}

#[test]
fn rejects_an_expiry_equal_to_now() {
    let bytes = manifest("2026-01-01T00:00:00Z", "1.2.3", PRODUCT, "stable", &[]);

    let err = verify(bytes.as_bytes()).unwrap_err();

    assert!(matches!(err, UpdateError::Expired(_)));
}

#[test]
fn rejects_an_unparseable_expiry() {
    let bytes = manifest("tomorrow", "1.2.3", PRODUCT, "stable", &[]);

    let err = verify(bytes.as_bytes()).unwrap_err();

    assert!(matches!(err, UpdateError::Manifest(_)));
}

#[test]
fn rejects_a_version_equal_to_the_running_one() {
    let err = verify(good_manifest("1.2.2").as_bytes()).unwrap_err();

    assert_eq!(err, UpdateError::NotNewer(Version::parse("1.2.2").unwrap()));
}

#[test]
fn rejects_a_version_older_than_the_running_one() {
    let err = verify(good_manifest("1.2.1").as_bytes()).unwrap_err();

    assert_eq!(err, UpdateError::NotNewer(Version::parse("1.2.1").unwrap()));
}

#[test]
fn ignores_build_metadata_when_checking_that_a_version_is_newer() {
    let bytes = good_manifest("1.0.0+b");
    let running = Version::parse("1.0.0").unwrap();
    let expected = Version::parse("1.0.0+b").unwrap();

    let err = verify_manifest(
        bytes.as_bytes(),
        &signed(SEED_A, bytes.as_bytes()),
        &keys(),
        PRODUCT,
        &running,
        Channel::Stable,
        now(),
    )
    .unwrap_err();

    assert_eq!(err, UpdateError::NotNewer(expected));
}

#[test]
fn rejects_forbidden_file_names() {
    // (name as it appears in the JSON, the name after JSON unescaping)
    let cases = [
        ("sub/launcher.exe", "sub/launcher.exe"),
        ("launcher\\\\exe", "launcher\\exe"),
        ("launch..er.exe", "launch..er.exe"),
        (".launcher.exe", ".launcher.exe"),
        ("", ""),
    ];
    for (json_name, real_name) in cases {
        let bytes = manifest(
            EXPIRES,
            "1.2.3",
            PRODUCT,
            "stable",
            &[entry(json_name, DIGEST, 5)],
        );

        match verify(bytes.as_bytes()) {
            Err(UpdateError::FileName { name }) => {
                assert_eq!(name, real_name, "name {json_name:?}")
            }
            other => panic!("{json_name:?}: expected FileName, got {other:?}"),
        }
    }
}

#[test]
fn rejects_windows_reserved_and_malformed_file_names() {
    let long = format!("{}.exe", "a".repeat(61));
    assert_eq!(long.len(), 65);
    let names = [
        "C:evil.exe",
        "a.exe:stream",
        "nul.txt",
        "Com1",
        "x.",
        "a b.exe",
    ];
    for name in names {
        let bytes = manifest(
            EXPIRES,
            "1.2.3",
            PRODUCT,
            "stable",
            &[entry(name, DIGEST, 5)],
        );

        match verify(bytes.as_bytes()) {
            Err(UpdateError::FileName { name: got }) => assert_eq!(got, name),
            other => panic!("{name:?}: expected FileName, got {other:?}"),
        }
    }
    let bytes = manifest(
        EXPIRES,
        "1.2.3",
        PRODUCT,
        "stable",
        &[entry(&long, DIGEST, 5)],
    );

    match verify(bytes.as_bytes()) {
        Err(UpdateError::FileName { name }) => assert_eq!(name, long),
        other => panic!("{long:?}: expected FileName, got {other:?}"),
    }

    let name = format!("{}.exe", "a".repeat(60));
    assert_eq!(name.len(), 64);
    let bytes = manifest(
        EXPIRES,
        "1.2.3",
        PRODUCT,
        "stable",
        &[entry(&name, DIGEST, 5)],
    );
    let verified = verify(bytes.as_bytes()).unwrap();

    assert_eq!(verified.files[0].name, name);
}

#[test]
fn rejects_duplicate_file_names() {
    let files = [
        entry("launcher.exe", DIGEST, 5),
        entry("launcher.exe", DIGEST, 6),
    ];
    let bytes = manifest(EXPIRES, "1.2.3", PRODUCT, "stable", &files);

    let err = verify(bytes.as_bytes()).unwrap_err();

    assert_eq!(
        err,
        UpdateError::DuplicateFile {
            name: "launcher.exe".to_owned(),
        }
    );
}

#[test]
fn rejects_a_digest_that_is_not_64_lowercase_hex_digits() {
    let cases = [
        DIGEST.to_uppercase(),
        DIGEST[..63].to_owned(),
        format!("g{}", &DIGEST[1..]),
    ];
    for sha256 in cases {
        let bytes = manifest(
            EXPIRES,
            "1.2.3",
            PRODUCT,
            "stable",
            &[entry("launcher.exe", &sha256, 5)],
        );

        match verify(bytes.as_bytes()) {
            Err(UpdateError::Digest { name }) => {
                assert_eq!(name, "launcher.exe", "digest {sha256:?}")
            }
            other => panic!("{sha256}: expected Digest, got {other:?}"),
        }
    }
}

#[test]
fn rejects_more_than_16_files() {
    let files: Vec<String> = (0..17)
        .map(|index| entry(&format!("f{index:02}.exe"), DIGEST, 1))
        .collect();
    let bytes = manifest(EXPIRES, "1.2.3", PRODUCT, "stable", &files);

    let err = verify(bytes.as_bytes()).unwrap_err();

    assert_eq!(err, UpdateError::TooManyFiles(17));
}

#[test]
fn rejects_a_file_entry_larger_than_512_mib() {
    let size = MAX_FILE_BYTES + 1;
    let bytes = manifest(
        EXPIRES,
        "1.2.3",
        PRODUCT,
        "stable",
        &[entry("launcher.exe", DIGEST, size)],
    );

    let err = verify(bytes.as_bytes()).unwrap_err();

    assert_eq!(
        err,
        UpdateError::FileTooLarge {
            name: "launcher.exe".to_owned(),
            size,
        }
    );
}

#[test]
fn rejects_files_totaling_more_than_1_gib() {
    let total = MAX_FILE_BYTES * 2 + 1;
    let files = [
        entry("a.exe", DIGEST, MAX_FILE_BYTES),
        entry("b.exe", DIGEST, MAX_FILE_BYTES),
        entry("c.exe", DIGEST, 1),
    ];
    let bytes = manifest(EXPIRES, "1.2.3", PRODUCT, "stable", &files);

    let err = verify(bytes.as_bytes()).unwrap_err();

    assert_eq!(err, UpdateError::FilesTooLarge { total });

    let at_limit = [
        entry("a.exe", DIGEST, MAX_FILE_BYTES),
        entry("b.exe", DIGEST, MAX_FILE_BYTES),
    ];
    let bytes = manifest(EXPIRES, "1.2.3", PRODUCT, "stable", &at_limit);
    let verified = verify(bytes.as_bytes()).unwrap();
    let accepted: u64 = verified.files.iter().map(|file| file.size).sum();

    assert_eq!(accepted, MAX_TOTAL_BYTES);
}

#[test]
fn rejects_a_manifest_larger_than_64_kib() {
    let mut bytes = good_manifest("1.2.3").into_bytes();
    bytes.resize(64 * 1024 + 1, b' ');

    let err = verify_manifest(
        &bytes,
        &signed(SEED_A, &bytes),
        &keys(),
        PRODUCT,
        &current(),
        Channel::Stable,
        now(),
    )
    .unwrap_err();

    assert!(matches!(err, UpdateError::TooLarge));
}

#[test]
fn accepts_a_file_that_matches_its_entry() {
    let dir = tempdir().unwrap();
    let path = write_file(dir.path(), "launcher.exe", b"hello");
    let file = FileEntry {
        name: "launcher.exe".to_owned(),
        sha256: sha256_hex(b"hello"),
        size: 5,
    };

    verify_file(&path, &file).unwrap();
}

#[test]
fn rejects_a_file_of_the_wrong_size() {
    let dir = tempdir().unwrap();
    let path = write_file(dir.path(), "launcher.exe", b"hello");
    let file = FileEntry {
        name: "launcher.exe".to_owned(),
        sha256: sha256_hex(b"hello"),
        size: 4,
    };

    let err = verify_file(&path, &file).unwrap_err();

    assert_eq!(
        err,
        UpdateError::FileSize {
            name: "launcher.exe".to_owned(),
            expected: 4,
            got: 5,
        }
    );
}

#[test]
fn rejects_a_file_with_a_different_digest() {
    let dir = tempdir().unwrap();
    let path = write_file(dir.path(), "launcher.exe", b"hello");
    let file = FileEntry {
        name: "launcher.exe".to_owned(),
        sha256: sha256_hex(b"jello"),
        size: 5,
    };

    let err = verify_file(&path, &file).unwrap_err();

    assert_eq!(
        err,
        UpdateError::FileDigest {
            name: "launcher.exe".to_owned(),
        }
    );
}

#[test]
fn rejects_a_missing_file() {
    let dir = tempdir().unwrap();
    let file = FileEntry {
        name: "launcher.exe".to_owned(),
        sha256: sha256_hex(b"hello"),
        size: 5,
    };

    let err = verify_file(&dir.path().join("missing.exe"), &file).unwrap_err();

    assert!(matches!(err, UpdateError::Io(_)));
}
