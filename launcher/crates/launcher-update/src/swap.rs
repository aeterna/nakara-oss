// SPDX-License-Identifier: MIT

//! Replaces the running launcher exe by rename, keeping the previous one to
//! roll back.

use std::path::{Path, PathBuf};

use crate::error::{UpdateError, io_error};

/// Path of the previous exe kept for rollback: the file name of `current`
/// with `.old` appended, in the same directory.
pub fn old_path(current: &Path) -> PathBuf {
    match current.file_name() {
        Some(name) => {
            let mut old = name.to_os_string();
            old.push(".old");
            current.with_file_name(old)
        }
        None => {
            let mut old = current.as_os_str().to_os_string();
            old.push(".old");
            PathBuf::from(old)
        }
    }
}

/// Replaces the launcher exe with a downloaded update.
///
/// `current` is renamed to [`old_path`] (replacing an older `.old` file),
/// then `new` is renamed to `current`. If the second rename fails, the
/// `.old` file is renamed back so `current` is left as it was. Both paths
/// must live in the same directory; only renames inside it are used and
/// nothing is deleted.
pub fn swap_exe(current: &Path, new: &Path) -> Result<(), UpdateError> {
    let old = old_path(current);
    std::fs::rename(current, &old).map_err(io_error)?;
    if let Err(err) = std::fs::rename(new, current) {
        std::fs::rename(&old, current).map_err(io_error)?;
        return Err(io_error(err));
    }
    Ok(())
}

/// Puts the kept `.old` exe back in place of the current one.
///
/// Renames [`old_path`] over `current`, replacing whatever sits there, so a
/// broken update can be undone. Fails when there is no `.old` file.
pub fn rollback(current: &Path) -> Result<(), UpdateError> {
    std::fs::rename(old_path(current), current).map_err(io_error)
}
