// SPDX-License-Identifier: MIT

//! Release key generation, update manifest construction and signing (ADR 0002 decision 7).
//!
//! A release carries a JSON update manifest and a separate 64-byte ed25519
//! signature over the exact manifest bytes. This crate provides the pure
//! key-handling, manifest-building and signing functions used by the
//! `launcher-sign` CLI tool. Private key bytes never appear in error values,
//! debug formatting or display strings.

#![deny(missing_docs)]

use std::collections::HashSet;
use std::fmt;
use std::fs::File;
use std::io::{BufReader, Read};
use std::path::PathBuf;

use ed25519_dalek::{Signer, SigningKey};
use serde::Serialize;
use sha2::{Digest, Sha256};
use time::format_description::well_known::Rfc3339;
use time::{OffsetDateTime, UtcOffset};

/// Largest manifest accepted by `launcher-update`, in bytes (64 KiB).
pub const MAX_MANIFEST_BYTES: usize = 64 * 1024;

/// Most files a manifest may list.
pub const MAX_FILES: usize = 16;

/// Largest single file a manifest may list, in bytes (512 MiB).
pub const MAX_FILE_BYTES: u64 = 512 * 1024 * 1024;

/// Largest total size of all files a manifest lists, in bytes (1 GiB).
pub const MAX_TOTAL_BYTES: u64 = 1024 * 1024 * 1024;

const READ_BUFFER: usize = 8192;

/// Why key generation, key parsing or manifest construction was refused.
///
/// No variant carries key bytes or raw secret input.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SignError {
    /// The signing key string is not 64 hex characters.
    KeyLength,
    /// The signing key string contains a character outside `[0-9a-fA-F]`.
    KeyHex,
    /// Generating random bytes for a new seed failed.
    Random,
    /// The product name is empty.
    EmptyProduct,
    /// The update channel is not `"stable"` or `"beta"`.
    Channel(String),
    /// Formatting the expiry timestamp as RFC 3339 failed.
    Expires(String),
    /// More than [`MAX_FILES`] files were given.
    TooManyFiles(usize),
    /// A file path has no valid plain base name.
    FileName(String),
    /// The same file base name appears more than once.
    DuplicateFile(String),
    /// A file is larger than [`MAX_FILE_BYTES`].
    FileTooLarge {
        /// Base name of the file.
        name: String,
        /// Size of the file in bytes.
        size: u64,
    },
    /// All files together are larger than [`MAX_TOTAL_BYTES`].
    FilesTooLarge {
        /// Combined size of all files in bytes.
        total: u64,
    },
    /// The serialized manifest is larger than [`MAX_MANIFEST_BYTES`].
    ManifestTooLarge(usize),
    /// Self-verification of the signature with the derived verifying key failed.
    Signature,
    /// Reading a file or serializing the manifest failed.
    Io(String),
}

impl fmt::Display for SignError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SignError::KeyLength => write!(f, "signing key must be exactly 64 hex characters"),
            SignError::KeyHex => write!(f, "signing key contains non-hex characters"),
            SignError::Random => write!(f, "failed to generate random bytes for signing seed"),
            SignError::EmptyProduct => write!(f, "product name must not be empty"),
            SignError::Channel(ch) => {
                write!(f, "channel must be \"stable\" or \"beta\", got {ch:?}")
            }
            SignError::Expires(msg) => write!(f, "invalid expires timestamp: {msg}"),
            SignError::TooManyFiles(count) => {
                write!(f, "manifest lists {count} files, the limit is {MAX_FILES}")
            }
            SignError::FileName(name) => {
                write!(f, "file name {name:?} is not a valid plain file name")
            }
            SignError::DuplicateFile(name) => {
                write!(f, "file name {name:?} appears twice in the manifest")
            }
            SignError::FileTooLarge { name, size } => {
                write!(f, "file {name:?} is {size} bytes, the limit is 512 MiB")
            }
            SignError::FilesTooLarge { total } => {
                write!(f, "manifest files total {total} bytes, the limit is 1 GiB")
            }
            SignError::ManifestTooLarge(size) => {
                write!(f, "manifest is {size} bytes, the limit is 64 KiB")
            }
            SignError::Signature => {
                write!(f, "signature failed verification with derived public key")
            }
            SignError::Io(msg) => write!(f, "{msg}"),
        }
    }
}

impl std::error::Error for SignError {}

/// Input parameters for building a signed-ready update manifest.
#[derive(Debug, Clone)]
pub struct ManifestInput {
    /// Product identifier the manifest updates.
    pub product: String,
    /// Release version being offered.
    pub version: semver::Version,
    /// Update channel (`"stable"` or `"beta"`).
    pub channel: String,
    /// When the manifest expires (formatted in UTC whole seconds).
    pub expires: OffsetDateTime,
    /// Paths to the release files to hash and include in the given order.
    pub files: Vec<PathBuf>,
}

#[derive(Serialize)]
struct WireManifest<'a> {
    schema: u32,
    product: &'a str,
    version: &'a semver::Version,
    channel: &'a str,
    expires: String,
    files: Vec<WireFile>,
}

#[derive(Serialize)]
struct WireFile {
    name: String,
    sha256: String,
    size: u64,
}

/// Parses an ed25519 32-byte seed from 64 hexadecimal characters.
///
/// At most one trailing newline (`\n` or `\r\n`) is stripped before checking.
/// Both lowercase and uppercase hex digits are accepted. On error, the returned
/// [`SignError`] never contains any part of `s`.
pub fn parse_key_hex(s: &str) -> Result<[u8; 32], SignError> {
    let trimmed = s
        .strip_suffix("\r\n")
        .or_else(|| s.strip_suffix('\n'))
        .unwrap_or(s);
    let bytes = trimmed.as_bytes();
    if bytes.len() != 64 {
        return Err(SignError::KeyLength);
    }
    let mut seed = [0u8; 32];
    for (i, out) in seed.iter_mut().enumerate() {
        let hi = hex_nibble(bytes[i * 2]).ok_or(SignError::KeyHex)?;
        let lo = hex_nibble(bytes[i * 2 + 1]).ok_or(SignError::KeyHex)?;
        *out = (hi << 4) | lo;
    }
    Ok(seed)
}

fn hex_nibble(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

/// Encodes `bytes` as lowercase hexadecimal digits.
pub fn to_hex(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        out.push(HEX[(b >> 4) as usize] as char);
        out.push(HEX[(b & 0x0f) as usize] as char);
    }
    out
}

/// Derives the ed25519 verifying (public) key from `seed` and returns it as 64
/// lowercase hexadecimal characters.
pub fn public_key_hex(seed: &[u8; 32]) -> String {
    let signing_key = SigningKey::from_bytes(seed);
    let verifying_key = signing_key.verifying_key();
    to_hex(verifying_key.as_bytes())
}

/// Generates a fresh 32-byte ed25519 seed from the OS CSPRNG.
pub fn new_seed() -> Result<[u8; 32], SignError> {
    let mut seed = [0u8; 32];
    getrandom::fill(&mut seed).map_err(|_| SignError::Random)?;
    Ok(seed)
}

/// Signs `manifest` with the ed25519 `seed` and returns the raw 64-byte signature.
pub fn sign(seed: &[u8; 32], manifest: &[u8]) -> [u8; 64] {
    let signing_key = SigningKey::from_bytes(seed);
    signing_key.sign(manifest).to_bytes()
}

/// Signs `manifest` with the ed25519 `seed`, verifies the signature strictly
/// with the matching [`ed25519_dalek::VerifyingKey`] before returning, and
/// returns the raw 64-byte signature.
pub fn sign_checked(seed: &[u8; 32], manifest: &[u8]) -> Result<[u8; 64], SignError> {
    let signing_key = SigningKey::from_bytes(seed);
    let signature = signing_key.sign(manifest);
    let verifying_key = signing_key.verifying_key();
    verifying_key
        .verify_strict(manifest, &signature)
        .map_err(|_| SignError::Signature)?;
    Ok(signature.to_bytes())
}

/// Builds a canonical update manifest JSON byte vector from `input`.
///
/// Streams each file to compute its SHA-256 without loading the whole file into
/// memory, and refuses any input that `launcher_update::verify_manifest` would
/// refuse (channel other than `"stable"` or `"beta"`, invalid base file names,
/// duplicate file names, more than [`MAX_FILES`] files, individual or total
/// file size limits, or manifest size over [`MAX_MANIFEST_BYTES`]).
pub fn build_manifest(input: &ManifestInput) -> Result<Vec<u8>, SignError> {
    if input.product.is_empty() {
        return Err(SignError::EmptyProduct);
    }
    if input.channel != "stable" && input.channel != "beta" {
        return Err(SignError::Channel(input.channel.clone()));
    }
    if input.files.len() > MAX_FILES {
        return Err(SignError::TooManyFiles(input.files.len()));
    }

    let utc_expires = input
        .expires
        .to_offset(UtcOffset::UTC)
        .replace_nanosecond(0)
        .map_err(|e| SignError::Expires(e.to_string()))?;
    let expires_str = utc_expires
        .format(&Rfc3339)
        .map_err(|e| SignError::Expires(e.to_string()))?;

    let mut seen = HashSet::with_capacity(input.files.len());
    let mut wire_files = Vec::with_capacity(input.files.len());
    let mut total_size = 0u64;

    for path in &input.files {
        let name = path
            .file_name()
            .and_then(|n| n.to_str())
            .ok_or_else(|| SignError::FileName(path.display().to_string()))?
            .to_owned();

        if !plain_name(&name) {
            return Err(SignError::FileName(name));
        }
        if !seen.insert(name.clone()) {
            return Err(SignError::DuplicateFile(name));
        }

        let (sha256, size) = hash_file(path, &name)?;
        if size > MAX_FILE_BYTES {
            return Err(SignError::FileTooLarge { name, size });
        }
        total_size = total_size
            .checked_add(size)
            .ok_or(SignError::FilesTooLarge { total: u64::MAX })?;
        if total_size > MAX_TOTAL_BYTES {
            return Err(SignError::FilesTooLarge { total: total_size });
        }

        wire_files.push(WireFile { name, sha256, size });
    }

    let wire = WireManifest {
        schema: 1,
        product: &input.product,
        version: &input.version,
        channel: &input.channel,
        expires: expires_str,
        files: wire_files,
    };

    let bytes = serde_json::to_vec(&wire).map_err(|e| SignError::Io(e.to_string()))?;
    if bytes.len() > MAX_MANIFEST_BYTES {
        return Err(SignError::ManifestTooLarge(bytes.len()));
    }
    Ok(bytes)
}

fn hash_file(path: &PathBuf, name: &str) -> Result<(String, u64), SignError> {
    let file = File::open(path).map_err(|e| SignError::Io(format!("{name}: {e}")))?;
    let metadata = file
        .metadata()
        .map_err(|e| SignError::Io(format!("{name}: {e}")))?;
    if !metadata.is_file() {
        return Err(SignError::Io(format!("{name}: not a regular file")));
    }
    let expected_len = metadata.len();

    let mut reader = BufReader::new(file);
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; READ_BUFFER];
    let mut total_read = 0u64;

    loop {
        let n = reader
            .read(&mut buffer)
            .map_err(|e| SignError::Io(format!("{name}: {e}")))?;
        if n == 0 {
            break;
        }
        hasher.update(&buffer[..n]);
        total_read += n as u64;
    }

    if total_read != expected_len {
        return Err(SignError::Io(format!(
            "{name}: size changed while reading (expected {expected_len}, read {total_read})"
        )));
    }

    let digest = hasher.finalize();
    Ok((to_hex(digest.as_slice()), total_read))
}

/// A plain file name: 1 to 64 bytes of `[A-Za-z0-9._-]`, no leading or
/// trailing dot, no `..`, and not a Windows reserved device name.
fn plain_name(name: &str) -> bool {
    if name.is_empty() || name.len() > 64 {
        return false;
    }
    if name.starts_with('.') || name.ends_with('.') || name.contains("..") {
        return false;
    }
    if !name
        .bytes()
        .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
    {
        return false;
    }
    let stem = match name.split_once('.') {
        Some((stem, _)) => stem,
        None => name,
    };
    !reserved_stem(stem)
}

/// Whether the part before the first dot is a Windows reserved device name.
fn reserved_stem(stem: &str) -> bool {
    let upper = stem.to_ascii_uppercase();
    if matches!(upper.as_str(), "CON" | "PRN" | "AUX" | "NUL") {
        return true;
    }
    let bytes = upper.as_bytes();
    bytes.len() == 4
        && (bytes.starts_with(b"COM") || bytes.starts_with(b"LPT"))
        && matches!(bytes[3], b'1'..=b'9')
}

#[cfg(test)]
mod tests {
    use super::*;
    use launcher_update::{verify_manifest, Channel};
    use semver::Version;
    use tempfile::tempdir;

    #[test]
    fn parse_key_hex_accepts_good_keys_and_rejects_bad_length_or_non_hex() {
        let lower = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
        let upper = "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF\n";
        let crlf = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\r\n";

        let parsed_lower = parse_key_hex(lower).unwrap();
        let parsed_upper = parse_key_hex(upper).unwrap();
        let parsed_crlf = parse_key_hex(crlf).unwrap();
        assert_eq!(parsed_lower, parsed_upper);
        assert_eq!(parsed_lower, parsed_crlf);
        assert_eq!(to_hex(&parsed_lower), lower);

        // Two trailing newlines must fail length check (only one trailing newline trimmed)
        let two_newlines = format!("{lower}\n\n");
        assert_eq!(parse_key_hex(&two_newlines), Err(SignError::KeyLength));

        // Bad lengths
        assert_eq!(parse_key_hex(""), Err(SignError::KeyLength));
        assert_eq!(parse_key_hex(&lower[..63]), Err(SignError::KeyLength));
        assert_eq!(
            parse_key_hex(&format!("{lower}0")),
            Err(SignError::KeyLength)
        );

        // Non-hex characters of length 64
        let non_hex = format!("g{}", &lower[1..]);
        assert_eq!(parse_key_hex(&non_hex), Err(SignError::KeyHex));
    }

    #[test]
    fn build_manifest_and_sign_verifies_with_launcher_update_and_tamper_fails() {
        let dir = tempdir().unwrap();
        let file_a = dir.path().join("launcher.exe");
        let file_b = dir.path().join("readme.txt");
        std::fs::write(&file_a, b"binary-payload").unwrap();
        std::fs::write(&file_b, b"notes").unwrap();

        let seed = [42u8; 32];
        let pub_hex = public_key_hex(&seed);
        let pub_bytes = parse_key_hex(&pub_hex).unwrap();

        let now = OffsetDateTime::parse("2026-11-15T00:00:00Z", &Rfc3339).unwrap();
        let expires = OffsetDateTime::parse("2026-12-15T12:34:56.789Z", &Rfc3339).unwrap();

        let input = ManifestInput {
            product: "aeterna".to_owned(),
            version: Version::parse("1.3.0").unwrap(),
            channel: "stable".to_owned(),
            expires,
            files: vec![file_a, file_b],
        };

        let manifest_bytes = build_manifest(&input).unwrap();
        let manifest_str = std::str::from_utf8(&manifest_bytes).unwrap();
        // Whole seconds with UTC "Z"
        assert!(
            manifest_str.contains(r#""expires":"2026-12-15T12:34:56Z""#),
            "manifest was: {manifest_str}"
        );

        let sig = sign(&seed, &manifest_bytes);

        let older = Version::parse("1.2.0").unwrap();
        let verified = verify_manifest(
            &manifest_bytes,
            &sig,
            &[pub_bytes],
            "aeterna",
            &older,
            Channel::Stable,
            now,
        )
        .unwrap();

        assert_eq!(verified.schema, 1);
        assert_eq!(verified.product, "aeterna");
        assert_eq!(verified.version, Version::parse("1.3.0").unwrap());
        assert_eq!(verified.channel, Channel::Stable);
        assert_eq!(
            verified.expires,
            OffsetDateTime::parse("2026-12-15T12:34:56Z", &Rfc3339).unwrap()
        );
        assert_eq!(verified.files.len(), 2);
        assert_eq!(verified.files[0].name, "launcher.exe");
        assert_eq!(
            verified.files[0].sha256,
            to_hex(Sha256::digest(b"binary-payload").as_slice())
        );
        assert_eq!(verified.files[0].size, 14);
        assert_eq!(verified.files[1].name, "readme.txt");
        assert_eq!(
            verified.files[1].sha256,
            to_hex(Sha256::digest(b"notes").as_slice())
        );
        assert_eq!(verified.files[1].size, 5);

        // Flipping one manifest byte makes verify_manifest fail
        let mut tampered = manifest_bytes.clone();
        tampered[0] ^= 0x01;
        let err = verify_manifest(
            &tampered,
            &sig,
            &[pub_bytes],
            "aeterna",
            &older,
            Channel::Stable,
            now,
        )
        .unwrap_err();
        assert_eq!(err, launcher_update::UpdateError::Signature);
    }

    #[test]
    fn duplicate_file_names_are_refused() {
        let dir = tempdir().unwrap();
        let sub1 = dir.path().join("one");
        let sub2 = dir.path().join("two");
        std::fs::create_dir(&sub1).unwrap();
        std::fs::create_dir(&sub2).unwrap();
        let f1 = sub1.join("launcher.exe");
        let f2 = sub2.join("launcher.exe");
        std::fs::write(&f1, b"first").unwrap();
        std::fs::write(&f2, b"second").unwrap();

        let input = ManifestInput {
            product: "aeterna".to_owned(),
            version: Version::parse("1.0.0").unwrap(),
            channel: "stable".to_owned(),
            expires: OffsetDateTime::parse("2026-12-01T00:00:00Z", &Rfc3339).unwrap(),
            files: vec![f1, f2],
        };

        let err = build_manifest(&input).unwrap_err();
        assert_eq!(err, SignError::DuplicateFile("launcher.exe".to_owned()));
    }

    #[test]
    fn invalid_file_names_are_refused() {
        let dir = tempdir().unwrap();
        let expires = OffsetDateTime::parse("2026-12-01T00:00:00Z", &Rfc3339).unwrap();
        let overlong = format!("{}.exe", "a".repeat(61));
        assert_eq!(overlong.len(), 65);

        for bad_name in ["bad name.exe", "CON.exe", overlong.as_str()] {
            let path = dir.path().join(bad_name);
            let input = ManifestInput {
                product: "aeterna".to_owned(),
                version: Version::parse("1.0.0").unwrap(),
                channel: "stable".to_owned(),
                expires,
                files: vec![path],
            };

            let err = build_manifest(&input).unwrap_err();
            assert_eq!(err, SignError::FileName(bad_name.to_owned()));
        }
    }

    #[test]
    fn sign_checked_verifies_with_launcher_update() {
        let dir = tempdir().unwrap();
        let file = dir.path().join("launcher.exe");
        std::fs::write(&file, b"payload").unwrap();

        let seed = [7u8; 32];
        let pub_hex = public_key_hex(&seed);
        let pub_bytes = parse_key_hex(&pub_hex).unwrap();

        let now = OffsetDateTime::parse("2026-11-15T00:00:00Z", &Rfc3339).unwrap();
        let expires = OffsetDateTime::parse("2026-12-15T00:00:00Z", &Rfc3339).unwrap();

        let input = ManifestInput {
            product: "aeterna".to_owned(),
            version: Version::parse("2.0.0").unwrap(),
            channel: "stable".to_owned(),
            expires,
            files: vec![file],
        };

        let manifest_bytes = build_manifest(&input).unwrap();
        let sig = sign_checked(&seed, &manifest_bytes).unwrap();

        let older = Version::parse("1.9.0").unwrap();
        let verified = verify_manifest(
            &manifest_bytes,
            &sig,
            &[pub_bytes],
            "aeterna",
            &older,
            Channel::Stable,
            now,
        )
        .unwrap();

        assert_eq!(verified.version, Version::parse("2.0.0").unwrap());
        assert_eq!(verified.files.len(), 1);
        assert_eq!(verified.files[0].name, "launcher.exe");
    }

    #[test]
    fn channel_nightly_is_refused() {
        let input = ManifestInput {
            product: "aeterna".to_owned(),
            version: Version::parse("1.0.0").unwrap(),
            channel: "nightly".to_owned(),
            expires: OffsetDateTime::parse("2026-12-01T00:00:00Z", &Rfc3339).unwrap(),
            files: vec![],
        };

        let err = build_manifest(&input).unwrap_err();
        assert_eq!(err, SignError::Channel("nightly".to_owned()));
    }

    #[test]
    fn sign_error_debug_and_display_never_contain_bad_key_input() {
        let secret_short = "super_secret_key_material_do_not_leak";
        let err_len = parse_key_hex(secret_short).unwrap_err();
        let debug_len = format!("{err_len:?}");
        let display_len = format!("{err_len}");
        assert!(!debug_len.contains(secret_short));
        assert!(!display_len.contains(secret_short));

        // 64 chars with non-hex secret marker
        let secret_non_hex = "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz";
        assert_eq!(secret_non_hex.len(), 64);
        let err_hex = parse_key_hex(secret_non_hex).unwrap_err();
        let debug_hex = format!("{err_hex:?}");
        let display_hex = format!("{err_hex}");
        assert!(!debug_hex.contains("zzzz"));
        assert!(!display_hex.contains("zzzz"));
    }
}
