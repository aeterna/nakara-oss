// SPDX-License-Identifier: MIT

use launcher_core::Profile;
use launcher_net::NetPolicy;
use launcher_update::check::MAX_RELEASES_BYTES;
use launcher_update::manifest::MAX_MANIFEST_BYTES;
use launcher_update::{is_newer, launcher_tags, verify_manifest, Channel};
use semver::Version;
use time::OffsetDateTime;

const PRODUCT: &str = "aeterna-launcher";
const MAX_SIG_BYTES: u64 = 64;
const MAX_TRIED_TAGS: usize = 5;

type Fetch<'a> = dyn Fn(&str, u64, Option<&str>) -> Result<Vec<u8>, String> + 'a;

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub enum UpdateState {
    #[default]
    Off,
    UpToDate,
    Available {
        version: Version,
        page: String,
    },
    Failed,
}

pub fn check_with(
    fetch: &Fetch<'_>,
    repo: &str,
    keys: &[[u8; 32]],
    current: &Version,
    now: OffsetDateTime,
) -> Result<UpdateState, String> {
    let list_url = format!("https://api.github.com/repos/{repo}/releases?per_page=100");
    let list_bytes = fetch(
        &list_url,
        MAX_RELEASES_BYTES as u64,
        Some("application/vnd.github+json"),
    )?;
    let tags = launcher_tags(&list_bytes, Channel::Stable).map_err(|err| err.to_string())?;

    let mut saw_newer = false;
    for tag in tags
        .into_iter()
        .filter(|tag| is_newer(tag, current))
        .take(MAX_TRIED_TAGS)
    {
        saw_newer = true;

        let base = format!("https://github.com/{repo}/releases/download/launcher-v{tag}");
        let manifest_bytes = match fetch(
            &format!("{base}/manifest.json"),
            MAX_MANIFEST_BYTES as u64,
            None,
        ) {
            Ok(bytes) => bytes,
            Err(err) => {
                eprintln!("launcher-v{tag}: {err}");
                continue;
            }
        };
        let sig_bytes = match fetch(&format!("{base}/manifest.json.sig"), MAX_SIG_BYTES, None) {
            Ok(bytes) => bytes,
            Err(err) => {
                eprintln!("launcher-v{tag}: {err}");
                continue;
            }
        };
        let verified = match verify_manifest(
            &manifest_bytes,
            &sig_bytes,
            keys,
            PRODUCT,
            current,
            Channel::Stable,
            now,
        ) {
            Ok(verified) => verified,
            Err(err) => {
                eprintln!("launcher-v{tag}: {err}");
                continue;
            }
        };
        if verified.version != tag {
            eprintln!(
                "launcher-v{tag}: manifest version {} != tag {tag}",
                verified.version
            );
            continue;
        }

        let page = format!(
            "https://github.com/{repo}/releases/tag/launcher-v{}",
            verified.version
        );
        return Ok(UpdateState::Available {
            version: verified.version,
            page,
        });
    }

    if saw_newer {
        Ok(UpdateState::Failed)
    } else {
        Ok(UpdateState::UpToDate)
    }
}

pub fn check(profile: &Profile) -> UpdateState {
    let Some(repo) = profile.server.release_repo.as_deref() else {
        return UpdateState::Off;
    };
    let keys = profile.server.update_key_bytes();
    if keys.is_empty() {
        return UpdateState::Off;
    }
    let current = match Version::parse(env!("CARGO_PKG_VERSION")) {
        Ok(version) => version,
        Err(err) => {
            eprintln!("{err}");
            return UpdateState::Failed;
        }
    };
    let client = launcher_http::Client::new(
        NetPolicy::from_profile(profile),
        &format!(
            "{}-launcher/{}",
            profile.server.id,
            env!("CARGO_PKG_VERSION")
        ),
    );
    let fetch = |url: &str, cap: u64, accept: Option<&str>| {
        client
            .get_release(url, cap, accept)
            .map_err(|err| err.to_string())
    };
    match check_with(&fetch, repo, &keys, &current, OffsetDateTime::now_utc()) {
        Ok(state) => state,
        Err(err) => {
            eprintln!("{err}");
            UpdateState::Failed
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};
    use time::format_description::well_known::Rfc3339;

    const REPO: &str = "aeterna/nakara-oss";
    const SEED: [u8; 32] = [19; 32];
    const DIGEST: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const LIST_URL: &str = "https://api.github.com/repos/aeterna/nakara-oss/releases?per_page=100";
    const MANIFEST_020: &str =
        "https://github.com/aeterna/nakara-oss/releases/download/launcher-v0.2.0/manifest.json";
    const SIG_020: &str =
        "https://github.com/aeterna/nakara-oss/releases/download/launcher-v0.2.0/manifest.json.sig";
    const MANIFEST_030: &str =
        "https://github.com/aeterna/nakara-oss/releases/download/launcher-v0.3.0/manifest.json";
    const SIG_030: &str =
        "https://github.com/aeterna/nakara-oss/releases/download/launcher-v0.3.0/manifest.json.sig";
    const PAGE_020: &str = "https://github.com/aeterna/nakara-oss/releases/tag/launcher-v0.2.0";

    fn pubkey() -> [u8; 32] {
        SigningKey::from_bytes(&SEED).verifying_key().to_bytes()
    }

    fn sign(bytes: &[u8]) -> Vec<u8> {
        SigningKey::from_bytes(&SEED)
            .sign(bytes)
            .to_bytes()
            .to_vec()
    }

    fn manifest_json(version: &str, expires: &str) -> Vec<u8> {
        format!(
            r#"{{"schema":1,"product":"aeterna-launcher","version":"{version}","channel":"stable","expires":"{expires}","files":[{{"name":"aeterna-launcher.exe","sha256":"{DIGEST}","size":1024}}]}}"#
        )
        .into_bytes()
    }

    fn now() -> OffsetDateTime {
        OffsetDateTime::parse("2026-11-16T00:00:00Z", &Rfc3339).unwrap()
    }

    fn current() -> Version {
        Version::parse("0.1.0").unwrap()
    }

    #[test]
    fn newer_verified_returns_available_with_built_page_url() {
        let m020 = manifest_json("0.2.0", "2027-02-01T00:00:00Z");
        let s020 = sign(&m020);

        let fetch = |url: &str, cap: u64, accept: Option<&str>| match url {
            LIST_URL => {
                assert_eq!(cap, MAX_RELEASES_BYTES as u64);
                assert_eq!(accept, Some("application/vnd.github+json"));
                Ok(br#"[{"tag_name":"launcher-v0.2.0","draft":false,"prerelease":false,"html_url":"https://evil.example/phish"}]"#.to_vec())
            }
            MANIFEST_020 => {
                assert_eq!(cap, MAX_MANIFEST_BYTES as u64);
                assert_eq!(accept, None);
                Ok(m020.clone())
            }
            SIG_020 => {
                assert_eq!(cap, 64);
                assert_eq!(accept, None);
                Ok(s020.clone())
            }
            other => Err(format!("unexpected URL: {other}")),
        };

        let state = check_with(&fetch, REPO, &[pubkey()], &current(), now()).unwrap();
        assert_eq!(
            state,
            UpdateState::Available {
                version: Version::parse("0.2.0").unwrap(),
                page: PAGE_020.to_string(),
            }
        );
    }

    #[test]
    fn bad_signature_is_skipped_and_returns_failed_when_none_verifies() {
        let m020 = manifest_json("0.2.0", "2027-02-01T00:00:00Z");
        let mut bad_sig = sign(&m020);
        bad_sig[0] ^= 0xff;

        let fetch = |url: &str, _cap: u64, _accept: Option<&str>| match url {
            LIST_URL => Ok(
                br#"[{"tag_name":"launcher-v0.2.0","draft":false,"prerelease":false}]"#.to_vec(),
            ),
            MANIFEST_020 => Ok(m020.clone()),
            SIG_020 => Ok(bad_sig.clone()),
            other => Err(format!("unexpected URL: {other}")),
        };

        let state = check_with(&fetch, REPO, &[pubkey()], &current(), now()).unwrap();
        assert_eq!(state, UpdateState::Failed);
    }

    #[test]
    fn manifest_version_mismatch_is_skipped() {
        let m030_wrong = manifest_json("0.2.0", "2027-02-01T00:00:00Z");
        let s030_wrong = sign(&m030_wrong);
        let m020 = manifest_json("0.2.0", "2027-02-01T00:00:00Z");
        let s020 = sign(&m020);

        let fetch_only_mismatch = |url: &str, _cap: u64, _accept: Option<&str>| match url {
            LIST_URL => Ok(
                br#"[{"tag_name":"launcher-v0.3.0","draft":false,"prerelease":false}]"#.to_vec(),
            ),
            MANIFEST_030 => Ok(m030_wrong.clone()),
            SIG_030 => Ok(s030_wrong.clone()),
            other => Err(format!("unexpected URL: {other}")),
        };

        assert_eq!(
            check_with(&fetch_only_mismatch, REPO, &[pubkey()], &current(), now()).unwrap(),
            UpdateState::Failed
        );

        let fetch_with_fallback = |url: &str, _cap: u64, _accept: Option<&str>| match url {
            LIST_URL => Ok(br#"[
                {"tag_name":"launcher-v0.3.0","draft":false,"prerelease":false},
                {"tag_name":"launcher-v0.2.0","draft":false,"prerelease":false}
            ]"#
            .to_vec()),
            MANIFEST_030 => Ok(m030_wrong.clone()),
            SIG_030 => Ok(s030_wrong.clone()),
            MANIFEST_020 => Ok(m020.clone()),
            SIG_020 => Ok(s020.clone()),
            other => Err(format!("unexpected URL: {other}")),
        };

        assert_eq!(
            check_with(&fetch_with_fallback, REPO, &[pubkey()], &current(), now()).unwrap(),
            UpdateState::Available {
                version: Version::parse("0.2.0").unwrap(),
                page: PAGE_020.to_string(),
            }
        );
    }

    #[test]
    fn expired_manifest_is_skipped() {
        let m030_expired = manifest_json("0.3.0", "2025-01-01T00:00:00Z");
        let s030_expired = sign(&m030_expired);
        let m020 = manifest_json("0.2.0", "2027-02-01T00:00:00Z");
        let s020 = sign(&m020);

        let fetch_only_expired = |url: &str, _cap: u64, _accept: Option<&str>| match url {
            LIST_URL => Ok(
                br#"[{"tag_name":"launcher-v0.3.0","draft":false,"prerelease":false}]"#.to_vec(),
            ),
            MANIFEST_030 => Ok(m030_expired.clone()),
            SIG_030 => Ok(s030_expired.clone()),
            other => Err(format!("unexpected URL: {other}")),
        };

        assert_eq!(
            check_with(&fetch_only_expired, REPO, &[pubkey()], &current(), now()).unwrap(),
            UpdateState::Failed
        );

        let fetch_with_fallback = |url: &str, _cap: u64, _accept: Option<&str>| match url {
            LIST_URL => Ok(br#"[
                {"tag_name":"launcher-v0.3.0","draft":false,"prerelease":false},
                {"tag_name":"launcher-v0.2.0","draft":false,"prerelease":false}
            ]"#
            .to_vec()),
            MANIFEST_030 => Ok(m030_expired.clone()),
            SIG_030 => Ok(s030_expired.clone()),
            MANIFEST_020 => Ok(m020.clone()),
            SIG_020 => Ok(s020.clone()),
            other => Err(format!("unexpected URL: {other}")),
        };

        assert_eq!(
            check_with(&fetch_with_fallback, REPO, &[pubkey()], &current(), now()).unwrap(),
            UpdateState::Available {
                version: Version::parse("0.2.0").unwrap(),
                page: PAGE_020.to_string(),
            }
        );
    }

    #[test]
    fn older_or_equal_tags_only_returns_up_to_date() {
        let fetch = |url: &str, _cap: u64, _accept: Option<&str>| match url {
            LIST_URL => Ok(br#"[
                {"tag_name":"launcher-v0.2.0","draft":false,"prerelease":false},
                {"tag_name":"launcher-v0.1.0","draft":false,"prerelease":false}
            ]"#
            .to_vec()),
            other => Err(format!(
                "should not fetch manifest for non-newer tag: {other}"
            )),
        };

        let running = Version::parse("0.2.0").unwrap();
        let state = check_with(&fetch, REPO, &[pubkey()], &running, now()).unwrap();
        assert_eq!(state, UpdateState::UpToDate);
    }

    #[test]
    fn kit_tags_are_ignored() {
        let fetch = |url: &str, _cap: u64, _accept: Option<&str>| match url {
            LIST_URL => Ok(br#"[
                {"tag_name":"nakara_rongroi-v0.9.0","draft":false,"prerelease":false},
                {"tag_name":"nakara_tickets-v1.0.0","draft":false,"prerelease":false}
            ]"#
            .to_vec()),
            other => Err(format!("should not fetch manifest for kit tag: {other}")),
        };

        let state = check_with(&fetch, REPO, &[pubkey()], &current(), now()).unwrap();
        assert_eq!(state, UpdateState::UpToDate);
    }

    #[test]
    fn fetch_error_on_list_returns_err() {
        let fetch = |_url: &str, _cap: u64, _accept: Option<&str>| Err("failed".to_string());

        let err = check_with(&fetch, REPO, &[pubkey()], &current(), now()).unwrap_err();
        assert_eq!(err, "failed");
    }

    #[test]
    fn tries_at_most_five_newer_tags_and_never_fetches_sixth_or_seventh() {
        let m020 = manifest_json("0.2.0", "2027-02-01T00:00:00Z");
        let s020 = sign(&m020);
        let asked = std::cell::RefCell::new(Vec::new());

        let fetch = |url: &str, _cap: u64, _accept: Option<&str>| {
            asked.borrow_mut().push(url.to_string());
            match url {
                LIST_URL => Ok(br#"[
                    {"tag_name":"launcher-v0.8.0","draft":false,"prerelease":false},
                    {"tag_name":"launcher-v0.7.0","draft":false,"prerelease":false},
                    {"tag_name":"launcher-v0.6.0","draft":false,"prerelease":false},
                    {"tag_name":"launcher-v0.5.0","draft":false,"prerelease":false},
                    {"tag_name":"launcher-v0.4.0","draft":false,"prerelease":false},
                    {"tag_name":"launcher-v0.3.0","draft":false,"prerelease":false},
                    {"tag_name":"launcher-v0.2.0","draft":false,"prerelease":false}
                ]"#
                .to_vec()),
                MANIFEST_020 => Ok(m020.clone()),
                SIG_020 => Ok(s020.clone()),
                _ => Err("missing manifest".to_string()),
            }
        };

        let state = check_with(&fetch, REPO, &[pubkey()], &current(), now()).unwrap();
        assert_eq!(state, UpdateState::Failed);
        let urls = asked.borrow();
        assert_eq!(urls.len(), 1 + MAX_TRIED_TAGS);
        assert!(!urls.iter().any(|u| u.contains("launcher-v0.3.0")));
        assert!(!urls.iter().any(|u| u.contains("launcher-v0.2.0")));
    }

    #[test]
    fn check_returns_off_without_repo_or_keys() {
        let mut profile = crate::profile::get().clone();
        profile.server.release_repo = None;
        assert_eq!(check(&profile), UpdateState::Off);

        let mut no_keys = crate::profile::get().clone();
        no_keys.server.release_repo = Some(REPO.to_string());
        no_keys.server.update_keys.clear();
        assert_eq!(check(&no_keys), UpdateState::Off);
    }
}
