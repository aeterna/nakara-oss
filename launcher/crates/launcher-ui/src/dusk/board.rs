// SPDX-License-Identifier: MIT

use crate::dusk::glass::{self, FAINT, INK, INK2, MUTED};
use crate::sample::Instance;
use crate::text::label;
use crate::theme;
use crate::Message;
use iced::widget::{button, column, container, row, Space};
use iced::{
    gradient, Background, Border, Color, Element, Gradient, Length, Padding, Radians,
};

pub fn view<'a>(inst: &'a Instance) -> Element<'a, Message> {
    let board = container(
        column![tabs(), body(inst)]
            .spacing(8)
            .width(Length::Fill)
            .height(Length::Fill),
    )
    .width(Length::Fill)
    .height(250)
    .padding(8)
    .style(glass::glass(18.0));

    column![board, footer(inst)]
        .spacing(10)
        .width(Length::Fill)
        .into()
}

fn tabs<'a>() -> Element<'a, Message> {
    row![
        tab("ภาพรวม", true),
        tab("ข่าว 3", false),
        tab("กิจกรรม", false),
        tab("ภาพ 12", false),
        tab("กติกา", false),
    ]
    .spacing(2)
    .into()
}

fn tab<'a>(title: &str, active: bool) -> Element<'a, Message> {
    let text_color = if active { INK } else { INK2 };

    button(label(title, 14.0, text_color))
        .padding([8, 14])
        .on_press(Message::Noop)
        .style(glass::pill(active, 10.0))
        .into()
}

fn body<'a>(inst: &'a Instance) -> Element<'a, Message> {
    row![gallery(), patch(inst)]
        .spacing(12)
        .padding([0, 8])
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}

fn gallery<'a>() -> Element<'a, Message> {
    let header = row![
        label("ภาพจากเมือง", 15.0, INK),
        Space::new().width(Length::Fill),
        label("ดูทั้งหมด", 12.0, MUTED),
    ]
    .width(Length::Fill)
    .align_y(iced::Center);

    let images = row![
        tile(
            &[
                theme::rgb(0x12313a),
                theme::rgb(0x1f5a55),
                theme::rgb(0xc48a48),
            ],
            Length::FillPortion(2),
        ),
        column![
            tile(
                &[theme::rgb(0x0d1e2a), theme::rgb(0x2c3b4e)],
                Length::Fill,
            ),
            tile(
                &[theme::rgb(0x1c2a22), theme::rgb(0x4d6a46)],
                Length::Fill,
            ),
        ]
        .spacing(8)
        .width(Length::FillPortion(1))
        .height(Length::Fill),
    ]
    .spacing(8)
    .width(Length::Fill)
    .height(Length::Fill);

    column![header, images]
        .spacing(10)
        .width(Length::FillPortion(3))
        .height(Length::Fill)
        .into()
}

fn tile<'a>(stops: &[Color], width: Length) -> Element<'a, Message> {
    let mut linear = gradient::Linear::new(Radians(0.6));

    for (index, color) in stops.iter().enumerate() {
        let offset = if stops.len() <= 1 {
            0.0
        } else {
            index as f32 / (stops.len() - 1) as f32
        };

        linear = linear.add_stop(offset, *color);
    }

    let background = Background::Gradient(Gradient::Linear(linear));

    container(Space::new())
        .width(width)
        .height(Length::Fill)
        .style(move |_theme| container::Style {
            background: Some(background.clone()),
            border: Border {
                radius: 12.0.into(),
                ..Border::default()
            },
            ..container::Style::default()
        })
        .into()
}

fn patch<'a>(inst: &'a Instance) -> Element<'a, Message> {
    let header = row![
        label("บันทึกแพตช์", 15.0, INK),
        Space::new().width(Length::Fill),
        label("ทั้งหมด", 12.0, MUTED),
    ]
    .width(Length::Fill)
    .align_y(iced::Center);

    let mut list = column![header, label(inst.patch_title, 12.0, MUTED)]
        .spacing(4)
        .width(Length::Fill);

    if inst.patch.is_empty() {
        list = list.push(label("แพตช์แรกจะขึ้นที่นี่", 13.0, MUTED));
    } else {
        for &(group, items) in inst.patch {
            list = list.push(
                container(label(group, 12.0, MUTED)).padding(Padding {
                    top: 6.0,
                    right: 0.0,
                    bottom: 0.0,
                    left: 0.0,
                }),
            );

            for &item in items {
                list = list.push(label(&format!("• {item}"), 13.0, theme::rgb(0xd7e3df)));
            }
        }
    }

    container(list)
        .width(Length::FillPortion(2))
        .height(Length::Fill)
        .padding([12, 16])
        .style(glass::well(14.0))
        .into()
}

fn footer<'a>(inst: &'a Instance) -> Element<'a, Message> {
    let contact = format!("ดูแลโดย {} · ติดต่อ {}", inst.operator, inst.contact);
    let notice = format!(
        "{} IS NOT APPROVED, SPONSORED, OR ENDORSED BY ROCKSTAR GAMES.",
        inst.name.to_uppercase()
    );

    row![
        label(&contact, 11.0, FAINT),
        Space::new().width(Length::Fill),
        label(&notice, 11.0, FAINT),
    ]
    .spacing(16)
    .padding([0, 4])
    .width(Length::Fill)
    .into()
}
