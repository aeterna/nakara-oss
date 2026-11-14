// SPDX-License-Identifier: MIT

use crate::model::Instance;
use crate::text::{label, t};
use crate::theme;
use crate::Message;
use iced::widget::{button, column, container, row, text_input, Space};
use iced::{Background, Border, Color, Element, Length};

pub fn view<'a>(inst: &'a Instance, notice: Option<&str>) -> Element<'a, Message> {
    let skin = theme::rgb(inst.skin);

    let mut chips = row![chip(&inst.chips[0], theme::T1)]
        .spacing(8)
        .align_y(iced::Center);

    if !inst.chips[1].is_empty() {
        chips = chips.push(chip(&inst.chips[1], theme::T2));
    }

    let title = row![
        container(label(&inst.initials, 20.0, skin))
            .width(56)
            .height(56)
            .align_x(iced::Center)
            .align_y(iced::Center)
            .style(theme::panel(theme::HI, 14.0)),
        label(&inst.name, 52.0, skin),
    ]
    .spacing(16)
    .align_y(iced::Center);

    let sub = container(label(notice.unwrap_or(&inst.sub), 15.0, theme::T2))
        .width(Length::Fill)
        .max_width(560.0)
        .padding(iced::Padding {
            top: 12.0,
            right: 0.0,
            bottom: 0.0,
            left: 0.0,
        });

    let mut page = column![
        container(chips).padding(iced::Padding {
            top: 0.0,
            right: 0.0,
            bottom: 12.0,
            left: 0.0,
        }),
        title,
        sub,
    ]
    .spacing(0)
    .width(Length::Fill)
    .padding(iced::Padding {
        top: 20.0,
        right: 0.0,
        bottom: 0.0,
        left: 0.0,
    });

    if inst.show_hours {
        page = page.push(hours(inst));
    }

    page = page.push(actions(inst));

    page.into()
}

fn chip<'a>(text: &str, color: Color) -> Element<'a, Message> {
    container(label(text, 12.0, color))
        .padding([3, 10])
        .style(theme::panel(theme::RAISE, 8.0))
        .into()
}

fn hours<'a>(inst: &'a Instance) -> Element<'a, Message> {
    let mut left = Border::default();
    left.radius.top_left = 4.0;
    left.radius.bottom_left = 4.0;

    let mut right = Border::default();
    right.radius.top_right = 4.0;
    right.radius.bottom_right = 4.0;

    let accent = crate::profile::accent();

    let open = Color { a: 0.7, ..accent };

    let bar = row![
        segment(299.0, 8.0, theme::RAISE, left),
        segment(2.0, 16.0, theme::GOLD, Border::default()),
        segment(69.0, 8.0, theme::RAISE, Border::default()),
        segment(150.0, 8.0, open, right),
    ]
    .spacing(0)
    .height(16)
    .align_y(iced::Center);

    let ticks = row![
        label("00", 11.0, theme::T3),
        Space::new().width(Length::Fill),
        label("06", 11.0, theme::T3),
        Space::new().width(Length::Fill),
        label("12", 11.0, theme::T3),
        Space::new().width(Length::Fill),
        label("17", 11.0, theme::T3),
        Space::new().width(Length::Fill),
        label("24", 11.0, theme::T3),
    ]
    .width(Length::Fixed(520.0))
    .align_y(iced::Center);

    let window = inst.hours.as_deref().unwrap_or("");

    let block = column![
        row![
            label(&inst.status, 13.0, theme::T1),
            label(&format!("· เปิด {window}"), 13.0, theme::T2),
        ]
        .spacing(8)
        .align_y(iced::Center),
        container(bar).padding(iced::Padding {
            top: 8.0,
            right: 0.0,
            bottom: 0.0,
            left: 0.0,
        }),
        container(ticks).padding(iced::Padding {
            top: 6.0,
            right: 0.0,
            bottom: 0.0,
            left: 0.0,
        }),
    ]
    .spacing(0)
    .width(Length::Fixed(520.0));

    container(block)
        .width(Length::Fixed(520.0))
        .padding(iced::Padding {
            top: 16.0,
            right: 0.0,
            bottom: 0.0,
            left: 0.0,
        })
        .into()
}

fn segment<'a>(width: f32, height: f32, color: Color, border: Border) -> Element<'a, Message> {
    container(
        Space::new()
            .width(Length::Fixed(width))
            .height(Length::Fixed(height)),
    )
    .width(Length::Fixed(width))
    .height(Length::Fixed(height))
    .style(move |_theme| container::Style {
        background: Some(Background::Color(color)),
        border,
        ..container::Style::default()
    })
    .into()
}

fn actions<'a>(inst: &Instance) -> Element<'a, Message> {
    let mut bar = row![play_button(inst), picker(inst)];

    if crate::profile::connect_on() {
        bar = bar.push(chrome_button("ตรวจเครื่อง"));
    }

    bar = bar.push(chrome_button("โฟลเดอร์ภาพ"));
    bar = bar.push(Space::new().width(Length::Fill));
    bar = bar
        .spacing(12)
        .width(Length::Fill)
        .height(56)
        .align_y(iced::Center);

    if inst.show_invite {
        bar = bar.push(invite());
    }

    container(bar)
        .width(Length::Fill)
        .padding(iced::Padding {
            top: 24.0,
            right: 0.0,
            bottom: 0.0,
            left: 0.0,
        })
        .into()
}

fn play_button<'a>(inst: &Instance) -> Element<'a, Message> {
    let enabled = inst.play_enabled;
    let text_color = if enabled { Color::WHITE } else { theme::T3 };
    let accent = crate::profile::accent();

    let content = container(label(&inst.play_label, 18.0, text_color))
        .width(Length::Fill)
        .height(Length::Fill)
        .align_x(iced::Center)
        .align_y(iced::Center);

    let mut play = button(content)
        .width(200)
        .height(56)
        .padding(0)
        .style(move |_theme, status| {
            let background = if enabled {
                match status {
                    button::Status::Hovered => Color {
                        r: accent.r * 0.88,
                        g: accent.g * 0.88,
                        b: accent.b * 0.88,
                        a: 1.0,
                    },
                    _ => accent,
                }
            } else {
                theme::RAISE
            };

            button::Style {
                background: Some(Background::Color(background)),
                text_color,
                border: Border {
                    radius: 12.0.into(),
                    ..Border::default()
                },
                ..Default::default()
            }
        });

    if enabled {
        play = play.on_press(Message::Play);
    }

    play.into()
}

fn picker<'a>(inst: &Instance) -> Element<'a, Message> {
    let labels = column![
        label(&inst.pick_label, 11.0, theme::T3),
        label(&inst.pick_value, 14.0, theme::T1),
    ]
    .spacing(0);

    container(
        row![
            labels,
            Space::new().width(Length::Fill),
            label("▾", 14.0, theme::T2),
        ]
        .width(Length::Fill)
        .align_y(iced::Center),
    )
    .width(220)
    .height(56)
    .padding([8, 14])
    .align_y(iced::Center)
    .style(bordered(12.0))
    .into()
}

fn chrome_button<'a>(text: &str) -> Element<'a, Message> {
    button(label(text, 14.0, theme::T2))
        .height(56)
        .padding([0, 16])
        .on_press(Message::Noop)
        .style(|_theme, _status| button::Style {
            background: Some(Background::Color(theme::SURF)),
            text_color: theme::T2,
            border: Border {
                color: theme::LINE,
                width: 1.0,
                radius: 12.0.into(),
            },
            ..Default::default()
        })
        .into()
}

fn invite<'a>() -> Element<'a, Message> {
    let code = text_input(&t("วางรหัสเชิญเข้าเมือง"), "")
        .size(14)
        .padding(0)
        .width(Length::Fill)
        .style(input_style);

    let use_code = button(label("ใช้รหัส", 14.0, theme::T2))
        .height(44)
        .padding([0, 14])
        .on_press(Message::OpenInvite)
        .style(|_theme, _status| button::Style {
            background: Some(Background::Color(theme::RAISE)),
            text_color: theme::T2,
            border: Border {
                radius: 8.0.into(),
                ..Border::default()
            },
            ..Default::default()
        });

    container(
        row![code, use_code]
            .spacing(6)
            .width(Length::Fill)
            .height(Length::Fill)
            .align_y(iced::Center),
    )
    .width(320)
    .height(56)
    .padding([6, 6])
    .style(bordered(12.0))
    .into()
}

fn bordered(radius: f32) -> impl Fn(&iced::Theme) -> container::Style {
    move |_theme| container::Style {
        background: Some(Background::Color(theme::SURF)),
        border: Border {
            color: theme::LINE,
            width: 1.0,
            radius: radius.into(),
        },
        ..container::Style::default()
    }
}

fn input_style(_theme: &iced::Theme, _status: text_input::Status) -> text_input::Style {
    let accent = crate::profile::accent();

    text_input::Style {
        background: Background::Color(Color::TRANSPARENT),
        border: Border::default(),
        icon: theme::T2,
        placeholder: theme::T3,
        value: theme::T1,
        selection: accent,
    }
}
