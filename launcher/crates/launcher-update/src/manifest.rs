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
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;

use crate::error::UpdateError;

/// Largest manifest accepted, in bytes.
pub const MAX_MANIFEST_BYTES: usize = 64 * 1024;

/// Most files a manifest may list.
pub const MAX_FILES: usize = 16;

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
/// [`MAX_FILES`] files, file names that are not plain names, or digests that
/// are not 64 lowercase hex digits.
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
    if raw.version <= *current {
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
        if !seen.insert(file.name.as_str()) {
            return Err(UpdateError::DuplicateFile {
                name: file.name.clone(),
            });
        }
    }
    Ok(())
}

/// A plain file name: not empty, no path parts, no leading dot.
fn plain_name(name: &str) -> bool {
    !name.is_empty()
        && !name.starts_with('.')
        && !name.contains('/')
        && !name.contains('\\')
        && !name.contains("..")
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
    for (pair, out) in bytes.chunks_exact(2).zip(digest.iter_mut()) {
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
