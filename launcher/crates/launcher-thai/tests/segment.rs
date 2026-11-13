// SPDX-License-Identifier: MIT

use launcher_thai::insert_zwsp;

const ZWSP: char = '\u{200B}';

const THAI_SENTENCES: &[&str] = &[
    "เมืองปิดอยู่ เปิดอีกครั้ง 17:00",
    "วางรหัสเชิญเข้าเมือง",
    "ตรวจเครื่องด้วย Rongroi Connect",
    "ข้อความทุกคำยังไม่ผ่านการตรวจ",
    "เมืองเปิดอยู่",
    "Nakara City เปิด 17:00",
];

fn strip_zwsp(text: &str) -> String {
    text.chars().filter(|&c| c != ZWSP).collect()
}

fn count_zwsp(text: &str) -> usize {
    text.chars().filter(|&c| c == ZWSP).count()
}

fn is_thai(c: char) -> bool {
    ('\u{0E00}'..='\u{0E7F}').contains(&c)
}

fn assert_zwsp_only_between_thai(text: &str) {
    for (index, c) in text.char_indices() {
        if c != ZWSP {
            continue;
        }

        let before = text[..index].chars().next_back();
        let after = text[index + c.len_utf8()..].chars().next();

        assert!(
            matches!(before, Some(before) if is_thai(before)),
            "ZWSP at byte {index} is not preceded by a Thai character in {text:?}"
        );
        assert!(
            matches!(after, Some(after) if is_thai(after)),
            "ZWSP at byte {index} is not followed by a Thai character in {text:?}"
        );
    }
}

#[test]
fn thai_sentence_gets_zwsp_and_round_trips() {
    let input = "เมืองเปิดอยู่";
    let output = insert_zwsp(input);

    assert!(
        count_zwsp(&output) >= 1,
        "expected at least one ZWSP in {output:?}"
    );
    assert_eq!(strip_zwsp(&output), input);
}

#[test]
fn no_zwsp_next_to_space_digit_or_latin() {
    let input = "Nakara City เปิด 17:00";
    let output = insert_zwsp(input);

    assert_eq!(strip_zwsp(&output), input);
    assert_zwsp_only_between_thai(&output);

    // The only Thai run is "เปิด"; it must not gain a ZWSP beside the spaces,
    // digits or Latin letters around it.
    assert_eq!(output.matches("เปิด").count(), 1);
}

#[test]
fn idempotent() {
    for sentence in THAI_SENTENCES {
        let once = insert_zwsp(sentence);
        let twice = insert_zwsp(&once);

        assert_eq!(once, twice, "not idempotent for {sentence:?}");
        assert!(
            !once.contains("\u{200B}\u{200B}"),
            "found doubled ZWSP in {once:?}"
        );
    }
}

#[test]
fn existing_zwsp_is_removed_before_inserting() {
    let input = "เมื\u{200B}องเปิด\u{200B}อยู่";
    let output = insert_zwsp(input);

    assert!(
        !output.contains("\u{200B}\u{200B}"),
        "found doubled ZWSP in {output:?}"
    );
    assert_eq!(output, insert_zwsp(&strip_zwsp(input)));
}

#[test]
fn removing_zwsp_restores_input() {
    for sentence in THAI_SENTENCES {
        let output = insert_zwsp(sentence);

        assert_eq!(
            strip_zwsp(&output),
            *sentence,
            "round trip failed for {sentence:?}"
        );
    }
}

#[test]
fn empty_and_non_thai_unchanged() {
    assert_eq!(insert_zwsp(""), "");
    assert_eq!(insert_zwsp("hello world"), "hello world");
}
