// SPDX-License-Identifier: MIT

use iced::widget::{text, Text};

/// Insert Thai word-break points before text reaches a widget.
pub fn t(s: &str) -> String {
    launcher_thai::insert_zwsp(s)
}

/// The only way this crate creates visible text.
pub fn label<'a>(s: &str, size: f32, color: iced::Color) -> Text<'a> {
    text(t(s)).size(size).style(move |_theme| {
        iced::widget::text::Style {
            color: Some(color),
        }
    })
}
