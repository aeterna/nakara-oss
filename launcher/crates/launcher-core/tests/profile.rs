// SPDX-License-Identifier: MIT

use launcher_core::{parse, Game, ProfileError, Template};

const VALID: &str = r##"schema = 1

[server]
id = "nakara"
name = "Nakara"
game = "fivem-legacy"
connect = "play.nakara.example:30120"
operator = "Nakara Team"
contact_email = "ops@nakara.example"
feed = "https://feed.nakara.example/profile.json"
invite_url = "https://discord.gg/nakara"
release_repo = "nakara-oss/launcher"

[theme]
accent = "#1a2b3c"
wordmark = "assets/wordmark.png"
background = "assets/background.jpg"

[features]
"##;

fn replace_line(text: &str, from: &str, to: &str) -> String {
    assert!(
        text.lines().any(|line| line == from),
        "fixture has no line {from:?}"
    );
    text.replacen(from, to, 1)
}

fn variant(from: &str, to: &str) -> String {
    replace_line(VALID, from, to)
}

fn rejected(text: &str) -> ProfileError {
    parse(text).expect_err("profile should be rejected")
}

#[test]
fn valid_profile_parses() {
    let profile = parse(VALID).expect("valid profile should parse");
    assert_eq!(profile.schema, 1);
    assert_eq!(profile.server.id, "nakara");
    assert_eq!(profile.server.name, "Nakara");
    assert_eq!(profile.server.game, Game::FivemLegacy);
    assert_eq!(profile.server.connect, "play.nakara.example:30120");
    assert_eq!(profile.server.contact_email, "ops@nakara.example");
    assert_eq!(profile.theme.accent, "#1a2b3c");
}

#[test]
fn empty_features_table_defaults_to_false() {
    let profile = parse(VALID).expect("empty [features] table should parse");
    assert!(!profile.features.rongroi_connect);
    assert!(!profile.features.allow_user_servers);
    assert!(!profile.features.allow_local_feed);
}

#[test]
fn missing_operator_is_rejected() {
    let text = variant("operator = \"Nakara Team\"", "# operator removed");
    assert!(matches!(rejected(&text), ProfileError::Toml(_)));
}

#[test]
fn invalid_email_is_rejected() {
    let text = variant(
        "contact_email = \"ops@nakara.example\"",
        "contact_email = \"not-an-email\"",
    );
    assert!(matches!(
        rejected(&text),
        ProfileError::ContactEmail {
            field: "server.contact_email",
            ..
        }
    ));
}

#[test]
fn unknown_field_is_rejected() {
    let text = variant("id = \"nakara\"", "id = \"nakara\"\nunknown_field = \"x\"");
    assert!(matches!(rejected(&text), ProfileError::Toml(_)));
}

#[test]
fn port_zero_is_rejected() {
    let text = variant(
        "connect = \"play.nakara.example:30120\"",
        "connect = \"play.nakara.example:0\"",
    );
    assert!(matches!(
        rejected(&text),
        ProfileError::Connect {
            field: "server.connect",
            ..
        }
    ));
}

#[test]
fn port_65536_is_rejected() {
    let text = variant(
        "connect = \"play.nakara.example:30120\"",
        "connect = \"play.nakara.example:65536\"",
    );
    assert!(matches!(
        rejected(&text),
        ProfileError::Connect {
            field: "server.connect",
            ..
        }
    ));
}

#[test]
fn host_with_double_dot_is_rejected() {
    let text = variant(
        "connect = \"play.nakara.example:30120\"",
        "connect = \"host..x:1\"",
    );
    assert!(matches!(
        rejected(&text),
        ProfileError::Connect {
            field: "server.connect",
            ..
        }
    ));
}

#[test]
fn roblox_non_numeric_connect_is_rejected() {
    let text = replace_line(
        &variant("game = \"fivem-legacy\"", "game = \"roblox\""),
        "connect = \"play.nakara.example:30120\"",
        "connect = \"12a\"",
    );
    assert!(matches!(
        rejected(&text),
        ProfileError::Connect {
            field: "server.connect",
            game: Game::Roblox,
            ..
        }
    ));
}

#[test]
fn insecure_feed_is_rejected() {
    let text = variant(
        "feed = \"https://feed.nakara.example/profile.json\"",
        "feed = \"http://feed.nakara.example/profile.json\"",
    );
    assert!(matches!(
        rejected(&text),
        ProfileError::Feed {
            field: "server.feed",
            ..
        }
    ));
}

#[test]
fn feed_with_userinfo_is_rejected() {
    let text = variant(
        "feed = \"https://feed.nakara.example/profile.json\"",
        "feed = \"https://user@host/x\"",
    );
    assert!(matches!(
        rejected(&text),
        ProfileError::Feed {
            field: "server.feed",
            ..
        }
    ));
}

#[test]
fn short_accent_is_rejected() {
    let text = variant("accent = \"#1a2b3c\"", "accent = \"#12345\"");
    assert!(matches!(
        rejected(&text),
        ProfileError::Accent {
            field: "theme.accent",
            ..
        }
    ));
}

#[test]
fn wordmark_outside_assets_is_rejected() {
    let text = variant(
        "wordmark = \"assets/wordmark.png\"",
        "wordmark = \"../x.png\"",
    );
    assert!(matches!(
        rejected(&text),
        ProfileError::Wordmark {
            field: "theme.wordmark",
            ..
        }
    ));
}

#[test]
fn schema_two_is_rejected() {
    let text = variant("schema = 1", "schema = 2");
    assert!(matches!(
        rejected(&text),
        ProfileError::Schema {
            field: "schema",
            value: 2
        }
    ));
}

#[test]
fn roblox_numeric_connect_parses() {
    let text = replace_line(
        &variant("game = \"fivem-legacy\"", "game = \"roblox\""),
        "connect = \"play.nakara.example:30120\"",
        "connect = \"1234567890\"",
    );
    let profile = parse(&text).expect("numeric Roblox place id should parse");
    assert_eq!(profile.server.game, Game::Roblox);
    assert_eq!(profile.server.connect, "1234567890");
}

#[test]
fn template_defaults_to_dusk() {
    let profile = parse(VALID).expect("profile without a template should parse");
    assert_eq!(profile.theme.template, Template::Dusk);
}

#[test]
fn classic_template_parses() {
    let text = replace_line(VALID, "[theme]", "[theme]\ntemplate = \"classic\"");
    let profile = parse(&text).expect("classic template should parse");
    assert_eq!(profile.theme.template, Template::Classic);
}

#[test]
fn unknown_template_is_rejected() {
    let text = replace_line(VALID, "[theme]", "[theme]\ntemplate = \"neon\"");
    assert!(parse(&text).is_err());
}

#[test]
fn valid_profile_has_no_brand() {
    let profile = parse(VALID).expect("valid profile should parse");
    assert_eq!(profile.theme.brand, None);
}

#[test]
fn brand_parses() {
    let text = replace_line(VALID, "[theme]", "[theme]\nbrand = \"AETERNA Game\"");
    let profile = parse(&text).expect("brand should parse");
    assert_eq!(profile.theme.brand.as_deref(), Some("AETERNA Game"));
}

#[test]
fn empty_brand_is_rejected() {
    let text = replace_line(VALID, "[theme]", "[theme]\nbrand = \"\"");
    assert!(matches!(
        rejected(&text),
        ProfileError::Name {
            field: "theme.brand"
        }
    ));
}

#[test]
fn sixty_five_character_brand_is_rejected() {
    let line = format!("brand = \"{}\"", "x".repeat(65));
    let text = replace_line(VALID, "[theme]", &format!("[theme]\n{line}"));
    assert!(matches!(
        rejected(&text),
        ProfileError::Name {
            field: "theme.brand"
        }
    ));
}

#[test]
fn studio_games_defaults_to_false() {
    let profile = parse(VALID).expect("empty [features] table should parse");
    assert!(!profile.features.studio_games);
}

#[test]
fn studio_games_true_parses() {
    let text = replace_line(VALID, "[features]", "[features]\nstudio_games = true");
    let profile = parse(&text).expect("studio_games should parse");
    assert!(profile.features.studio_games);
}
