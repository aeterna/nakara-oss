// SPDX-License-Identifier: MIT

use iced::widget::container;
use iced::{Background, Border, Color};

pub const BG: Color = rgb(0x0e1312);
pub const SURF: Color = rgb(0x141b19);
pub const RAISE: Color = rgb(0x1b2421);
pub const HI: Color = rgb(0x222d2a);
pub const T1: Color = rgb(0xe7ede9);
pub const T2: Color = rgb(0xa8b4af);
pub const T3: Color = rgb(0x717e79);
pub const GOLD: Color = rgb(0xe8b84a);
pub const DOT_ON: Color = rgb(0x6fcf8b);

pub const LINE: Color = Color {
    r: 226.0 / 255.0,
    g: 238.0 / 255.0,
    b: 233.0 / 255.0,
    a: 0.08,
};

pub const fn rgb(hex: u32) -> Color {
    Color {
        r: ((hex >> 16) & 0xff) as f32 / 255.0,
        g: ((hex >> 8) & 0xff) as f32 / 255.0,
        b: (hex & 0xff) as f32 / 255.0,
        a: 1.0,
    }
}

pub fn panel(bg: Color, radius: f32) -> impl Fn(&iced::Theme) -> container::Style {
    move |_theme| container::Style {
        background: Some(Background::Color(bg)),
        border: Border {
            radius: radius.into(),
            ..Border::default()
        },
        ..container::Style::default()
    }
}
