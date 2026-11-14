// SPDX-License-Identifier: MIT

use crate::dusk::glass;
use crate::dusk::icons::{self, Icon};
use crate::text::label;
use crate::Message;
use iced::widget::{button, column, container, row, Space};
use iced::{Element, Length, Padding};

const NAV: [&str; 5] = ["หน้าหลัก", "ข่าว", "เซิร์ฟเวอร์", "ตรวจเครื่อง", "บันทึกแพตช์"];

pub fn view<'a>() -> Element<'a, Message> {
    let mut buttons: Vec<Element<'a, Message>> = Vec::new();
    for title in NAV.iter() {
        if *title == "ตรวจเครื่อง" && !crate::profile::connect_on() {
            continue;
        }

        let active = buttons.is_empty();
        buttons.push(nav_button(*title, active));
    }

    let nav = container(row(buttons).spacing(2))
        .padding(4)
        .style(glass::glass(14.0));

    row![nav, Space::new().width(Length::Fill), account(), settings(),]
        .spacing(12)
        .width(Length::Fill)
        .align_y(iced::Center)
        .into()
}

fn nav_button<'a>(title: &'static str, active: bool) -> Element<'a, Message> {
    let text_color = if active { glass::INK } else { glass::INK2 };

    button(label(title, 14.0, text_color))
        .padding([8, 16])
        .on_press(Message::Noop)
        .style(glass::pill(active, 10.0))
        .into()
}

fn account<'a>() -> Element<'a, Message> {
    let avatar = container(icons::icon(Icon::User, 16.0, glass::INK))
        .width(30)
        .height(30)
        .align_x(iced::Center)
        .align_y(iced::Center)
        .style(glass::tint(0.10, 9.0));

    let who = column![
        label("ผู้เล่น", 13.0, glass::INK),
        label("ยังไม่ได้เข้าสู่ระบบ", 11.0, glass::MUTED),
    ]
    .spacing(0);

    let face = button(row![avatar, who].spacing(10).align_y(iced::Center))
        .padding(Padding {
            top: 6.0,
            right: 14.0,
            bottom: 6.0,
            left: 8.0,
        })
        .on_press(Message::Noop)
        .style(transparent);

    container(face).style(glass::glass(14.0)).into()
}

fn settings<'a>() -> Element<'a, Message> {
    let face = container(icons::icon(Icon::Sliders, 18.0, glass::INK2))
        .width(44)
        .height(44)
        .align_x(iced::Center)
        .align_y(iced::Center);

    let body = button(face)
        .padding(0)
        .on_press(Message::Noop)
        .style(transparent);

    container(body).style(glass::glass(14.0)).into()
}

fn transparent(_theme: &iced::Theme, _status: button::Status) -> button::Style {
    button::Style {
        background: None,
        text_color: glass::INK,
        ..button::Style::default()
    }
}
