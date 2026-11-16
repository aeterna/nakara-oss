// SPDX-License-Identifier: MIT

use launcher_update::check::MAX_RELEASES_BYTES;
use launcher_update::{launcher_tags, Channel, UpdateError};
use semver::Version;

fn ver(text: &str) -> Version {
    Version::parse(text).unwrap()
}

#[test]
fn filters_sorts_and_deduplicates_mixed_release_tags_for_stable() {
    let json = br#"[
        {"id": 1, "tag_name": "nakara_rongroi-v0.1.0", "draft": false, "prerelease": false, "html_url": "https://github.com/example/repo"},
        {"id": 2, "tag_name": "launcher-v0.2.0", "draft": false, "prerelease": false, "assets": []},
        {"id": 3, "tag_name": "launcher-v0.10.0", "draft": false, "prerelease": false},
        {"id": 4, "tag_name": "launcher-v0.1.0", "draft": false, "prerelease": false},
        {"id": 5, "tag_name": "launcher-v0.2.0", "draft": false, "prerelease": false},
        {"id": 6, "tag_name": "launcher-v0.11.0", "draft": true, "prerelease": false},
        {"id": 7, "tag_name": "launcher-v0.12.0-beta.1", "draft": false, "prerelease": true},
        {"id": 8, "tag_name": "launcher-v0.13.0", "draft": false, "prerelease": true},
        {"id": 9, "tag_name": "launcher-vv0.3.0", "draft": false, "prerelease": false},
        {"id": 10, "tag_name": "launcher-v0.3", "draft": false, "prerelease": false},
        {"id": 11, "tag_name": "launcher-v01.2.3", "draft": false, "prerelease": false},
        {"id": 12, "tag_name": "launcher-0.4.0", "draft": false, "prerelease": false},
        {"id": 13, "tag_name": "v0.5.0", "draft": false, "prerelease": false},
        {"id": 14, "tag_name": "launcher-v", "draft": false, "prerelease": false},
        {"id": 15, "tag_name": "not-a-tag", "draft": false, "prerelease": false}
    ]"#;

    let tags = launcher_tags(json, Channel::Stable).unwrap();

    assert_eq!(tags, vec![ver("0.10.0"), ver("0.2.0"), ver("0.1.0")]);
}

#[test]
fn beta_channel_keeps_prereleases_and_skips_drafts() {
    let json = br#"[
        {"tag_name": "launcher-v0.2.0", "draft": false, "prerelease": false},
        {"tag_name": "launcher-v0.3.0-beta.1", "draft": false, "prerelease": true},
        {"tag_name": "launcher-v0.3.0", "draft": false, "prerelease": false},
        {"tag_name": "launcher-v0.4.0-beta.1", "draft": true, "prerelease": true},
        {"tag_name": "nakara_rongroi-v0.9.0", "draft": false, "prerelease": false}
    ]"#;

    let tags = launcher_tags(json, Channel::Beta).unwrap();

    assert_eq!(tags, vec![ver("0.3.0"), ver("0.3.0-beta.1"), ver("0.2.0")]);
}

#[test]
fn rejects_releases_json_larger_than_2_mib() {
    let mut at_limit = b"[]".to_vec();
    at_limit.resize(MAX_RELEASES_BYTES, b' ');
    assert_eq!(
        launcher_tags(&at_limit, Channel::Stable).unwrap(),
        Vec::<Version>::new()
    );

    let mut over_limit = at_limit;
    over_limit.push(b' ');
    assert_eq!(
        launcher_tags(&over_limit, Channel::Stable).unwrap_err(),
        UpdateError::TooLarge
    );
}

#[test]
fn rejects_malformed_releases_json() {
    let err = launcher_tags(b"{not a list", Channel::Stable).unwrap_err();
    assert!(matches!(err, UpdateError::Manifest(_)));
}
