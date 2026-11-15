// SPDX-License-Identifier: MIT

use crate::text::label;
use crate::theme;
use crate::Message;
use iced::widget::{button, container, row, Space};
use iced::{Background, Border, Color, Element, Length};

pub fn view<'a>() -> Element<'a, Message> {
    let mut buttons: Vec<Element<'a, Message>> = vec![nav_button("หน้าหลัก", true, Message::Noop)];
    if crate::profile::connect_on() {
        buttons.push(nav_button("ตรวจเครื่อง", false, Message::ConnectOpen));
    }

    let nav = container(row(buttons).spacing(2))
        .padding(4)
        .style(theme::panel(theme::SURF, 12.0));

    let settings = container(label("⚙", 16.0, theme::T2))
        .width(40)
        .height(40)
        .align_x(iced::Center)
        .align_y(iced::Center)
        .style(theme::panel(theme::SURF, 12.0));

    row![nav, Space::new().width(Length::Fill), settings]
        .spacing(12)
        .width(Length::Fill)
        .align_y(iced::Center)
        .into()
}

fn nav_button<'a>(title: &str, active: bool, msg: Message) -> Element<'a, Message> {
    let text_color = if active { theme::T1 } else { theme::T2 };

    button(label(title, 14.0, text_color))
        .padding([6, 14])
        .on_press(msg)
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
