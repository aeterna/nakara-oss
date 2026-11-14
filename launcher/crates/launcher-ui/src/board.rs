// SPDX-License-Identifier: MIT

use crate::sample::Instance;
use crate::text::label;
use crate::theme;
use crate::Message;
use iced::widget::{button, column, container, row, Space};
use iced::{Background, Border, Color, Element, Length, Padding};

pub fn view<'a>(inst: &'a Instance) -> Element<'a, Message> {
    let board = container(column![tabs(), body(inst)].spacing(12).width(Length::Fill))
        .width(Length::Fill)
        .padding(Padding {
            top: 8.0,
            right: 8.0,
            bottom: 16.0,
            left: 8.0,
        })
        .style(theme::panel(theme::SURF, 16.0));

    let board = container(board).width(Length::Fill).padding(Padding {
        top: 8.0,
        right: 0.0,
        bottom: 0.0,
        left: 0.0,
    });

    column![board, footer(inst)]
        .spacing(12)
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
    let text_color = if active { theme::T1 } else { theme::T2 };

    button(label(title, 14.0, text_color))
        .padding([8, 14])
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

fn body<'a>(inst: &'a Instance) -> Element<'a, Message> {
    let news_header = row![
        label("ข่าวล่าสุด", 15.0, theme::T1),
        Space::new().width(Length::Fill),
        label("ดูทั้งหมด", 12.0, theme::T3),
    ]
    .align_y(iced::Center);

    let news_cards: Element<'a, Message> = if inst.news.is_empty() {
        container(label("ยังไม่มีข่าว", 13.0, theme::T3))
            .padding(Padding {
                top: 12.0,
                right: 0.0,
                bottom: 0.0,
                left: 0.0,
            })
            .into()
    } else {
        let mut cards = row![].spacing(12).width(Length::Fill);

        for &(title, date) in inst.news {
            cards = cards.push(news_card(title, date));
        }

        cards.into()
    };

    let news = column![news_header, news_cards]
        .spacing(12)
        .width(Length::FillPortion(3));

    row![news, patch(inst)]
        .spacing(16)
        .padding([0, 8])
        .width(Length::Fill)
        .into()
}

fn news_card<'a>(title: &str, date: &str) -> Element<'a, Message> {
    let image = container(Space::new())
        .width(Length::Fill)
        .height(120)
        .style(theme::panel(theme::HI, 12.0));

    let info =
        container(column![label(title, 14.0, theme::T1), label(date, 11.0, theme::T3),].spacing(4))
            .padding([10, 12]);

    container(column![image, info].width(Length::Fill))
        .width(Length::Fill)
        .style(theme::panel(theme::RAISE, 12.0))
        .into()
}

fn patch<'a>(inst: &'a Instance) -> Element<'a, Message> {
    let header = row![
        label("บันทึกแพตช์", 15.0, theme::T1),
        Space::new().width(Length::Fill),
        label("ทั้งหมด", 11.0, theme::T3),
    ]
    .align_y(iced::Center);

    let mut list = column![header, label(inst.patch_title, 11.0, theme::T3)]
        .spacing(4)
        .width(Length::Fill);

    if inst.patch.is_empty() {
        list = list.push(
            container(label("แพตช์แรกจะขึ้นที่นี่", 13.0, theme::T3)).padding(Padding {
                top: 12.0,
                right: 0.0,
                bottom: 0.0,
                left: 0.0,
            }),
        );
    } else {
        for &(group, items) in inst.patch {
            list = list.push(container(label(group, 12.0, theme::T3)).padding(Padding {
                top: 12.0,
                right: 0.0,
                bottom: 0.0,
                left: 0.0,
            }));

            for &item in items {
                list = list.push(label(&format!("• {item}"), 13.0, theme::T2));
            }
        }
    }

    container(list)
        .width(Length::FillPortion(2))
        .padding([14, 16])
        .style(theme::panel(theme::RAISE, 12.0))
        .into()
}

fn footer<'a>(inst: &'a Instance) -> Element<'a, Message> {
    let contact = format!("ดูแลโดย {} · ติดต่อ {}", inst.operator, inst.contact);
    let notice = format!(
        "{} IS NOT APPROVED, SPONSORED, OR ENDORSED BY ROCKSTAR GAMES.",
        inst.name
    );

    container(
        column![
            label(&contact, 11.0, theme::T3),
            label(&notice, 11.0, theme::T3),
        ]
        .spacing(2),
    )
    .width(Length::Fill)
    .padding([0, 8])
    .into()
}
