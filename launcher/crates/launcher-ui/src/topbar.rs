// SPDX-License-Identifier: MIT

use crate::text::label;
use crate::theme;
use crate::Message;
use iced::widget::{button, column, container, row, Space};
use iced::{Background, Border, Color, Element, Length};

const NAV: [&str; 5] = ["หน้าหลัก", "ข่าว", "เซิร์ฟเวอร์", "ตรวจเครื่อง", "บันทึกแพตช์"];

pub fn view<'a>() -> Element<'a, Message> {
    let nav = container(
        row![
            nav_button(NAV[0], true),
            nav_button(NAV[1], false),
            nav_button(NAV[2], false),
            nav_button(NAV[3], false),
            nav_button(NAV[4], false),
        ]
        .spacing(2),
    )
    .padding(4)
    .style(theme::panel(theme::SURF, 12.0));

    let account = container(
        column![
            label("ผู้เล่น", 14.0, theme::T1),
            label("ยังไม่ได้เข้าสู่ระบบ", 11.0, theme::T3),
        ]
        .spacing(0),
    )
    .padding([6, 12])
    .style(theme::panel(theme::SURF, 12.0));

    let settings = container(label("⚙", 16.0, theme::T2))
        .width(40)
        .height(40)
        .align_x(iced::Center)
        .align_y(iced::Center)
        .style(theme::panel(theme::SURF, 12.0));

    row![nav, Space::new().width(Length::Fill), account, settings]
        .spacing(12)
        .width(Length::Fill)
        .align_y(iced::Center)
        .into()
}

fn nav_button<'a>(title: &str, active: bool) -> Element<'a, Message> {
    let text_color = if active { theme::T1 } else { theme::T2 };

    button(label(title, 14.0, text_color))
        .padding([6, 14])
        .on_press(Message::Noop)
        .style(move |_theme, status| {
            let background = match status {
                button::Status::Hovered if active => theme::HI,
                button::Status::Hovered => theme::RAISE,
                _ if active => theme::RAISE,
                _ => Color::TRANSPARENT,
            };

            button::Style {
                background: Some(Background::Color(background)),
                text_color,
                border: Border {
                    radius: 8.0.into(),
                    ..Default::default()
                },
                ..Default::default()
            }
        })
        .into()
}
