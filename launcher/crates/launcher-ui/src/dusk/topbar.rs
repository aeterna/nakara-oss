// SPDX-License-Identifier: MIT

use crate::dusk::glass;
use crate::dusk::icons::{self, Icon};
use crate::text::label;
use crate::Message;
use iced::widget::{button, container, row, Space};
use iced::{Element, Length};

pub fn view<'a>() -> Element<'a, Message> {
    let mut buttons: Vec<Element<'a, Message>> = vec![nav_button("หน้าหลัก", true, Message::Noop)];
    if crate::profile::connect_on() {
        buttons.push(nav_button("ตรวจเครื่อง", false, Message::ConnectOpen));
    }

    let nav = container(row(buttons).spacing(2))
        .padding(4)
        .style(glass::glass(14.0));

    row![nav, Space::new().width(Length::Fill), settings()]
        .spacing(12)
        .width(Length::Fill)
        .align_y(iced::Center)
        .into()
}

fn nav_button<'a>(title: &'static str, active: bool, msg: Message) -> Element<'a, Message> {
    let text_color = if active { glass::INK } else { glass::INK2 };

    button(label(title, 14.0, text_color))
        .padding([8, 16])
        .on_press(msg)
        .style(glass::pill(active, 10.0))
        .into()
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
