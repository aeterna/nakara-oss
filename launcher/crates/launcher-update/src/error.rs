// SPDX-License-Identifier: MIT

//! Why an update was refused.

use std::io;
use time::OffsetDateTime;

use crate::manifest::Channel;

/// Why a manifest, a downloaded file or the exe swap was refused.
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum UpdateError {
    /// The manifest is larger than 64 KiB.
    #[error("manifest is larger than 64 KiB")]
    TooLarge,

    /// The signature is not 64 bytes, or no public key verifies it.
    #[error("signature verification failed")]
    Signature,

    /// A public key in the list is not a valid ed25519 key.
    #[error("public key is not a valid ed25519 key")]
    Key,

    /// The manifest is not JSON, has an unknown field, or `expires` is not RFC 3339.
    #[error("invalid manifest: {0}")]
    Manifest(String),

    /// The manifest schema is not 1.
    #[error("manifest schema must be 1, got {0}")]
    Schema(u32),

    /// The manifest updates another product than the build expects.
    #[error("manifest is for product {got:?}, expected {expected:?}")]
    Product { expected: String, got: String },

    /// The manifest is for another channel than the build expects.
    #[error("manifest is for channel {got:?}, expected {expected:?}")]
    Channel { expected: Channel, got: Channel },

    /// The manifest has expired.
    #[error("manifest expired at {0}")]
    Expired(OffsetDateTime),

    /// The manifest version is not strictly newer than the running one.
    #[error("manifest version {0} is not newer than the running launcher")]
    NotNewer(semver::Version),

    /// A file name is not a plain name.
    #[error("file name {name:?} is not a plain file name")]
    FileName { name: String },

    /// The same file name appears twice in the manifest.
    #[error("file name {name:?} appears twice in the manifest")]
    DuplicateFile { name: String },

    /// A digest is not 64 lowercase hex digits.
    #[error("file {name:?} digest is not 64 lowercase hex digits")]
    Digest { name: String },

    /// The manifest lists more files than the limit of 16.
    #[error("manifest lists {0} files, the limit is 16")]
    TooManyFiles(usize),

    /// A file entry is larger than 512 MiB.
    #[error("file {name:?} is {size} bytes, the limit is 512 MiB")]
    FileTooLarge { name: String, size: u64 },

    /// The manifest's files total more than 1 GiB.
    #[error("manifest files total {total} bytes, the limit is 1 GiB")]
    FilesTooLarge { total: u64 },

    /// A downloaded file has another size than the manifest says.
    #[error("file {name:?} is {got} bytes, the manifest says {expected}")]
    FileSize {
        name: String,
        expected: u64,
        got: u64,
    },

    /// A downloaded file does not match its SHA-256 digest.
    #[error("file {name:?} does not match its SHA-256 digest")]
    FileDigest { name: String },

    /// Reading a downloaded file failed.
    #[error("could not read the update file: {0}")]
    Io(String),

    /// The downloaded exe is not a file.
    #[error("the new exe {path:?} is not a file")]
    NewNotFile { path: String },

    /// The downloaded exe is not in the same directory as the current exe.
    #[error("the new exe {new:?} is not in the same directory as {current:?}")]
    DifferentParents { current: String, new: String },

    /// Moving the new exe failed and restoring the previous one also failed.
    #[error("could not move the new exe ({move_error}); restore failed ({restore_error})")]
    SwapFailed {
        move_error: String,
        restore_error: String,
    },
}

/// Turns an I/O error into [`UpdateError::Io`].
pub(crate) fn io_error(err: io::Error) -> UpdateError {
    UpdateError::Io(err.to_string())
}
