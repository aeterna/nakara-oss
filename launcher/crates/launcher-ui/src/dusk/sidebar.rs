// SPDX-License-Identifier: MIT

use crate::dusk::glass;
use crate::dusk::icons::{self, Icon};
use crate::sample;
use crate::text::label;
use crate::theme;
use crate::Message;
use iced::widget::{button, column, container, row, Space};
use iced::{Background, Border, Color, Element, Length, Padding};

pub fn view<'a>(selected: usize) -> Element<'a, Message> {
    let mut list = column![brand(), section("เกม", 8.0)]
        .spacing(4)
        .width(Length::Fill)
        .height(Length::Fill);

    for index in 0..crate::sample::instances().len() {
        list = list.push(instance_button(index, selected));
    }

    list = list.push(section("กิจกรรมของเมือง", 16.0));
    list = list.push(event_card());
    list = list.push(Space::new().height(Length::Fill));

    if crate::profile::invite_url().is_some() {
        list = list.push(discord_button());
    }

    list = list.push(website());
    list = list.push(version());

    container(list)
        .width(248)
        .height(Length::Fill)
        .padding([16, 12])
        .style(glass::glass(18.0))
        .into()
}

fn brand<'a>() -> Element<'a, Message> {
    let brand = crate::profile::brand();
    let letter = brand
        .chars()
        .next()
        .map(|first| first.to_uppercase().collect::<String>())
        .unwrap_or_else(|| "?".to_string());

    let mark = container(label(&letter, 15.0, Color::WHITE))
        .width(30)
        .height(30)
        .align_x(iced::Center)
        .align_y(iced::Center)
        .style(theme::panel(theme::rgb(0x119a7a), 9.0));

    let name = column![
        label(brand, 15.0, glass::INK),
        label("Launcher", 12.0, glass::MUTED),
    ]
    .spacing(0);

    container(row![mark, name].spacing(10).align_y(iced::Center))
        .width(Length::Fill)
        .padding(Padding {
            top: 0.0,
            right: 8.0,
            bottom: 12.0,
            left: 8.0,
        })
        .into()
}

fn section<'a>(title: &'static str, top: f32) -> Element<'a, Message> {
    container(label(title, 12.0, glass::MUTED))
        .width(Length::Fill)
        .padding(Padding {
            top,
            right: 8.0,
            bottom: 6.0,
            left: 8.0,
        })
        .into()
}

fn instance_button<'a>(index: usize, selected: usize) -> Element<'a, Message> {
    let inst = &crate::sample::instances()[index];

    let tile = container(label(inst.initials, 13.0, theme::rgb(inst.skin)))
        .width(38)
        .height(38)
        .align_x(iced::Center)
        .align_y(iced::Center)
        .style(|_theme| container::Style {
            background: Some(Background::Color(rgba(0x10181c, 0.9))),
            border: Border {
                radius: 10.0.into(),
                ..Border::default()
            },
            ..container::Style::default()
        });

    let dot = container(Space::new().width(6).height(6)).style(theme::panel(
        if inst.status_on {
            theme::DOT_ON
        } else {
            theme::GOLD
        },
        3.0,
    ));

    let lines = column![
        label(inst.name, 14.0, glass::INK),
        row![dot, label(inst.status, 12.0, glass::MUTED)]
            .spacing(6)
            .align_y(iced::Center),
    ]
    .spacing(2);

    let content = row![tile, lines].spacing(10).align_y(iced::Center);

    button(content)
        .width(Length::Fill)
        .padding(8)
        .on_press(Message::Select(index))
        .style(glass::pill(index == selected, 12.0))
        .into()
}

fn event_card<'a>() -> Element<'a, Message> {
    let info = column![
        label(sample::EVENT.0, 15.0, glass::INK),
        label(sample::EVENT.1, 12.0, glass::MUTED),
        detail_button(),
    ]
    .spacing(4)
    .width(Length::Fill);

    let info = container(info).padding(Padding {
        top: 12.0,
        right: 14.0,
        bottom: 14.0,
        left: 14.0,
    });

    container(column![event_picture(), info].width(Length::Fill))
        .width(Length::Fill)
        .style(glass::well(14.0))
        .into()
}

fn event_picture<'a>() -> Element<'a, Message> {
    let gradient = iced::Gradient::Linear(
        iced::gradient::Linear::new(iced::Radians(std::f32::consts::PI))
            .add_stop(0.0, rgba(0x0b2230, 1.0))
            .add_stop(0.5, rgba(0x17424a, 1.0))
            .add_stop(1.0, rgba(0xa8763f, 1.0)),
    );

    let mut border = Border::default();
    border.radius.top_left = 14.0;
    border.radius.top_right = 14.0;

    container(Space::new().width(Length::Fill).height(Length::Fill))
        .width(Length::Fill)
        .height(108)
        .style(move |_theme| container::Style {
            background: Some(Background::Gradient(gradient)),
            border,
            ..container::Style::default()
        })
        .into()
}

fn detail_button<'a>() -> Element<'a, Message> {
    button(
        container(label("ดูรายละเอียด", 14.0, glass::LINK))
            .width(Length::Fill)
            .height(Length::Fill)
            .align_x(iced::Center)
            .align_y(iced::Center),
    )
    .width(Length::Fill)
    .height(36)
    .padding(0)
    .on_press(Message::Noop)
    .style(|_theme, _status| button::Style {
        background: None,
        text_color: glass::LINK,
        border: Border {
            color: rgba(0x7fd8c0, 0.45),
            width: 1.0,
            radius: 10.0.into(),
        },
        ..button::Style::default()
    })
    .into()
}

fn discord_button<'a>() -> Element<'a, Message> {
    let content = row![
        icons::icon(Icon::Chat, 16.0, glass::INK),
        label("เข้า Discord ของเมือง", 14.0, glass::INK),
    ]
    .spacing(8)
    .align_y(iced::Center);

    button(
        container(content)
            .width(Length::Fill)
            .height(Length::Fill)
            .align_x(iced::Center)
            .align_y(iced::Center),
    )
    .width(Length::Fill)
    .height(42)
    .padding(0)
    .on_press(Message::Noop)
    .style(glass::solid(rgba(0xdcf0ea, 0.08), 12.0))
    .into()
}

fn website<'a>() -> Element<'a, Message> {
    container(
        row![
            icons::icon(Icon::Globe, 16.0, glass::INK2),
            label("เว็บไซต์", 14.0, glass::INK2),
        ]
        .spacing(10)
        .align_y(iced::Center),
    )
    .padding(8)
    .into()
}

fn version<'a>() -> Element<'a, Message> {
    container(label("Launcher 0.1.0", 11.0, glass::FAINT))
        .padding([0, 8])
        .into()
}

fn rgba(hex: u32, a: f32) -> Color {
    Color {
        r: ((hex >> 16) & 0xff) as f32 / 255.0,
        g: ((hex >> 8) & 0xff) as f32 / 255.0,
        b: (hex & 0xff) as f32 / 255.0,
        a,
    }
}
