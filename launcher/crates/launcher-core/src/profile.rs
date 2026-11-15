// SPDX-License-Identifier: MIT

//! The `server.toml` profile: types, parsing and validation.
//!
//! The shape and limits follow `launcher/schema/server.schema.json` (schema 1).

use serde::Deserialize;
use thiserror::Error;

/// A parsed launcher profile.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Profile {
    /// Profile schema version; must be 1.
    pub schema: u32,
    pub server: Server,
    pub theme: Theme,
    pub features: Features,
}

/// The game server this build opens.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Server {
    /// Stable lowercase identifier, 2–48 characters.
    pub id: String,
    /// Display name, 1–64 characters.
    pub name: String,
    pub game: Game,
    /// FiveM `host:port`, or a numeric Roblox place id.
    pub connect: String,
    /// Operator named for the Creator PLA (decision 9).
    pub operator: String,
    /// Contact address named for the Creator PLA (decision 9).
    pub contact_email: String,
    /// HTTPS feed URL; data only.
    pub feed: Option<String>,
    /// HTTPS invite link, opened in the browser.
    pub invite_url: Option<String>,
    /// `owner/name` of the GitHub repository releases come from.
    pub release_repo: Option<String>,
    /// ed25519 public keys (64 lowercase hex) that may sign this build's update manifests; empty means the build never installs updates.
    #[serde(default)]
    pub update_keys: Vec<String>,
}

impl Server {
    /// Decodes [`Self::update_keys`] into 32-byte ed25519 public keys, skipping any entry that does not decode.
    pub fn update_key_bytes(&self) -> Vec<[u8; 32]> {
        self.update_keys
            .iter()
            .filter_map(|key| decode_update_key(key))
            .collect()
    }
}

/// Supported game clients.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Game {
    FivemLegacy,
    FivemEnhanced,
    Roblox,
}

/// Which Home layout the build uses. Dusk (the default) draws the screen over a full-window scene; Classic is flat panels.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Template {
    #[default]
    Dusk,
    Classic,
}

/// Visual tokens; asset paths are relative to `assets/`.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Theme {
    /// Home layout; defaults to Dusk when omitted.
    #[serde(default)]
    pub template: Template,
    /// Name in the launcher's corner and window title; defaults to the server name. 1..=64 characters.
    pub brand: Option<String>,
    /// `#` followed by six hex digits.
    pub accent: String,
    pub wordmark: Option<String>,
    pub background: Option<String>,
}

/// Build feature flags; all default to off.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Features {
    #[serde(default)]
    pub rongroi_connect: bool,
    #[serde(default)]
    pub allow_user_servers: bool,
    #[serde(default)]
    pub allow_local_feed: bool,
    /// Also list the AETERNA studio's other games in the sidebar (sample data until the feed lists them). Off for forks.
    #[serde(default)]
    pub studio_games: bool,
}

/// Why a profile could not be parsed or validated.
#[derive(Debug, Clone, PartialEq, Error)]
pub enum ProfileError {
    #[error("could not parse profile: {0}")]
    Toml(String),

    #[error("{field}: expected schema 1, got {value}")]
    Schema { field: &'static str, value: u32 },

    #[error("{field}: {value:?} is not a valid id")]
    Id { field: &'static str, value: String },

    #[error("{field}: must be 1..=64 characters")]
    Name { field: &'static str },

    #[error("{field}: must be 1..=128 characters")]
    Operator { field: &'static str },

    #[error("{field}: {value:?} is not a valid email address")]
    ContactEmail { field: &'static str, value: String },

    #[error("{field}: {value:?} is not valid for {game:?}")]
    Connect {
        field: &'static str,
        value: String,
        game: Game,
    },

    #[error("{field}: {value:?} is not a valid https URL")]
    Feed { field: &'static str, value: String },

    #[error("{field}: {value:?} is not a valid https URL")]
    InviteUrl { field: &'static str, value: String },

    #[error("{field}: {value:?} is not an owner/name repository")]
    ReleaseRepo { field: &'static str, value: String },

    #[error("{field}: {value:?} is not a valid update key")]
    UpdateKey { field: &'static str, value: String },

    #[error("{field}: {value:?} is not # followed by six hex digits")]
    Accent { field: &'static str, value: String },

    #[error("{field}: {value:?} is not an assets/ .png or .webp path")]
    Wordmark { field: &'static str, value: String },

    #[error("{field}: {value:?} is not an assets/ .png, .webp or .jpg path")]
    Background { field: &'static str, value: String },
}

/// Parse and validate a `server.toml`.
pub fn parse(text: &str) -> Result<Profile, ProfileError> {
    let profile: Profile = toml::from_str(text).map_err(|e| ProfileError::Toml(e.to_string()))?;
    validate(&profile)?;
    Ok(profile)
}

/// Validate a parsed profile against schema 1.
pub fn validate(p: &Profile) -> Result<(), ProfileError> {
    if p.schema != 1 {
        return Err(ProfileError::Schema {
            field: "schema",
            value: p.schema,
        });
    }

    let s = &p.server;
    if !valid_id(&s.id) {
        return Err(ProfileError::Id {
            field: "server.id",
            value: s.id.clone(),
        });
    }
    if !(1..=64).contains(&s.name.chars().count()) || !plain_text(&s.name) {
        return Err(ProfileError::Name {
            field: "server.name",
        });
    }
    if !(1..=128).contains(&s.operator.chars().count()) || !plain_text(&s.operator) {
        return Err(ProfileError::Operator {
            field: "server.operator",
        });
    }
    if !valid_email(&s.contact_email) || !plain_text(&s.contact_email) {
        return Err(ProfileError::ContactEmail {
            field: "server.contact_email",
            value: s.contact_email.clone(),
        });
    }
    if !valid_connect(&s.connect, &s.game) {
        return Err(ProfileError::Connect {
            field: "server.connect",
            value: s.connect.clone(),
            game: s.game.clone(),
        });
    }
    if let Some(feed) = &s.feed {
        if !valid_feed(feed) {
            return Err(ProfileError::Feed {
                field: "server.feed",
                value: feed.clone(),
            });
        }
    }
    if let Some(url) = &s.invite_url {
        if !valid_https(url) {
            return Err(ProfileError::InviteUrl {
                field: "server.invite_url",
                value: url.clone(),
            });
        }
    }
    if let Some(repo) = &s.release_repo {
        if !valid_repo(repo) {
            return Err(ProfileError::ReleaseRepo {
                field: "server.release_repo",
                value: repo.clone(),
            });
        }
    }
    for (i, key) in s.update_keys.iter().enumerate() {
        if i >= 4 || decode_update_key(key).is_none() || s.update_keys[..i].contains(key) {
            return Err(ProfileError::UpdateKey {
                field: "server.update_keys",
                value: key.clone(),
            });
        }
    }

    if !valid_accent(&p.theme.accent) {
        return Err(ProfileError::Accent {
            field: "theme.accent",
            value: p.theme.accent.clone(),
        });
    }
    if let Some(brand) = &p.theme.brand {
        if !(1..=64).contains(&brand.chars().count()) || !plain_text(brand) {
            return Err(ProfileError::Name {
                field: "theme.brand",
            });
        }
    }
    if let Some(wordmark) = &p.theme.wordmark {
        if !valid_asset(wordmark, false) {
            return Err(ProfileError::Wordmark {
                field: "theme.wordmark",
                value: wordmark.clone(),
            });
        }
    }
    if let Some(background) = &p.theme.background {
        if !valid_asset(background, true) {
            return Err(ProfileError::Background {
                field: "theme.background",
                value: background.clone(),
            });
        }
    }
    Ok(())
}

fn valid_id(id: &str) -> bool {
    let b = id.as_bytes();
    (2..=48).contains(&b.len())
        && (b[0].is_ascii_lowercase() || b[0].is_ascii_digit())
        && b[1..]
            .iter()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == b'-')
}

fn plain_text(s: &str) -> bool {
    !s.trim().is_empty()
        && !s.chars().any(|c| {
            c.is_control()
                || matches!(
                    c,
                    '\u{061C}'
                        | '\u{200E}'
                        | '\u{200F}'
                        | '\u{202A}'..='\u{202E}'
                        | '\u{2066}'..='\u{2069}'
                )
        })
}

fn valid_email(email: &str) -> bool {
    if email.chars().count() > 254 || email.chars().any(char::is_whitespace) {
        return false;
    }
    let mut parts = email.split('@');
    matches!(
        (parts.next(), parts.next(), parts.next()),
        (Some(local), Some(domain), None) if !local.is_empty() && !domain.is_empty()
    )
}

fn valid_connect(connect: &str, game: &Game) -> bool {
    match game {
        Game::FivemLegacy | Game::FivemEnhanced => valid_host_port(connect),
        Game::Roblox => {
            (1..=20).contains(&connect.len()) && connect.bytes().all(|b| b.is_ascii_digit())
        }
    }
}

fn valid_host_port(value: &str) -> bool {
    if value.len() > 255 {
        return false;
    }
    let Some((host, port)) = value.rsplit_once(':') else {
        return false;
    };
    if host.is_empty() || port.is_empty() || port.len() > 5 {
        return false;
    }
    if !port.bytes().all(|b| b.is_ascii_digit()) {
        return false;
    }
    let Ok(port) = port.parse::<u32>() else {
        return false;
    };
    if !(1..=65535).contains(&port) {
        return false;
    }
    let host_ok = host
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-');
    host_ok && !host.starts_with('.') && !host.ends_with('.') && !host.contains("..")
}

fn valid_https(value: &str) -> bool {
    let Some(rest) = value.strip_prefix("https://") else {
        return false;
    };
    if value.chars().any(char::is_whitespace) || !plain_text(value) {
        return false;
    }
    let authority = rest.split('/').next().unwrap_or(rest);
    !authority.is_empty() && !authority.contains('@')
}

fn valid_feed(value: &str) -> bool {
    let Some(rest) = value.strip_prefix("https://") else {
        return false;
    };
    if value.chars().any(char::is_whitespace) || !plain_text(value) {
        return false;
    }
    let end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    if end == 0 || rest[..end].contains('@') {
        return false;
    }
    match rest.as_bytes().get(end) {
        None => true,
        Some(b'/') => !rest[end..].chars().any(|c| matches!(c, '?' | '#')),
        _ => false,
    }
}

fn valid_repo(value: &str) -> bool {
    let Some((owner, name)) = value.split_once('/') else {
        return false;
    };
    !owner.is_empty()
        && !name.is_empty()
        && owner
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-')
        && name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
}

fn decode_update_key(value: &str) -> Option<[u8; 32]> {
    let b = value.as_bytes();
    if b.len() != 64 || !b.iter().all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(c)) {
        return None;
    }
    let mut out = [0u8; 32];
    for (pair, slot) in b.chunks_exact(2).zip(out.iter_mut()) {
        *slot = (hex_nibble(pair[0]) << 4) | hex_nibble(pair[1]);
    }
    Some(out)
}

fn hex_nibble(b: u8) -> u8 {
    match b {
        b'0'..=b'9' => b - b'0',
        b'a'..=b'f' => b - b'a' + 10,
        _ => 0,
    }
}

fn valid_accent(value: &str) -> bool {
    let b = value.as_bytes();
    b.len() == 7 && b[0] == b'#' && b[1..].iter().all(|c| c.is_ascii_hexdigit())
}

fn valid_asset(value: &str, allow_jpg: bool) -> bool {
    let Some(rest) = value.strip_prefix("assets/") else {
        return false;
    };
    let charset = rest
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'/' | b'_' | b'-'));
    if rest.is_empty() || rest.contains("..") || !charset {
        return false;
    }
    let ext = if rest.ends_with(".png") {
        ".png"
    } else if rest.ends_with(".webp") {
        ".webp"
    } else if allow_jpg && rest.ends_with(".jpg") {
        ".jpg"
    } else {
        return false;
    };
    rest.len() > ext.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    const BASE: &str = r##"schema = 1

[server]
id = "nakara"
name = "Nakara"
game = "fivem-legacy"
connect = "play.nakara.example:30120"
operator = "Nakara Team"
contact_email = "ops@nakara.example"

[theme]
accent = "#1a2b3c"

[features]
"##;

    fn with_update_keys(keys_toml: &str) -> String {
        BASE.replacen(
            "contact_email = \"ops@nakara.example\"",
            &format!("contact_email = \"ops@nakara.example\"\nupdate_keys = {keys_toml}"),
            1,
        )
    }

    #[test]
    fn update_keys_empty_is_ok() {
        let omitted = parse(BASE).expect("omitted update_keys should parse");
        assert!(omitted.server.update_keys.is_empty());
        assert!(omitted.server.update_key_bytes().is_empty());

        let empty = parse(&with_update_keys("[]")).expect("empty update_keys should parse");
        assert!(empty.server.update_keys.is_empty());
        assert!(empty.server.update_key_bytes().is_empty());
    }

    #[test]
    fn update_keys_valid_key_is_ok_and_decodes_bytes() {
        let hex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
        let profile = parse(&with_update_keys(&format!("[\"{hex}\"]")))
            .expect("valid update key should parse");
        assert_eq!(profile.server.update_keys, vec![hex.to_string()]);
        let expected: [u8; 32] = std::array::from_fn(|i| i as u8);
        assert_eq!(profile.server.update_key_bytes(), vec![expected]);
    }

    #[test]
    fn update_keys_63_chars_is_refused() {
        let short = "a".repeat(63);
        let err = parse(&with_update_keys(&format!("[\"{short}\"]")))
            .expect_err("63-char key must be refused");
        assert_eq!(
            err,
            ProfileError::UpdateKey {
                field: "server.update_keys",
                value: short,
            }
        );
    }

    #[test]
    fn update_keys_uppercase_hex_is_refused() {
        let upper = format!("A{}", "a".repeat(63));
        let err = parse(&with_update_keys(&format!("[\"{upper}\"]")))
            .expect_err("uppercase hex key must be refused");
        assert_eq!(
            err,
            ProfileError::UpdateKey {
                field: "server.update_keys",
                value: upper,
            }
        );
    }

    #[test]
    fn update_keys_non_hex_is_refused() {
        let non_hex = format!("g{}", "a".repeat(63));
        let err = parse(&with_update_keys(&format!("[\"{non_hex}\"]")))
            .expect_err("non-hex key must be refused");
        assert_eq!(
            err,
            ProfileError::UpdateKey {
                field: "server.update_keys",
                value: non_hex,
            }
        );
    }

    #[test]
    fn update_keys_five_keys_is_refused() {
        let k1 = "1".repeat(64);
        let k2 = "2".repeat(64);
        let k3 = "3".repeat(64);
        let k4 = "4".repeat(64);
        let k5 = "5".repeat(64);
        let err = parse(&with_update_keys(&format!(
            "[\"{k1}\", \"{k2}\", \"{k3}\", \"{k4}\", \"{k5}\"]"
        )))
        .expect_err("5 update keys must be refused");
        assert_eq!(
            err,
            ProfileError::UpdateKey {
                field: "server.update_keys",
                value: k5,
            }
        );
    }

    #[test]
    fn update_keys_duplicate_is_refused() {
        let dup = "a".repeat(64);
        let err = parse(&with_update_keys(&format!("[\"{dup}\", \"{dup}\"]")))
            .expect_err("duplicate update key must be refused");
        assert_eq!(
            err,
            ProfileError::UpdateKey {
                field: "server.update_keys",
                value: dup,
            }
        );
    }
}
