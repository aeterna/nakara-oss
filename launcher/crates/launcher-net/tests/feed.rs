// SPDX-License-Identifier: MIT

//! Tests for the feed parser (ADR 0002 decision 4): every refusal the schema
//! and its limits require, plus accepted cases.

use launcher_net::feed::{parse_feed, Feed, FeedError};

const MAX_FEED_BYTES: usize = 256 * 1024;

fn minimal() -> Vec<u8> {
    br#"{"schema":1,"generated_at":"2026-11-14T08:00:00Z","status":{"state":"open"}}"#.to_vec()
}

/// A feed body whose first news title carries the given JSON string value.
/// `raw` must already be valid JSON (without the surrounding quotes).
fn feed_with_title(raw: &str) -> String {
    format!(
        r#"{{"schema":1,"generated_at":"2026-11-14T08:00:00Z","status":{{"state":"open"}},"news":[{{"title":{raw},"date":"2026-11-13"}}]}}"#,
    )
}

fn news_array(count: usize, title_len: usize) -> String {
    let items: Vec<String> = (0..count)
        .map(|_| format!(r#"{{"title":"{}","date":"2026-11-13"}}"#, "x".repeat(title_len)))
        .collect();
    format!("[{}]", items.join(","))
}

fn patch_notes_array(count: usize, groups: &str) -> String {
    let items: Vec<String> = (0..count)
        .map(|_| {
            format!(
                r#"{{"title":"Note","date":"2026-11-13","groups":[{groups}]}}"#,
            )
        })
        .collect();
    format!("[{}]", items.join(","))
}

fn group_with_items(count: usize, item_len: usize) -> String {
    let items: Vec<String> = (0..count).map(|_| format!(r#""{}""#, "x".repeat(item_len))).collect();
    format!(r#"{{"label":"Fixed","items":[{}]}}"#, items.join(","))
}

fn hours(open: Option<&str>, close: Option<&str>) -> String {
    let open = open.map(|v| format!(r#","open":"{v}""#)).unwrap_or_default();
    let close = close.map(|v| format!(r#","close":"{v}""#)).unwrap_or_default();
    format!(r#""hours":{{"plan":"window","tz":"Asia/Bangkok"{open}{close}}}"#)
}

fn full() -> Vec<u8> {
    br#"{"schema":1,"generated_at":"2026-11-14T08:00:00Z","status":{"state":"maintenance","players":420,"max_players":1024},"hours":{"plan":"window","tz":"Asia/Bangkok","open":"09:00","close":"24:00"},"news":[{"title":"Double XP weekend","date":"2026-11-13","url":"https://example-rp.com/news/double-xp","image":"/img/news/double-xp.webp"}],"patch_notes":[{"title":"1.4.2","date":"2026-11-10","groups":[{"label":"Fixed","items":["Elevator in the docks","Fishing rod durability"]},{"label":"Changed","items":["Taxi routes"]}]}]}"#.to_vec()
}

// --- accepted cases ---

#[test]
fn minimal_feed_parses() {
    let feed: Feed = parse_feed(&minimal()).expect("minimal feed should parse");
    assert_eq!(feed.schema, 1);
    assert_eq!(feed.status.state, launcher_net::feed::FeedState::Open);
    assert_eq!(feed.status.players, None);
    assert_eq!(feed.hours, None);
    assert!(feed.news.is_empty());
    assert!(feed.patch_notes.is_empty());
}

#[test]
fn full_feed_parses() {
    let feed = parse_feed(&full()).expect("full feed should parse");
    assert_eq!(feed.status.players, Some(420));
    let hours = feed.hours.expect("hours should be present");
    assert_eq!(hours.open.as_deref(), Some("09:00"));
    assert_eq!(hours.close.as_deref(), Some("24:00"));
    assert_eq!(feed.news.len(), 1);
    assert_eq!(feed.news[0].title, "Double XP weekend");
    assert_eq!(feed.news[0].url.as_deref(), Some("https://example-rp.com/news/double-xp"));
    assert_eq!(feed.news[0].image.as_deref(), Some("/img/news/double-xp.webp"));
    assert_eq!(feed.patch_notes.len(), 1);
    assert_eq!(feed.patch_notes[0].groups.len(), 2);
    assert_eq!(feed.patch_notes[0].groups[0].items[0], "Elevator in the docks");
}

// --- size and encoding ---

#[test]
fn over_size_cap_refused() {
    let bytes = vec![b' '; MAX_FEED_BYTES + 1];
    assert_eq!(
        parse_feed(&bytes),
        Err(FeedError::TooLarge {
            size: MAX_FEED_BYTES + 1,
            limit: MAX_FEED_BYTES,
        }),
    );
}

#[test]
fn at_size_cap_still_checked_as_json() {
    let bytes = vec![b' '; MAX_FEED_BYTES];
    assert!(matches!(parse_feed(&bytes), Err(FeedError::Json(_))));
}

#[test]
fn invalid_utf8_refused() {
    let mut bytes = minimal();
    bytes.insert(0, 0xff);
    assert!(matches!(parse_feed(&bytes), Err(FeedError::Json(_))));
}

// --- shape ---

#[test]
fn unknown_field_refused() {
    let body = br#"{"schema":1,"generated_at":"2026-11-14T08:00:00Z","status":{"state":"open"},"extra":1}"#;
    assert!(matches!(parse_feed(body), Err(FeedError::Json(_))));
}

#[test]
fn unknown_status_field_refused() {
    let body = br#"{"schema":1,"generated_at":"2026-11-14T08:00:00Z","status":{"state":"open","mood":"calm"}}"#;
    assert!(matches!(parse_feed(body), Err(FeedError::Json(_))));
}

#[test]
fn schema_two_refused() {
    let body = br#"{"schema":2,"generated_at":"2026-11-14T08:00:00Z","status":{"state":"open"}}"#;
    assert_eq!(parse_feed(body), Err(FeedError::Schema(2)));
}

#[test]
fn schema_field_missing_refused() {
    let body = br#"{"generated_at":"2026-11-14T08:00:00Z","status":{"state":"open"}}"#;
    assert!(matches!(parse_feed(body), Err(FeedError::Json(_))));
}

#[test]
fn unknown_state_refused() {
    let body = br#"{"schema":1,"generated_at":"2026-11-14T08:00:00Z","status":{"state":"weird"}}"#;
    assert!(matches!(parse_feed(body), Err(FeedError::Json(_))));
}

#[test]
fn negative_players_refused() {
    let body = br#"{"schema":1,"generated_at":"2026-11-14T08:00:00Z","status":{"state":"open","players":-1}}"#;
    assert!(matches!(parse_feed(body), Err(FeedError::Json(_))));
}

// --- array limits ---

#[test]
fn too_many_news_refused() {
    let mut body = minimal();
    body.truncate(body.len() - 1);
    body.extend_from_slice(format!(r#","news":{}}}"#, news_array(21, 4)).as_bytes());
    assert_eq!(
        parse_feed(&body),
        Err(FeedError::TooManyItems {
            field: "news",
            count: 21,
            limit: 20,
        }),
    );
}

#[test]
fn twenty_news_items_allowed() {
    let mut body = minimal();
    body.truncate(body.len() - 1);
    body.extend_from_slice(format!(r#","news":{}}}"#, news_array(20, 4)).as_bytes());
    assert!(parse_feed(&body).is_ok());
}

#[test]
fn too_many_patch_notes_refused() {
    let mut body = minimal();
    body.truncate(body.len() - 1);
    body.extend_from_slice(format!(r#","patch_notes":{}}}"#, patch_notes_array(11, "")).as_bytes());
    assert_eq!(
        parse_feed(&body),
        Err(FeedError::TooManyItems {
            field: "patch_notes",
            count: 11,
            limit: 10,
        }),
    );
}

#[test]
fn too_many_groups_refused() {
    let groups = (0..7).map(|_| r#"{"label":"Fixed","items":[]}"#).collect::<Vec<_>>().join(",");
    let mut body = minimal();
    body.truncate(body.len() - 1);
    body.extend_from_slice(format!(r#","patch_notes":[{{"title":"Note","date":"2026-11-13","groups":[{groups}]}}]}}"#).as_bytes());
    assert_eq!(
        parse_feed(&body),
        Err(FeedError::TooManyItems {
            field: "patch_notes.groups",
            count: 7,
            limit: 6,
        }),
    );
}

#[test]
fn too_many_group_items_refused() {
    let mut body = minimal();
    body.truncate(body.len() - 1);
    body.extend_from_slice(
        format!(r#","patch_notes":{}}}"#, patch_notes_array(1, &group_with_items(31, 4))).as_bytes(),
    );
    assert_eq!(
        parse_feed(&body),
        Err(FeedError::TooManyItems {
            field: "patch_notes.groups.items",
            count: 31,
            limit: 30,
        }),
    );
}

// --- string limits (characters, not bytes) ---

#[test]
fn too_long_news_title_refused() {
    let body = feed_with_title(format!(r#""{}""#, "x".repeat(121)).as_str());
    assert_eq!(
        parse_feed(body.as_bytes()),
        Err(FeedError::TooLong {
            field: "news.title",
            length: 121,
            limit: 120,
        }),
    );
}

#[test]
fn title_limit_counts_characters_not_bytes() {
    // 120 Thai characters (360 bytes) are fine; 121 are not.
    let ok = feed_with_title(format!(r#""{}""#, "\u{0e01}".repeat(120)).as_str());
    assert!(parse_feed(ok.as_bytes()).is_ok());
    let too_long = feed_with_title(format!(r#""{}""#, "\u{0e01}".repeat(121)).as_str());
    assert!(matches!(parse_feed(too_long.as_bytes()), Err(FeedError::TooLong { .. })));
}

#[test]
fn too_long_tz_refused() {
    let mut body = minimal();
    body.truncate(body.len() - 1);
    let tz = "z".repeat(65);
    body.extend_from_slice(
        format!(r#","hours":{{"plan":"none","tz":"{tz}"}}}}"#).as_bytes(),
    );
    assert_eq!(
        parse_feed(&body),
        Err(FeedError::TooLong {
            field: "hours.tz",
            length: 65,
            limit: 64,
        }),
    );
}

#[test]
fn too_long_group_label_refused() {
    let mut body = minimal();
    body.truncate(body.len() - 1);
    let label = "x".repeat(41);
    body.extend_from_slice(
        format!(r#","patch_notes":[{{"title":"Note","date":"2026-11-13","groups":[{{"label":"{label}","items":[]}}]}}]}}"#).as_bytes(),
    );
    assert_eq!(
        parse_feed(&body),
        Err(FeedError::TooLong {
            field: "patch_notes.groups.label",
            length: 41,
            limit: 40,
        }),
    );
}

#[test]
fn too_long_group_item_refused() {
    let mut body = minimal();
    body.truncate(body.len() - 1);
    body.extend_from_slice(
        format!(r#","patch_notes":{}}}"#, patch_notes_array(1, &group_with_items(1, 301)))
            .as_bytes(),
    );
    assert_eq!(
        parse_feed(&body),
        Err(FeedError::TooLong {
            field: "patch_notes.groups.items",
            length: 301,
            limit: 300,
        }),
    );
}

// --- patterns ---

#[test]
fn open_refuses_2400() {
    let mut body = minimal();
    body.truncate(body.len() - 1);
    body.extend_from_slice(format!(",{}}}", hours(Some("24:00"), None)).as_bytes());
    assert_eq!(
        parse_feed(&body),
        Err(FeedError::Pattern {
            field: "hours.open",
            value: "24:00".to_owned(),
            pattern: "^([01][0-9]|2[0-3]):[0-5][0-9]$".to_owned(),
        }),
    );
}

#[test]
fn open_boundaries_allowed() {
    for open in ["00:00", "23:59", "07:30"] {
        let mut body = minimal();
        body.truncate(body.len() - 1);
        body.extend_from_slice(format!(",{}}}", hours(Some(open), None)).as_bytes());
        assert!(parse_feed(&body).is_ok(), "open {open} should be allowed");
    }
}

#[test]
fn close_allows_2400() {
    let mut body = minimal();
    body.truncate(body.len() - 1);
    body.extend_from_slice(format!(",{}}}", hours(Some("09:00"), Some("24:00"))).as_bytes());
    assert!(parse_feed(&body).is_ok());
}

#[test]
fn close_refuses_2500() {
    let mut body = minimal();
    body.truncate(body.len() - 1);
    body.extend_from_slice(format!(",{}}}", hours(None, Some("25:00"))).as_bytes());
    assert!(matches!(parse_feed(&body), Err(FeedError::Pattern { field: "hours.close", .. })));
}

#[test]
fn bad_minute_refused() {
    let mut body = minimal();
    body.truncate(body.len() - 1);
    body.extend_from_slice(format!(",{}}}", hours(Some("09:60"), None)).as_bytes());
    assert!(matches!(parse_feed(&body), Err(FeedError::Pattern { field: "hours.open", .. })));
}

#[test]
fn short_hour_refused() {
    let mut body = minimal();
    body.truncate(body.len() - 1);
    body.extend_from_slice(format!(",{}}}", hours(Some("9:00"), None)).as_bytes());
    assert!(matches!(parse_feed(&body), Err(FeedError::Pattern { field: "hours.open", .. })));
}

// --- news url and image ---

#[test]
fn http_news_url_refused() {
    let body = feed_with_title(r#""Title","url":"http://example-rp.com/news/a""#);
    assert_eq!(
        parse_feed(body.as_bytes()),
        Err(FeedError::NewsUrl("http://example-rp.com/news/a".to_owned())),
    );
}

#[test]
fn uppercase_scheme_news_url_refused() {
    let body = feed_with_title(r#""Title","url":"HTTPS://example-rp.com/news/a""#);
    assert!(matches!(parse_feed(body.as_bytes()), Err(FeedError::NewsUrl(_))));
}

#[test]
fn image_needs_leading_slash() {
    let body = feed_with_title(r#""Title","image":"img/news/a.png""#);
    assert_eq!(
        parse_feed(body.as_bytes()),
        Err(FeedError::Image("img/news/a.png".to_owned())),
    );
}

#[test]
fn image_extension_restricted() {
    let body = feed_with_title(r#""Title","image":"/img/news/a.gif""#);
    assert!(matches!(parse_feed(body.as_bytes()), Err(FeedError::Image(_))));
}

#[test]
fn image_paths_allowed() {
    for image in ["/a.png", "/img/news/patch_1-2.webp", "/a/b.jpg"] {
        let body = feed_with_title(format!(r#""Title","image":"{image}""#).as_str());
        assert!(parse_feed(body.as_bytes()).is_ok(), "image {image} should be allowed");
    }
}

// --- control and bidi characters ---

#[test]
fn bidi_and_control_characters_refused() {
    let codepoints = [0x061C, 0x200E, 0x200F, 0x202A, 0x202E, 0x2066, 0x2069, 0x0007, 0x001B];
    for cp in codepoints {
        let body = feed_with_title(&format!(r#""bad\u{:04X}text""#, cp));
        assert_eq!(
            parse_feed(body.as_bytes()),
            Err(FeedError::Text {
                field: "news.title",
                character: cp,
            }),
        );
    }
}

#[test]
fn control_char_in_tz_refused() {
    let mut body = minimal();
    body.truncate(body.len() - 1);
    body.extend_from_slice(
        format!(r#","hours":{{"plan":"none","tz":"Asia/Bangkok\n"}}}}"#).as_bytes(),
    );
    assert_eq!(
        parse_feed(&body),
        Err(FeedError::Text {
            field: "hours.tz",
            character: 0x000A,
        }),
    );
}

#[test]
fn bidi_char_in_group_item_refused() {
    let mut body = minimal();
    body.truncate(body.len() - 1);
    body.extend_from_slice(
        format!(r#","patch_notes":[{{"title":"Note","date":"2026-11-13","groups":[{{"label":"Fixed","items":["fixed\u2066thing"]}}]}}]}}"#).as_bytes(),
    );
    assert_eq!(
        parse_feed(&body),
        Err(FeedError::Text {
            field: "patch_notes.groups.items",
            character: 0x2066,
        }),
    );
}
