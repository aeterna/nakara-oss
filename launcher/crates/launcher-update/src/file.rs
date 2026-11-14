// SPDX-License-Identifier: MIT

//! Checks one downloaded file against its manifest entry.

use std::fs::File;
use std::io::{BufReader, Read};
use std::path::Path;

use sha2::{Digest, Sha256};

use crate::error::{UpdateError, io_error};
use crate::manifest::{FileEntry, decode_sha256};

const READ_BUFFER: usize = 8192;

/// Streams the file at `path` and checks it against `entry`.
///
/// The size is checked before any hashing; the SHA-256 digest is then
/// computed while streaming, so a large file never has to be held in memory.
pub fn verify_file(path: &Path, entry: &FileEntry) -> Result<(), UpdateError> {
    let expected = decode_sha256(&entry.sha256)
        .ok_or_else(|| UpdateError::Digest {
            name: entry.name.clone(),
        })?;
    let file = File::open(path).map_err(io_error)?;
    let size = file.metadata().map_err(io_error)?.len();
    if size != entry.size {
        return Err(UpdateError::FileSize {
            name: entry.name.clone(),
            expected: entry.size,
            got: size,
        });
    }

    let mut hasher = Sha256::new();
    let mut reader = BufReader::new(file);
    let mut buffer = [0u8; READ_BUFFER];
    loop {
        let read = reader.read(&mut buffer).map_err(io_error)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    if hasher.finalize().as_slice() != expected.as_slice() {
        return Err(UpdateError::FileDigest {
            name: entry.name.clone(),
        });
    }
    Ok(())
}
