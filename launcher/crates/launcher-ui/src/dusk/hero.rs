// SPDX-License-Identifier: MIT

use crate::dusk::glass::{self, INK, INK2, MUTED};
use crate::dusk::icons::{icon, Icon};
use crate::model::Instance;
use crate::text::{label, t};
use crate::theme;
use crate::Message;
use iced::widget::{button, column, container, row, text_input, Space};
use iced::{Background, Border, Color, Element, Length, Padding};

pub fn view<'a>(inst: &'a Instance) -> Element<'a, Message> {
    let mut chips = row![container(label(&inst.chips[0], 12.0, INK))
        .padding([4, 10])
        .style(glass::glass(8.0))]
    .spacing(8)
    .align_y(iced::Center);

    if !inst.chips[1].is_empty() {
        chips = chips.push(container(label(&inst.chips[1], 12.0, INK2)).padding([4, 10]));
    }

    let title = row![title_tile(inst), label(&inst.name, 68.0, Color::WHITE)]
        .spacing(18)
        .align_y(iced::Center);

    let dot = if inst.status_on {
        theme::DOT_ON
    } else {
        theme::GOLD
    };

    let status = row![
        container(Space::new())
            .width(8)
            .height(8)
            .style(theme::panel(dot, 4.0)),
        label(&inst.sub, 16.0, theme::rgb(0xd7e3df)),
    ]
    .spacing(10)
    .align_y(iced::Center);

    let mut actions_row = row![play_group(inst), picker(inst)];

    if crate::profile::connect_on() {
        actions_row = actions_row.push(icon_button(Icon::Shield));
    }

    actions_row = actions_row.push(icon_button(Icon::Folder));

    let actions = container(actions_row.spacing(12).align_y(iced::Center)).padding(Padding {
        top: 18.0,
        right: 0.0,
        bottom: 0.0,
        left: 0.0,
    });

    let mut page = column![chips, title, status, actions]
        .spacing(14)
        .width(Length::Fill);

    if inst.show_invite {
        page = page.push(invite());
    }

    container(page)
        .width(Length::Fill)
        .max_width(760.0)
        .padding(Padding {
            top: 52.0,
            right: 0.0,
            bottom: 0.0,
            left: 0.0,
        })
        .into()
}

fn title_tile<'a>(inst: &Instance) -> Element<'a, Message> {
    let skin = theme::rgb(inst.skin);

    container(label(&inst.initials, 22.0, skin))
        .width(64)
        .height(64)
        .align_x(iced::Center)
        .align_y(iced::Center)
        .style(move |_theme| container::Style {
            background: Some(Background::Color(theme::rgb(0x0b0a07))),
            border: Border {
                color: Color { a: 0.45, ..skin },
                width: 1.0,
                radius: 16.0.into(),
            },
            ..container::Style::default()
        })
        .into()
}

fn play_group<'a>(inst: &Instance) -> Element<'a, Message> {
    let background = if inst.play_enabled {
        crate::profile::accent()
    } else {
        Color {
            a: 0.10,
            ..theme::rgb(0xdcf0ea)
        }
    };

    let content = container(
        row![
            icon(Icon::Play, 18.0, Color::WHITE),
            label(&inst.play_label, 19.0, Color::WHITE),
        ]
        .spacing(10)
        .align_y(iced::Center),
    )
    .height(Length::Fill)
    .align_y(iced::Center);

    let mut play = button(content)
        .height(58)
        .padding([0, 28])
        .style(bare_button);

    if inst.play_enabled {
        play = play.on_press(Message::Noop);
    }

    let divider = container(Space::new())
        .width(1)
        .height(Length::Fill)
        .style(|_theme| container::Style {
            background: Some(Background::Color(Color {
                a: 0.18,
                ..Color::WHITE
            })),
            ..container::Style::default()
        });

    let radius = iced::border::Radius {
        top_right: 14.0,
        bottom_right: 14.0,
        ..Default::default()
    };

    let more = button(
        container(icon(Icon::More, 18.0, Color::WHITE))
            .width(Length::Fill)
            .height(Length::Fill)
            .align_x(iced::Center)
            .align_y(iced::Center),
    )
    .width(52)
    .height(58)
    .padding(0)
    .on_press(Message::Noop)
    .style(move |_theme, _status| button::Style {
        background: Some(Background::Color(Color {
            a: 0.14,
            ..Color::BLACK
        })),
        text_color: Color::WHITE,
        border: Border {
            radius,
            ..Border::default()
        },
        ..button::Style::default()
    });

    container(row![play, divider, more].height(58).align_y(iced::Center))
        .height(58)
        .style(move |_theme| container::Style {
            background: Some(Background::Color(background)),
            border: Border {
                radius: 14.0.into(),
                ..Border::default()
            },
            ..container::Style::default()
        })
        .into()
}

fn picker<'a>(inst: &'a Instance) -> Element<'a, Message> {
    let labels = column![
        label(&inst.pick_label, 11.0, MUTED),
        label(&inst.pick_value, 15.0, INK),
    ]
    .spacing(0)
    .width(Length::Fill);

    let content = row![labels, icon(Icon::Chevron, 16.0, INK)]
        .spacing(10)
        .align_y(iced::Center)
        .width(Length::Fill);

    let picker = button(content)
        .width(Length::Fill)
        .height(Length::Fill)
        .padding([0, 14])
        .on_press(Message::Noop)
        .style(bare_button);

    container(picker)
        .width(200)
        .height(58)
        .style(glass::glass(14.0))
        .into()
}

fn icon_button<'a>(which: Icon) -> Element<'a, Message> {
    let square = button(
        container(icon(which, 20.0, INK2))
            .width(Length::Fill)
            .height(Length::Fill)
            .align_x(iced::Center)
            .align_y(iced::Center),
    )
    .width(Length::Fill)
    .height(Length::Fill)
    .padding(0)
    .on_press(Message::Noop)
    .style(bare_button);

    container(square)
        .width(58)
        .height(58)
        .style(glass::glass(14.0))
        .into()
}

fn invite<'a>() -> Element<'a, Message> {
    let code = text_input(&t("วางรหัสเชิญเข้าเมือง"), "")
        .size(14)
        .padding(0)
        .width(Length::Fill)
        .style(input_style);

    let use_code = button(
        container(label("ใช้รหัส", 14.0, INK))
            .height(Length::Fill)
            .align_y(iced::Center),
    )
    .height(42)
    .padding([0, 16])
    .on_press(Message::Noop)
    .style(glass::solid(
        Color {
            a: 0.10,
            ..theme::rgb(0xdcf0ea)
        },
        10.0,
    ));

    container(
        row![icon(Icon::AddUser, 18.0, MUTED), code, use_code]
            .spacing(10)
            .align_y(iced::Center)
            .height(Length::Fill),
    )
    .width(412)
    .height(54)
    .padding(Padding {
        top: 0.0,
        right: 6.0,
        bottom: 0.0,
        left: 14.0,
    })
    .style(glass::glass(14.0))
    .into()
}

fn bare_button(_theme: &iced::Theme, _status: button::Status) -> button::Style {
    button::Style {
        background: Some(Background::Color(Color::TRANSPARENT)),
        text_color: INK,
        border: Border::default(),
        ..button::Style::default()
    }
}

fn input_style(_theme: &iced::Theme, _status: text_input::Status) -> text_input::Style {
    text_input::Style {
        background: Background::Color(Color::TRANSPARENT),
        border: Border {
            width: 0.0,
            ..Border::default()
        },
        icon: INK,
        placeholder: MUTED,
        value: INK,
        selection: Color {
            a: 0.35,
            ..theme::rgb(0x7fd8c0)
        },
    }
}
