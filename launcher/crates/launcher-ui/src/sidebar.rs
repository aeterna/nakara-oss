// SPDX-License-Identifier: MIT

use crate::model::Instance;
use crate::text::label;
use crate::theme;
use crate::Message;
use iced::widget::{button, column, container, row, Space};
use iced::{Background, Border, Color, Element, Length};

pub fn view<'a>(instances: &'a [Instance], selected: usize) -> Element<'a, Message> {
    let mut list = column![brand(), section("เกม")]
        .spacing(4)
        .width(Length::Fill)
        .height(Length::Fill);

    for index in 0..instances.len().min(3) {
        list = list.push(instance_button(&instances[index], index, selected));
    }

    if instances.len() > 3 {
        list = list.push(section("เครื่องมือ"));
        list = list.push(instance_button(&instances[3], 3, selected));
    }

    list = list.push(Space::new().height(Length::Fill));

    if crate::profile::invite_url().is_some() {
        list = list.push(discord_button());
    }
    list = list.push(container(row![label("เว็บไซต์", 14.0, theme::T2)]).padding([8, 8]));
    list =
        list.push(container(row![label("Launcher 0.1.0 · ร่าง", 11.0, theme::T3)]).padding([4, 8]));

    container(list)
        .width(248)
        .height(Length::Fill)
        .padding([16, 12])
        .style(theme::panel(theme::SURF, 12.0))
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
        .width(28)
        .height(28)
        .align_x(iced::Center)
        .align_y(iced::Center)
        .style(theme::panel(theme::rgb(0x119a7a), 8.0));

    let name = column![
        label(brand, 15.0, theme::T1),
        label("Launcher", 12.0, theme::T3),
    ]
    .spacing(0);

    row![mark, name].spacing(10).align_y(iced::Center).into()
}

fn section<'a>(title: &str) -> Element<'a, Message> {
    container(label(title, 12.0, theme::T3))
        .width(Length::Fill)
        .padding(iced::Padding {
            top: 16.0,
            right: 0.0,
            bottom: 6.0,
            left: 8.0,
        })
        .into()
}

fn instance_button<'a>(inst: &'a Instance, index: usize, selected: usize) -> Element<'a, Message> {
    let skin = theme::rgb(inst.skin);

    let tile = container(label(&inst.initials, 13.0, skin))
        .width(36)
        .height(36)
        .align_x(iced::Center)
        .align_y(iced::Center)
        .style(theme::panel(theme::HI, 8.0));

    let dot = container(Space::new().width(6).height(6)).style(theme::panel(
        if inst.status_on {
            theme::DOT_ON
        } else {
            theme::GOLD
        },
        3.0,
    ));

    let lines = column![
        label(&inst.name, 14.0, theme::T1),
        row![dot, label(&inst.status, 12.0, theme::T3)]
            .spacing(6)
            .align_y(iced::Center),
    ]
    .spacing(2);

    let content = row![tile, lines].spacing(10).align_y(iced::Center);

    button(content)
        .width(Length::Fill)
        .padding(8)
        .on_press(Message::Select(index))
        .style(move |_theme, status| {
            let background = match status {
                button::Status::Hovered if index == selected => theme::HI,
                button::Status::Hovered => theme::RAISE,
                _ if index == selected => theme::RAISE,
                _ => Color::TRANSPARENT,
            };

            button::Style {
                background: Some(Background::Color(background)),
                text_color: theme::T1,
                border: Border {
                    radius: 10.0.into(),
                    ..Default::default()
                },
                ..Default::default()
            }
        })
        .into()
}

fn discord_button<'a>() -> Element<'a, Message> {
    let content = container(label("เข้า Discord ของสตูดิโอ", 14.0, theme::T1))
        .width(Length::Fill)
        .align_x(iced::Center);

    button(content)
        .width(Length::Fill)
        .padding(10)
        .on_press(Message::Noop)
        .style(|_theme, status| {
            let background = match status {
                button::Status::Hovered => theme::HI,
                _ => theme::RAISE,
            };

            button::Style {
                background: Some(Background::Color(background)),
                text_color: theme::T1,
                border: Border {
                    radius: 10.0.into(),
                    ..Default::default()
                },
                ..Default::default()
            }
        })
        .into()
}
