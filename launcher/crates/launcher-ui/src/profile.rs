// SPDX-License-Identifier: MIT

//! The server profile embedded at build time by build.rs (ADR 0002 decision 3).

use std::sync::OnceLock;

const TEXT: &str = include_str!(concat!(env!("OUT_DIR"), "/server.toml"));

/// The profile this build was compiled with.
pub fn get() -> &'static launcher_core::Profile {
    static PROFILE: OnceLock<launcher_core::Profile> = OnceLock::new();
    PROFILE.get_or_init(|| launcher_core::parse(TEXT).expect("build.rs validated the profile"))
}

/// The Home layout this build uses.
pub fn template() -> launcher_core::Template {
    get().theme.template
}

/// The accent colour this build uses.
pub fn accent() -> iced::Color {
    let value = get().theme.accent.trim_start_matches('#');
    let hex = u32::from_str_radix(value, 16).unwrap_or(0x0c7a60);
    iced::Color::from_rgb8(
        ((hex >> 16) & 0xff) as u8,
        ((hex >> 8) & 0xff) as u8,
        (hex & 0xff) as u8,
    )
}

/// The display name of a game client.
pub fn game_label(game: &launcher_core::Game) -> &'static str {
    match game {
        launcher_core::Game::FivemLegacy => "FiveM",
        launcher_core::Game::FivemEnhanced => "FiveM Enhanced",
        launcher_core::Game::Roblox => "Roblox",
    }
}

/// The initials shown for a server name.
pub fn initials(name: &str) -> String {
    let words: Vec<&str> = name.split_whitespace().collect();
    let initials = if words.len() >= 2 {
        let mut initials = String::new();
        initials.extend(words[0].chars().take(1));
        initials.extend(words[1].chars().take(1));
        initials
    } else if name.is_empty() {
        return "?".to_string();
    } else {
        name.chars().take(2).collect()
    };
    initials.to_uppercase()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn embedded_profile_parses() {
        assert_eq!(get().schema, 1);
    }

    #[test]
    fn initials_use_the_first_two_words() {
        assert_eq!(initials("Nakara City"), "NC");
        assert_eq!(initials("Example RP"), "ER");
    }

    #[test]
    fn initials_use_the_first_two_letters() {
        assert_eq!(initials("Rongroi"), "RO");
    }

    #[test]
    fn initials_of_an_empty_name_are_unknown() {
        assert_eq!(initials(""), "?");
    }

    #[test]
    fn enhanced_fivem_has_a_label() {
        assert_eq!(
            game_label(&launcher_core::Game::FivemEnhanced),
            "FiveM Enhanced"
        );
    }
}
