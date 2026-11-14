// SPDX-License-Identifier: MIT

//! The update manifest: types and verification (ADR 0002 decision 7).
//!
//! A release carries a JSON manifest and a separate 64-byte ed25519 signature
//! over the exact manifest bytes. [`verify_manifest`] checks the signature
//! before it parses anything, then checks the schema, product, channel,
//! expiry, version and every file entry.

use std::collections::HashSet;

use ed25519_dalek::{Signature, VerifyingKey};
use serde::Deserialize;
use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;

use crate::error::UpdateError;

/// Largest manifest accepted, in bytes.
pub const MAX_MANIFEST_BYTES: usize = 64 * 1024;

/// Most files a manifest may list.
pub const MAX_FILES: usize = 16;

/// Largest single file a manifest may list, in bytes (512 MiB).
pub const MAX_FILE_BYTES: u64 = 512 * 1024 * 1024;

/// Largest total size of all files a manifest lists, in bytes (1 GiB).
pub const MAX_TOTAL_BYTES: u64 = 1024 * 1024 * 1024;

/// Update channel a manifest is for.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Channel {
    Stable,
    Beta,
}

/// One downloaded file a manifest describes.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FileEntry {
    /// Plain file name without any path part; unique within the manifest.
    pub name: String,
    /// SHA-256 of the file as 64 lowercase hex digits.
    pub sha256: String,
    /// File size in bytes.
    pub size: u64,
}

/// A manifest that passed every check.
#[derive(Debug, Clone, PartialEq)]
pub struct Verified {
    /// Manifest schema version; always 1.
    pub schema: u32,
    /// Product the manifest updates; always the build's product.
    pub product: String,
    /// Version the update installs; strictly newer than the running one.
    pub version: semver::Version,
    /// Update channel; always the build's channel.
    pub channel: Channel,
    /// When the manifest stops being valid; always after `now`.
    pub expires: OffsetDateTime,
    /// Files the update ships; at most [`MAX_FILES`].
    pub files: Vec<FileEntry>,
}

/// The manifest as it is signed, before its checks run.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawManifest {
    schema: u32,
    product: String,
    version: semver::Version,
    channel: Channel,
    expires: String,
    files: Vec<FileEntry>,
}

/// Checks a signed manifest and returns what it offers to install.
///
/// `sig` is the raw 64-byte ed25519 signature over the exact `manifest`
/// bytes, checked strictly against every public key in `keys`. The manifest
/// is refused when it is larger than [`MAX_MANIFEST_BYTES`], parses badly or
/// names unknown fields, names another schema than 1, another product or
/// channel than expected, has already expired at `now`, offers a version
/// that is not strictly newer than `current`, or lists more than
/// [`MAX_FILES`] files, file names that are not plain names, digests that
/// are not 64 lowercase hex digits, a file larger than [`MAX_FILE_BYTES`] or
/// files totaling more than [`MAX_TOTAL_BYTES`].
pub fn verify_manifest(
    manifest: &[u8],
    sig: &[u8],
    keys: &[[u8; 32]],
    expect_product: &str,
    current: &semver::Version,
    channel: Channel,
    now: OffsetDateTime,
) -> Result<Verified, UpdateError> {
    if manifest.len() > MAX_MANIFEST_BYTES {
        return Err(UpdateError::TooLarge);
    }

    let Ok(bytes) = <[u8; 64]>::try_from(sig) else {
        return Err(UpdateError::Signature);
    };
    let sig = Signature::from_bytes(&bytes);
    let verifying_keys: Vec<VerifyingKey> = keys
        .iter()
        .map(|key| VerifyingKey::from_bytes(key).map_err(|_| UpdateError::Key))
        .collect::<Result<_, _>>()?;
    if !verifying_keys
        .iter()
        .any(|key| key.verify_strict(manifest, &sig).is_ok())
    {
        return Err(UpdateError::Signature);
    }

    let raw: RawManifest =
        serde_json::from_slice(manifest).map_err(|e| UpdateError::Manifest(e.to_string()))?;
    if raw.schema != 1 {
        return Err(UpdateError::Schema(raw.schema));
    }
    if raw.product != expect_product {
        return Err(UpdateError::Product {
            expected: expect_product.to_owned(),
            got: raw.product,
        });
    }
    if raw.channel != channel {
        return Err(UpdateError::Channel {
            expected: channel,
            got: raw.channel,
        });
    }
    let expires = OffsetDateTime::parse(&raw.expires, &Rfc3339)
        .map_err(|e| UpdateError::Manifest(format!("expires is not RFC 3339: {e}")))?;
    if expires <= now {
        return Err(UpdateError::Expired(expires));
    }
    if !strictly_newer(&raw.version, current) {
        return Err(UpdateError::NotNewer(raw.version));
    }
    check_files(&raw.files)?;

    Ok(Verified {
        schema: raw.schema,
        product: raw.product,
        version: raw.version,
        channel: raw.channel,
        expires,
        files: raw.files,
    })
}

fn check_files(files: &[FileEntry]) -> Result<(), UpdateError> {
    if files.len() > MAX_FILES {
        return Err(UpdateError::TooManyFiles(files.len()));
    }
    let mut seen = HashSet::new();
    let mut total = 0u64;
    for file in files {
        if !plain_name(&file.name) {
            return Err(UpdateError::FileName {
                name: file.name.clone(),
            });
        }
        if decode_sha256(&file.sha256).is_none() {
            return Err(UpdateError::Digest {
                name: file.name.clone(),
            });
        }
        if file.size > MAX_FILE_BYTES {
            return Err(UpdateError::FileTooLarge {
                name: file.name.clone(),
                size: file.size,
            });
        }
        total += file.size;
        if !seen.insert(file.name.as_str()) {
            return Err(UpdateError::DuplicateFile {
                name: file.name.clone(),
            });
        }
    }
    if total > MAX_TOTAL_BYTES {
        return Err(UpdateError::FilesTooLarge { total });
    }
    Ok(())
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

/// Whether `candidate` is strictly newer by major, minor, patch and
/// pre-release, ignoring build metadata.
fn strictly_newer(candidate: &semver::Version, current: &semver::Version) -> bool {
    candidate
        .major
        .cmp(&current.major)
        .then_with(|| candidate.minor.cmp(&current.minor))
        .then_with(|| candidate.patch.cmp(&current.patch))
        .then_with(|| candidate.pre.cmp(&current.pre))
        .is_gt()
}

/// Decodes 64 lowercase hex digits into a SHA-256 digest.
pub(crate) fn decode_sha256(value: &str) -> Option<[u8; 32]> {
    let bytes = value.as_bytes();
    if bytes.len() != 64
        || !bytes
            .iter()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(byte))
    {
        return None;
    }
    let mut digest = [0u8; 32];
    for (pair, out) in bytes.as_chunks::<2>().0.iter().zip(digest.iter_mut()) {
        *out = (hex_value(pair[0]) << 4) | hex_value(pair[1]);
    }
    Some(digest)
}

fn hex_value(byte: u8) -> u8 {
    match byte {
        b'0'..=b'9' => byte - b'0',
        _ => byte - b'a' + 10,
    }
}
