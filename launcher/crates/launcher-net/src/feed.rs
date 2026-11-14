// SPDX-License-Identifier: MIT

//! The launcher feed: types, parsing and validation (ADR 0002 decision 4).
//!
//! The shape and limits follow `launcher/schema/feed.schema.json` (schema 1).
//! The feed is data only: no HTML, scripts or markup. [`parse_feed`] refuses
//! a body larger than [`MAX_FEED_BYTES`], unknown fields, a schema other than
//! 1, counts or string lengths over the schema's limits, malformed dates and
//! times, a news link that is not `https://`, an image path outside the
//! schema's pattern, and control or bidi characters in any text.

use serde::Deserialize;
use thiserror::Error;

/// Largest feed accepted, in bytes.
pub const MAX_FEED_BYTES: usize = 256 * 1024;

const MAX_NEWS: usize = 20;
const MAX_PATCH_NOTES: usize = 10;
const MAX_GROUPS: usize = 6;
const MAX_GROUP_ITEMS: usize = 30;
const MAX_TITLE_CHARS: usize = 120;
const MAX_TZ_CHARS: usize = 64;
const MAX_LABEL_CHARS: usize = 40;
const MAX_ITEM_CHARS: usize = 300;

const DATE_PATTERN: &str = "YYYY-MM-DD";
const DATE_TIME_PATTERN: &str = "RFC 3339 date-time";
const OPEN_PATTERN: &str = "^([01][0-9]|2[0-3]):[0-5][0-9]$";
const CLOSE_PATTERN: &str = "^([01][0-9]|2[0-4]):[0-5][0-9]$";
const IMAGE_PATTERN: &str = "^/[A-Za-z0-9._/-]+\\.(png|webp|jpg)$";

/// A parsed launcher feed.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Feed {
    /// Feed schema version; must be 1.
    pub schema: u32,
    /// When the feed was generated, as an RFC 3339 date-time.
    pub generated_at: String,
    /// Current server status.
    pub status: Status,
    /// Published opening hours, when the server has them.
    #[serde(default)]
    pub hours: Option<Hours>,
    /// News items, newest first.
    #[serde(default)]
    pub news: Vec<News>,
    /// Patch notes, newest first.
    #[serde(default)]
    pub patch_notes: Vec<PatchNote>,
}

/// Server status shown beside the play button.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Status {
    /// The state the server reports.
    pub state: FeedState,
    /// Players online now.
    pub players: Option<u64>,
    /// The server's player limit.
    pub max_players: Option<u64>,
}

/// The four states a server can report.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FeedState {
    /// Players can join.
    Open,
    /// Players cannot join.
    Closed,
    /// The server is being worked on.
    Maintenance,
    /// The server did not say.
    Unknown,
}

/// Published opening hours.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Hours {
    /// How the hours apply.
    pub plan: HoursPlan,
    /// IANA time-zone name the times are in.
    pub tz: String,
    /// Opening time, `HH:MM`, when `plan` is `window`.
    pub open: Option<String>,
    /// Closing time, `HH:MM` or `24:00`, when `plan` is `window`.
    pub close: Option<String>,
}

/// How opening hours apply.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum HoursPlan {
    /// Open all day.
    None,
    /// Open between `open` and `close`.
    Window,
}

/// One news item.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct News {
    /// Headline, plain text.
    pub title: String,
    /// Publication date, `YYYY-MM-DD`.
    pub date: String,
    /// HTTPS link, opened in the browser.
    pub url: Option<String>,
    /// Image path on the feed host.
    pub image: Option<String>,
}

/// One patch note.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PatchNote {
    /// Version or title, plain text.
    pub title: String,
    /// Publication date, `YYYY-MM-DD`.
    pub date: String,
    /// Changes, grouped under labels.
    pub groups: Vec<PatchGroup>,
}

/// A labelled group of changes in a patch note.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PatchGroup {
    /// Group label, plain text.
    pub label: String,
    /// The changes, each plain text.
    pub items: Vec<String>,
}

/// Why a feed was refused.
#[derive(Debug, Clone, PartialEq, Error)]
pub enum FeedError {
    /// The body is larger than [`MAX_FEED_BYTES`].
    #[error("feed is {size} bytes, over the {limit}-byte limit")]
    TooLarge { size: usize, limit: usize },

    /// The body is not valid JSON, or has an unknown or missing field.
    #[error("invalid feed JSON: {0}")]
    Json(String),

    /// The feed schema is not 1.
    #[error("feed schema must be 1, got {0}")]
    Schema(u32),

    /// An array holds more items than the schema allows.
    #[error("{field} has {count} items, the limit is {limit}")]
    TooManyItems {
        field: &'static str,
        count: usize,
        limit: usize,
    },

    /// A string is longer, in characters, than the schema allows.
    #[error("{field} is {length} characters, the limit is {limit}")]
    TooLong {
        field: &'static str,
        length: usize,
        limit: usize,
    },

    /// A string does not match the schema's pattern.
    #[error("{field}: {value:?} does not match {pattern}")]
    Pattern {
        field: &'static str,
        value: String,
        pattern: String,
    },

    /// A news link is not `https://`.
    #[error("news url {0:?} is not https")]
    NewsUrl(String),

    /// An image path is outside the schema's pattern.
    #[error("image path {0:?} is not allowed")]
    Image(String),

    /// Text contains a control or bidi character.
    #[error("{field} contains forbidden character U+{character:04X}")]
    Text {
        field: &'static str,
        character: u32,
    },
}

/// Parses and validates feed bytes.
///
/// Refuses a body larger than [`MAX_FEED_BYTES`], invalid JSON, an unknown or
/// missing field, a schema other than 1, counts or string lengths over the
/// schema's limits, malformed dates and times, a news `url` that is not
/// `https://`, an `image` outside the schema's path pattern, and control or
/// bidi characters in text.
pub fn parse_feed(bytes: &[u8]) -> Result<Feed, FeedError> {
    if bytes.len() > MAX_FEED_BYTES {
        return Err(FeedError::TooLarge {
            size: bytes.len(),
            limit: MAX_FEED_BYTES,
        });
    }

    let feed: Feed =
        serde_json::from_slice(bytes).map_err(|error| FeedError::Json(error.to_string()))?;
    validate(&feed)?;
    Ok(feed)
}

fn validate(feed: &Feed) -> Result<(), FeedError> {
    if feed.schema != 1 {
        return Err(FeedError::Schema(feed.schema));
    }

    check_text("generated_at", &feed.generated_at)?;
    check_pattern(
        "generated_at",
        &feed.generated_at,
        is_date_time(&feed.generated_at),
        DATE_TIME_PATTERN,
    )?;

    if let Some(hours) = &feed.hours {
        check_length("hours.tz", &hours.tz, MAX_TZ_CHARS)?;
        check_text("hours.tz", &hours.tz)?;
        if let Some(open) = &hours.open {
            check_text("hours.open", open)?;
            check_pattern("hours.open", open, is_time(open, false), OPEN_PATTERN)?;
        }
        if let Some(close) = &hours.close {
            check_text("hours.close", close)?;
            check_pattern("hours.close", close, is_time(close, true), CLOSE_PATTERN)?;
        }
    }

    check_count("news", feed.news.len(), MAX_NEWS)?;
    for item in &feed.news {
        check_length("news.title", &item.title, MAX_TITLE_CHARS)?;
        check_text("news.title", &item.title)?;
        check_text("news.date", &item.date)?;
        check_pattern("news.date", &item.date, is_date(&item.date), DATE_PATTERN)?;
        if let Some(url) = &item.url {
            check_text("news.url", url)?;
            if !url.starts_with("https://") {
                return Err(FeedError::NewsUrl(url.clone()));
            }
        }
        if let Some(image) = &item.image {
            check_text("news.image", image)?;
            if !valid_image(image) {
                return Err(FeedError::Image(image.clone()));
            }
        }
    }

    check_count("patch_notes", feed.patch_notes.len(), MAX_PATCH_NOTES)?;
    for note in &feed.patch_notes {
        check_length("patch_notes.title", &note.title, MAX_TITLE_CHARS)?;
        check_text("patch_notes.title", &note.title)?;
        check_text("patch_notes.date", &note.date)?;
        check_pattern(
            "patch_notes.date",
            &note.date,
            is_date(&note.date),
            DATE_PATTERN,
        )?;
        check_count("patch_notes.groups", note.groups.len(), MAX_GROUPS)?;
        for group in &note.groups {
            check_length("patch_notes.groups.label", &group.label, MAX_LABEL_CHARS)?;
            check_text("patch_notes.groups.label", &group.label)?;
            check_count(
                "patch_notes.groups.items",
                group.items.len(),
                MAX_GROUP_ITEMS,
            )?;
            for entry in &group.items {
                check_length("patch_notes.groups.items", entry, MAX_ITEM_CHARS)?;
                check_text("patch_notes.groups.items", entry)?;
            }
        }
    }

    Ok(())
}

fn check_count(field: &'static str, count: usize, limit: usize) -> Result<(), FeedError> {
    if count > limit {
        Err(FeedError::TooManyItems {
            field,
            count,
            limit,
        })
    } else {
        Ok(())
    }
}

fn check_length(field: &'static str, value: &str, limit: usize) -> Result<(), FeedError> {
    let length = value.chars().count();
    if length > limit {
        Err(FeedError::TooLong {
            field,
            length,
            limit,
        })
    } else {
        Ok(())
    }
}

fn check_text(field: &'static str, value: &str) -> Result<(), FeedError> {
    if let Some(character) = value.chars().find(|character| forbidden(*character)) {
        return Err(FeedError::Text {
            field,
            character: character as u32,
        });
    }
    Ok(())
}

fn check_pattern(
    field: &'static str,
    value: &str,
    ok: bool,
    pattern: &str,
) -> Result<(), FeedError> {
    if ok {
        Ok(())
    } else {
        Err(FeedError::Pattern {
            field,
            value: value.to_owned(),
            pattern: pattern.to_owned(),
        })
    }
}

fn forbidden(character: char) -> bool {
    character.is_control()
        || matches!(
            character,
            '\u{061C}'
                | '\u{200E}'
                | '\u{200F}'
                | '\u{202A}'..='\u{202E}'
                | '\u{2066}'..='\u{2069}'
        )
}

fn valid_image(value: &str) -> bool {
    let Some(rest) = value.strip_prefix('/') else {
        return false;
    };
    let Some(stem) = rest
        .strip_suffix(".png")
        .or_else(|| rest.strip_suffix(".webp"))
        .or_else(|| rest.strip_suffix(".jpg"))
    else {
        return false;
    };
    !stem.is_empty() && stem.bytes().all(image_char)
}

fn image_char(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'/' | b'_' | b'-')
}

fn is_date(value: &str) -> bool {
    is_date_bytes(value.as_bytes())
}

fn is_date_bytes(bytes: &[u8]) -> bool {
    bytes.len() == 10
        && bytes[4] == b'-'
        && bytes[7] == b'-'
        && bytes[..4].iter().all(|byte| byte.is_ascii_digit())
        && matches!(two_digits(bytes, 5), Some(1..=12))
        && matches!(two_digits(bytes, 8), Some(1..=31))
}

fn is_time(value: &str, allow_24: bool) -> bool {
    let bytes = value.as_bytes();
    if bytes.len() != 5 || bytes[2] != b':' {
        return false;
    }
    let (Some(hour), Some(minute)) = (two_digits(bytes, 0), two_digits(bytes, 3)) else {
        return false;
    };
    let max_hour = if allow_24 { 24 } else { 23 };
    hour <= max_hour && minute <= 59
}

fn is_date_time(value: &str) -> bool {
    let bytes = value.as_bytes();
    if bytes.len() < 20 || !is_date_bytes(&bytes[..10]) {
        return false;
    }
    if !matches!(bytes[10], b'T' | b't') || bytes[13] != b':' || bytes[16] != b':' {
        return false;
    }
    let (Some(hour), Some(minute), Some(second)) = (
        two_digits(bytes, 11),
        two_digits(bytes, 14),
        two_digits(bytes, 17),
    ) else {
        return false;
    };
    if hour > 23 || minute > 59 || second > 60 {
        return false;
    }

    let mut index = 19;
    if bytes.get(index) == Some(&b'.') {
        index += 1;
        let start = index;
        while bytes.get(index).is_some_and(|byte| byte.is_ascii_digit()) {
            index += 1;
        }
        if index == start {
            return false;
        }
    }
    match bytes.get(index).copied() {
        Some(b'Z') | Some(b'z') => index + 1 == bytes.len(),
        Some(b'+') | Some(b'-') => {
            index + 6 == bytes.len()
                && bytes[index + 3] == b':'
                && matches!(two_digits(bytes, index + 1), Some(0..=23))
                && matches!(two_digits(bytes, index + 4), Some(0..=59))
        }
        _ => false,
    }
}

fn two_digits(bytes: &[u8], start: usize) -> Option<u8> {
    let high = *bytes.get(start)?;
    let low = *bytes.get(start + 1)?;
    if high.is_ascii_digit() && low.is_ascii_digit() {
        Some((high - b'0') * 10 + (low - b'0'))
    } else {
        None
    }
}
