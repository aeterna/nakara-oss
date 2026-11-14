// SPDX-License-Identifier: MIT

use launcher_core::Profile;
use launcher_net::feed::{Feed, FeedState, HoursPlan};

const STUDIO_SKIN: u32 = 0xd4af37;
const NEUTRAL_SKIN: u32 = 0xd4af37;

const MONTHS: [&str; 12] = [
    "ม.ค.",
    "ก.พ.",
    "มี.ค.",
    "เม.ย.",
    "พ.ค.",
    "มิ.ย.",
    "ก.ค.",
    "ส.ค.",
    "ก.ย.",
    "ต.ค.",
    "พ.ย.",
    "ธ.ค.",
];

/// What kind of sidebar entry an [`Instance`] represents.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Server,
    Studio,
    Rongroi,
}

/// One news card shown on the Home board.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewsItem {
    pub title: String,
    pub date: String,
    pub url: Option<String>,
}

/// Data backing one entry on the Home screen.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Instance {
    pub initials: String,
    pub name: String,
    pub status: String,
    pub status_on: bool,
    pub skin: u32,
    pub chips: [String; 2],
    pub sub: String,
    pub pick_label: String,
    pub pick_value: String,
    pub play_label: String,
    pub play_enabled: bool,
    pub show_hours: bool,
    pub hours: Option<String>,
    pub show_invite: bool,
    pub news: Vec<NewsItem>,
    pub patch_title: String,
    pub patch: Vec<(String, Vec<String>)>,
    pub operator: String,
    pub contact: String,
    pub kind: Kind,
}

/// Builds the list of instances shown on Home. Entry 0 is the profile's server;
/// the studio's other games follow when `profile.features.studio_games` is enabled.
pub fn instances(profile: &Profile, feed: Option<&Feed>) -> Vec<Instance> {
    let mut list = vec![server(profile, feed)];
    if profile.features.studio_games {
        list.extend(crate::sample::studio());
    }
    list
}

/// Builds entry 0 (the profile's server) from the embedded profile and optional feed.
pub fn server(profile: &Profile, feed: Option<&Feed>) -> Instance {
    let (status, status_on, play_label, play_enabled, sub) = match feed {
        None => (
            "ยังไม่มีข้อมูลสถานะ".to_string(),
            false,
            "เข้าเกม".to_string(),
            true,
            "ยังไม่ได้ข่าวจากเซิร์ฟ กดเข้าเกมได้ตามปกติ".to_string(),
        ),
        Some(feed) => match feed.status.state {
            FeedState::Open => {
                let status = match (feed.status.players, feed.status.max_players) {
                    (Some(players), Some(max_players)) => {
                        format!("เปิดอยู่ · {players}/{max_players} คน")
                    }
                    _ => "เปิดอยู่".to_string(),
                };
                (
                    status,
                    true,
                    "เข้าเกม".to_string(),
                    true,
                    "เมืองเปิดอยู่ เข้าได้เลย".to_string(),
                )
            }
            FeedState::Closed => {
                let open = feed.hours.as_ref().and_then(|h| {
                    if h.plan == HoursPlan::Window {
                        h.open.as_deref()
                    } else {
                        None
                    }
                });
                let (status, sub) = match open {
                    Some(open) => (
                        format!("เปิด {open}"),
                        format!("เมืองปิดอยู่ เปิดอีกครั้ง {open}"),
                    ),
                    None => ("ปิดอยู่".to_string(), "เมืองปิดอยู่".to_string()),
                };
                let play_label = status.clone();
                (status, false, play_label, false, sub)
            }
            FeedState::Maintenance => (
                "ปิดปรับปรุง".to_string(),
                false,
                "ปิดปรับปรุง".to_string(),
                false,
                "เมืองปิดปรับปรุงชั่วคราว".to_string(),
            ),
            FeedState::Unknown => (
                "ยังไม่มีข้อมูลสถานะ".to_string(),
                false,
                "เข้าเกม".to_string(),
                true,
                "เซิร์ฟไม่ได้บอกสถานะ กดเข้าเกมได้ตามปกติ".to_string(),
            ),
        },
    };

    let hours = feed.and_then(|f| f.hours.as_ref()).and_then(|h| {
        if h.plan == HoursPlan::Window {
            match (&h.open, &h.close) {
                (Some(open), Some(close)) => Some(format!("{open}–{close}")),
                _ => None,
            }
        } else {
            None
        }
    });
    let show_hours = hours.is_some();

    let news = match feed {
        Some(f) => f
            .news
            .iter()
            .map(|item| NewsItem {
                title: item.title.clone(),
                date: thai_date(&item.date),
                url: item.url.clone(),
            })
            .collect(),
        None => Vec::new(),
    };

    let (patch_title, patch) = match feed.and_then(|f| f.patch_notes.first()) {
        Some(note) => (
            format!("{} · {}", note.title, thai_date(&note.date)),
            note.groups
                .iter()
                .map(|g| (g.label.clone(), g.items.clone()))
                .collect(),
        ),
        None => ("ยังไม่มีแพตช์".to_string(), Vec::new()),
    };

    let skin = if profile.features.studio_games {
        STUDIO_SKIN
    } else {
        NEUTRAL_SKIN
    };

    Instance {
        initials: crate::profile::initials(&profile.server.name),
        name: profile.server.name.clone(),
        status,
        status_on,
        skin,
        chips: [
            crate::profile::game_label(&profile.server.game).to_string(),
            String::new(),
        ],
        sub,
        pick_label: "เซิร์ฟเวอร์".to_string(),
        pick_value: profile.server.name.clone(),
        play_label,
        play_enabled,
        show_hours,
        hours,
        show_invite: profile.server.invite_url.is_some(),
        news,
        patch_title,
        patch,
        operator: profile.server.operator.clone(),
        contact: profile.server.contact_email.clone(),
        kind: Kind::Server,
    }
}

/// Formats an ISO `YYYY-MM-DD` date into a short Thai date (`"13 พ.ย."`).
/// Anything that does not parse is returned unchanged.
pub fn thai_date(ymd: &str) -> String {
    let bytes = ymd.as_bytes();
    if bytes.len() != 10
        || bytes[4] != b'-'
        || bytes[7] != b'-'
        || !bytes[..4].iter().all(|b| b.is_ascii_digit())
        || !bytes[5..7].iter().all(|b| b.is_ascii_digit())
        || !bytes[8..10].iter().all(|b| b.is_ascii_digit())
    {
        return ymd.to_string();
    }

    let month = ((bytes[5] - b'0') * 10 + (bytes[6] - b'0')) as usize;
    let day = (bytes[8] - b'0') * 10 + (bytes[9] - b'0');

    if !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return ymd.to_string();
    }

    format!("{day} {}", MONTHS[month - 1])
}

#[cfg(test)]
mod tests {
    use super::*;
    use launcher_net::feed::{Hours, News, PatchGroup, PatchNote, Status};

    fn test_profile(studio_games: bool) -> Profile {
        let toml = format!(
            r#"
schema = 1

[server]
id = "example-rp"
name = "Example RP"
game = "fivem-legacy"
connect = "play.example.com:30120"
operator = "Example RP Team"
contact_email = "team@example.com"
invite_url = "https://discord.gg/example"

[theme]
template = "classic"
accent = "#3f6fd1"

[features]
studio_games = {studio_games}
"#
        );
        launcher_core::parse(&toml).expect("valid test profile")
    }

    fn empty_feed(state: FeedState) -> Feed {
        Feed {
            schema: 1,
            generated_at: "2026-11-14T12:00:00Z".to_string(),
            status: Status {
                state,
                players: None,
                max_players: None,
            },
            hours: None,
            news: Vec::new(),
            patch_notes: Vec::new(),
        }
    }

    #[test]
    fn status_when_feed_is_none() {
        let p = test_profile(false);
        let inst = server(&p, None);
        assert_eq!(inst.name, "Example RP");
        assert_eq!(inst.initials, "ER");
        assert_eq!(inst.chips, ["FiveM".to_string(), String::new()]);
        assert_eq!(inst.pick_label, "เซิร์ฟเวอร์");
        assert_eq!(inst.pick_value, "Example RP");
        assert!(inst.show_invite);
        assert_eq!(inst.kind, Kind::Server);
        assert_eq!(inst.status, "ยังไม่มีข้อมูลสถานะ");
        assert!(!inst.status_on);
        assert!(inst.play_enabled);
        assert_eq!(inst.play_label, "เข้าเกม");
        assert_eq!(inst.sub, "ยังไม่ได้ข่าวจากเซิร์ฟ กดเข้าเกมได้ตามปกติ");
        assert!(!inst.show_hours);
        assert_eq!(inst.hours, None);
        assert!(inst.news.is_empty());
        assert_eq!(inst.patch_title, "ยังไม่มีแพตช์");
        assert!(inst.patch.is_empty());
    }

    #[test]
    fn status_when_open_without_players() {
        let p = test_profile(false);
        let feed = empty_feed(FeedState::Open);
        let inst = server(&p, Some(&feed));
        assert_eq!(inst.status, "เปิดอยู่");
        assert!(inst.status_on);
        assert!(inst.play_enabled);
        assert_eq!(inst.play_label, "เข้าเกม");
        assert_eq!(inst.sub, "เมืองเปิดอยู่ เข้าได้เลย");
    }

    #[test]
    fn status_when_open_with_players() {
        let p = test_profile(false);
        let mut feed = empty_feed(FeedState::Open);
        feed.status.players = Some(42);
        feed.status.max_players = Some(128);
        let inst = server(&p, Some(&feed));
        assert_eq!(inst.status, "เปิดอยู่ · 42/128 คน");
        assert!(inst.status_on);
        assert!(inst.play_enabled);
        assert_eq!(inst.play_label, "เข้าเกม");
        assert_eq!(inst.sub, "เมืองเปิดอยู่ เข้าได้เลย");
    }

    #[test]
    fn status_when_closed_with_window_open() {
        let p = test_profile(false);
        let mut feed = empty_feed(FeedState::Closed);
        feed.hours = Some(Hours {
            plan: HoursPlan::Window,
            tz: "Asia/Bangkok".to_string(),
            open: Some("18:00".to_string()),
            close: Some("24:00".to_string()),
        });
        let inst = server(&p, Some(&feed));
        assert_eq!(inst.status, "เปิด 18:00");
        assert!(!inst.status_on);
        assert!(!inst.play_enabled);
        assert_eq!(inst.play_label, "เปิด 18:00");
        assert_eq!(inst.sub, "เมืองปิดอยู่ เปิดอีกครั้ง 18:00");
        assert!(inst.show_hours);
        assert_eq!(inst.hours.as_deref(), Some("18:00–24:00"));
    }

    #[test]
    fn status_when_closed_without_window() {
        let p = test_profile(false);
        let feed = empty_feed(FeedState::Closed);
        let inst = server(&p, Some(&feed));
        assert_eq!(inst.status, "ปิดอยู่");
        assert!(!inst.status_on);
        assert!(!inst.play_enabled);
        assert_eq!(inst.play_label, "ปิดอยู่");
        assert_eq!(inst.sub, "เมืองปิดอยู่");
        assert!(!inst.show_hours);
        assert_eq!(inst.hours, None);
    }

    #[test]
    fn status_when_maintenance() {
        let p = test_profile(false);
        let feed = empty_feed(FeedState::Maintenance);
        let inst = server(&p, Some(&feed));
        assert_eq!(inst.status, "ปิดปรับปรุง");
        assert!(!inst.status_on);
        assert!(!inst.play_enabled);
        assert_eq!(inst.play_label, "ปิดปรับปรุง");
        assert_eq!(inst.sub, "เมืองปิดปรับปรุงชั่วคราว");
    }

    #[test]
    fn status_when_unknown() {
        let p = test_profile(false);
        let feed = empty_feed(FeedState::Unknown);
        let inst = server(&p, Some(&feed));
        assert_eq!(inst.status, "ยังไม่มีข้อมูลสถานะ");
        assert!(!inst.status_on);
        assert!(inst.play_enabled);
        assert_eq!(inst.play_label, "เข้าเกม");
        assert_eq!(inst.sub, "เซิร์ฟไม่ได้บอกสถานะ กดเข้าเกมได้ตามปกติ");
    }

    #[test]
    fn hours_text_requires_window_plan_and_both_times() {
        let p = test_profile(false);
        let mut feed = empty_feed(FeedState::Open);
        feed.hours = Some(Hours {
            plan: HoursPlan::None,
            tz: "Asia/Bangkok".to_string(),
            open: Some("17:00".to_string()),
            close: Some("00:00".to_string()),
        });
        let inst = server(&p, Some(&feed));
        assert!(!inst.show_hours);
        assert_eq!(inst.hours, None);

        feed.hours = Some(Hours {
            plan: HoursPlan::Window,
            tz: "Asia/Bangkok".to_string(),
            open: Some("17:00".to_string()),
            close: None,
        });
        let inst = server(&p, Some(&feed));
        assert!(!inst.show_hours);
        assert_eq!(inst.hours, None);

        feed.hours = Some(Hours {
            plan: HoursPlan::Window,
            tz: "Asia/Bangkok".to_string(),
            open: Some("17:00".to_string()),
            close: Some("00:00".to_string()),
        });
        let inst = server(&p, Some(&feed));
        assert!(inst.show_hours);
        assert_eq!(inst.hours.as_deref(), Some("17:00–00:00"));
    }

    #[test]
    fn news_and_first_patch_note_are_mapped() {
        let p = test_profile(false);
        let mut feed = empty_feed(FeedState::Open);
        feed.news = vec![News {
            title: "ประกาศสำคัญ".to_string(),
            date: "2026-11-05".to_string(),
            url: Some("https://example.com/news/1".to_string()),
            image: None,
        }];
        feed.patch_notes = vec![
            PatchNote {
                title: "0.2.0".to_string(),
                date: "2026-11-14".to_string(),
                groups: vec![PatchGroup {
                    label: "ใหม่".to_string(),
                    items: vec!["เพิ่มระบบตกปลา".to_string()],
                }],
            },
            PatchNote {
                title: "0.1.0".to_string(),
                date: "2026-10-01".to_string(),
                groups: vec![],
            },
        ];

        let inst = server(&p, Some(&feed));
        assert_eq!(
            inst.news,
            vec![NewsItem {
                title: "ประกาศสำคัญ".to_string(),
                date: "5 พ.ย.".to_string(),
                url: Some("https://example.com/news/1".to_string()),
            }]
        );
        assert_eq!(inst.patch_title, "0.2.0 · 14 พ.ย.");
        assert_eq!(
            inst.patch,
            vec![("ใหม่".to_string(), vec!["เพิ่มระบบตกปลา".to_string()])]
        );
    }

    #[test]
    fn thai_date_formats_valid_and_preserves_invalid() {
        assert_eq!(thai_date("2026-11-13"), "13 พ.ย.");
        assert_eq!(thai_date("2026-01-05"), "5 ม.ค.");
        assert_eq!(thai_date("2026-12-31"), "31 ธ.ค.");
        assert_eq!(thai_date("2026-13-01"), "2026-13-01");
        assert_eq!(thai_date("2026-00-10"), "2026-00-10");
        assert_eq!(thai_date("2026-11-00"), "2026-11-00");
        assert_eq!(thai_date("not-a-date"), "not-a-date");
        assert_eq!(thai_date(""), "");
    }

    #[test]
    fn entry_zero_never_contains_sample_strings() {
        for studio in [false, true] {
            let p = test_profile(studio);
            let list = instances(&p, None);
            let first = &list[0];
            assert!(!first.patch_title.contains("แพตช์ 13 พ.ย."));
            assert!(first
                .news
                .iter()
                .all(|n| !n.title.contains("ชั่วโมงเมืองใหม่")));
            assert!(!first.sub.contains("ชั่วโมงเมืองใหม่"));
        }

        let p_studio = test_profile(true);
        let list = instances(&p_studio, None);
        assert_eq!(list.len(), 4);
        assert_eq!(list[0].kind, Kind::Server);
        assert_eq!(list[1].kind, Kind::Studio);
        assert_eq!(list[2].kind, Kind::Studio);
        assert_eq!(list[3].name, "Rongroi");
        assert_eq!(list[3].kind, Kind::Rongroi);
    }
}
