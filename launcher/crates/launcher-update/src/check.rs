// SPDX-License-Identifier: MIT

//! Parsing GitHub release lists into candidate launcher versions.

use serde::Deserialize;

use crate::error::UpdateError;
use crate::manifest::Channel;

/// Largest GitHub releases JSON response accepted, in bytes (2 MiB).
pub const MAX_RELEASES_BYTES: usize = 2 * 1024 * 1024;

#[derive(Debug, Deserialize)]
struct RawRelease {
    tag_name: String,
    draft: bool,
    prerelease: bool,
}

/// Parses a GitHub releases JSON list and returns candidate launcher versions,
/// sorted newest first and deduplicated.
///
/// Unknown fields on release objects are ignored. Only non-draft releases
/// whose `tag_name` is `launcher-v<semver>` are kept; [`Channel::Stable`]
/// also skips releases marked `prerelease` or carrying a SemVer pre-release
/// suffix, while [`Channel::Beta`] keeps them. Input larger than
/// [`MAX_RELEASES_BYTES`] is refused with [`UpdateError::TooLarge`].
pub fn launcher_tags(
    releases_json: &[u8],
    channel: Channel,
) -> Result<Vec<semver::Version>, UpdateError> {
    if releases_json.len() > MAX_RELEASES_BYTES {
        return Err(UpdateError::TooLarge);
    }

    let releases: Vec<RawRelease> =
        serde_json::from_slice(releases_json).map_err(|e| UpdateError::Manifest(e.to_string()))?;

    let mut versions = Vec::new();
    for release in releases {
        if release.draft {
            continue;
        }
        if channel == Channel::Stable && release.prerelease {
            continue;
        }
        let Some(raw_version) = release.tag_name.strip_prefix("launcher-v") else {
            continue;
        };
        let Ok(version) = semver::Version::parse(raw_version) else {
            continue;
        };
        if channel == Channel::Stable && !version.pre.is_empty() {
            continue;
        }
        versions.push(version);
    }

    versions.sort_by(|a, b| b.cmp(a));
    versions.dedup();
    Ok(versions)
}
