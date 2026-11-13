// SPDX-License-Identifier: MIT

use iced::widget::{button, container};
use iced::{Background, Border, Color};

pub const INK: Color = rgb(0xeef4f1);
pub const INK2: Color = rgb(0xc7d6d1);
pub const MUTED: Color = rgb(0xa9bcb6);
pub const FAINT: Color = rgb(0x93a7a1);
pub const ACCENT: Color = rgb(0x0c7a60);
pub const LINK: Color = rgb(0x7fd8c0);

const GLASS_BG: Color = rgba(0x091418, 0.52);
const GLASS_LINE: Color = rgba(0xdcf0ea, 0.10);
const WELL_BG: Color = rgba(0x060e12, 0.45);
const WELL_LINE: Color = rgba(0xdcf0ea, 0.07);
const PILL_ACTIVE: Color = rgba(0xdcf0ea, 0.12);
const PILL_HOVER: Color = rgba(0xdcf0ea, 0.07);

const fn rgb(hex: u32) -> Color {
    rgba(hex, 1.0)
}

const fn rgba(hex: u32, a: f32) -> Color {
    Color {
        r: ((hex >> 16) & 0xff) as f32 / 255.0,
        g: ((hex >> 8) & 0xff) as f32 / 255.0,
        b: (hex & 0xff) as f32 / 255.0,
        a,
    }
}

pub fn glass(radius: f32) -> impl Fn(&iced::Theme) -> container::Style {
    move |_theme| container::Style {
        background: Some(Background::Color(GLASS_BG)),
        border: Border {
            color: GLASS_LINE,
            width: 1.0,
            radius: radius.into(),
        },
        ..container::Style::default()
    }
}

pub fn well(radius: f32) -> impl Fn(&iced::Theme) -> container::Style {
    move |_theme| container::Style {
        background: Some(Background::Color(WELL_BG)),
        border: Border {
            color: WELL_LINE,
            width: 1.0,
            radius: radius.into(),
        },
        ..container::Style::default()
    }
}

pub fn tint(alpha: f32, radius: f32) -> impl Fn(&iced::Theme) -> container::Style {
    move |_theme| container::Style {
        background: Some(Background::Color(Color {
            a: alpha,
            ..rgba(0xdcf0ea, 1.0)
        })),
        border: Border {
            radius: radius.into(),
            ..Border::default()
        },
        ..container::Style::default()
    }
}

pub fn pill(active: bool, radius: f32) -> impl Fn(&iced::Theme, button::Status) -> button::Style {
    move |_theme, status| {
        let (background, text_color) = if active {
            (PILL_ACTIVE, INK)
        } else {
            match status {
                button::Status::Hovered => (PILL_HOVER, INK),
                _ => (Color::TRANSPARENT, INK2),
            }
        };

        button::Style {
            background: Some(Background::Color(background)),
            text_color,
            border: Border {
                radius: radius.into(),
                ..Border::default()
            },
            ..button::Style::default()
        }
    }
}

pub fn solid(bg: Color, radius: f32) -> impl Fn(&iced::Theme, button::Status) -> button::Style {
    move |_theme, status| {
        let background = match status {
            button::Status::Hovered => Color {
                a: (bg.a + 0.06).min(1.0),
                ..bg
            },
            _ => bg,
        };

        button::Style {
            background: Some(Background::Color(background)),
            text_color: Color::WHITE,
            border: Border {
                radius: radius.into(),
                ..Border::default()
            },
            ..button::Style::default()
        }
    }
}
