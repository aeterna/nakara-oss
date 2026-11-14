// SPDX-License-Identifier: MIT

//! Signed update manifests and the exe swap (ADR 0002 decision 7).
//!
//! A release carries a JSON manifest and a separate 64-byte ed25519 signature
//! over the exact manifest bytes. [`verify_manifest`] checks the signature
//! against the build's public keys before parsing anything, then checks the
//! product, channel, expiry, version and every file entry. After the files
//! are downloaded, [`verify_file`] streams each one against its entry, and
//! [`swap_exe`] replaces the running exe by rename while keeping the previous
//! one for [`rollback`].

pub mod error;
pub mod file;
pub mod manifest;
pub mod swap;

pub use error::UpdateError;
pub use file::verify_file;
pub use manifest::{Channel, FileEntry, Verified, verify_manifest};
pub use swap::{old_path, rollback, swap_exe};
