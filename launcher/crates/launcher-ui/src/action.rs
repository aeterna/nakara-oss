// SPDX-License-Identifier: MIT

use crate::model::{Instance, Kind};

const MAX_LINK_LEN: usize = 2048;

pub fn safe_link(url: &str) -> bool {
    url.starts_with("https://")
        && url.len() <= MAX_LINK_LEN
        && !url.chars().any(|c| c.is_whitespace() || c.is_control())
}

pub fn can_play(inst: &Instance) -> bool {
    inst.kind == Kind::Server && inst.play_enabled
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dummy_instance(kind: Kind, play_enabled: bool) -> Instance {
        Instance {
            initials: "EX".to_string(),
            name: "Example".to_string(),
            status: "เปิดอยู่".to_string(),
            status_on: true,
            skin: 0xd4af37,
            chips: ["FiveM".to_string(), String::new()],
            sub: String::new(),
            pick_label: String::new(),
            pick_value: String::new(),
            play_label: "เข้าเกม".to_string(),
            play_enabled,
            show_hours: false,
            hours: None,
            show_invite: false,
            news: Vec::new(),
            patch_title: String::new(),
            patch: Vec::new(),
            operator: String::new(),
            contact: String::new(),
            kind,
        }
    }

    #[test]
    fn safe_link_accepts_valid_https_urls() {
        assert!(safe_link("https://example.com/news/1"));
        assert!(safe_link("https://discord.gg/example"));

        let at_limit = format!("https://example.com/{}", "a".repeat(2028));
        assert_eq!(at_limit.len(), 2048);
        assert!(safe_link(&at_limit));
    }

    #[test]
    fn safe_link_rejects_http_and_javascript_schemes() {
        assert!(!safe_link("http://example.com/news/1"));
        assert!(!safe_link("javascript:alert(1)"));
        assert!(!safe_link(""));
    }

    #[test]
    fn safe_link_rejects_whitespace_and_control_characters() {
        assert!(!safe_link("https://example.com/with space"));
        assert!(!safe_link("https://example.com/with\nnewline"));
        assert!(!safe_link("https://example.com/with\ttab"));
        assert!(!safe_link("https://example.com/with\0null"));
        assert!(!safe_link("https://example.com/with\u{0007}bell"));
    }

    #[test]
    fn safe_link_rejects_over_long_url() {
        let too_long = format!("https://example.com/{}", "a".repeat(2029));
        assert_eq!(too_long.len(), 2049);
        assert!(!safe_link(&too_long));
    }

    #[test]
    fn can_play_checks_each_kind_and_play_enabled() {
        assert!(can_play(&dummy_instance(Kind::Server, true)));
        assert!(!can_play(&dummy_instance(Kind::Server, false)));
        assert!(!can_play(&dummy_instance(Kind::Studio, true)));
        assert!(!can_play(&dummy_instance(Kind::Studio, false)));
        assert!(!can_play(&dummy_instance(Kind::Rongroi, true)));
        assert!(!can_play(&dummy_instance(Kind::Rongroi, false)));
    }
}
