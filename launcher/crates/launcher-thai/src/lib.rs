// SPDX-License-Identifier: MIT

//! Line-breaking helpers for Thai UI text.
//!
//! Thai is written without spaces between words. A UI toolkit that only breaks
//! lines at spaces or U+200B ZERO WIDTH SPACE therefore treats an entire Thai
//! sentence as one long word and cannot wrap it. This crate uses ICU4X word
//! segmentation to find word boundaries and inserts U+200B between adjacent
//! Thai characters, giving the toolkit legal break points without changing the
//! visible text.

use icu_segmenter::WordSegmenter;

const ZWSP: char = '\u{200B}';

fn is_thai(c: char) -> bool {
    ('\u{0E00}'..='\u{0E7F}').contains(&c)
}

/// Insert U+200B ZERO WIDTH SPACE between Thai words.
///
/// Thai has no spaces between words, but most UI toolkits only break lines at
/// spaces or U+200B. Adding ZWSP at word boundaries lets such a toolkit wrap
/// Thai text correctly.
///
/// A boundary is used only when the character immediately before it and the
/// character immediately after it are both Thai (U+0E00..=U+0E7F). Boundaries
/// at the start or end of the text, or next to whitespace, digits, Latin
/// letters or punctuation, are left alone.
///
/// Existing U+200B characters are removed before segmentation, so the function
/// is idempotent and never doubles them. Removing every U+200B from the result
/// gives back the input with its original U+200B characters removed.
pub fn insert_zwsp(text: &str) -> String {
    // Strip existing ZWSP so repeated calls produce the same result.
    let stripped: String = text.chars().filter(|&c| c != ZWSP).collect();
    if stripped.is_empty() {
        return stripped;
    }

    let segmenter = WordSegmenter::new_auto(Default::default());

    // Collect the boundaries that sit between two Thai characters. The
    // iterator yields byte indices, including 0 and stripped.len(), so those
    // two ends are skipped explicitly.
    let mut boundaries = Vec::new();
    for boundary in segmenter.segment_str(&stripped) {
        if boundary == 0 || boundary >= stripped.len() {
            continue;
        }

        let before = stripped[..boundary].chars().next_back();
        let after = stripped[boundary..].chars().next();
        if matches!(
            (before, after),
            (Some(before), Some(after)) if is_thai(before) && is_thai(after)
        ) {
            boundaries.push(boundary);
        }
    }

    let mut out = String::with_capacity(stripped.len() + boundaries.len() * ZWSP.len_utf8());
    let mut last = 0;
    for boundary in boundaries {
        out.push_str(&stripped[last..boundary]);
        out.push(ZWSP);
        last = boundary;
    }
    out.push_str(&stripped[last..]);

    out
}
