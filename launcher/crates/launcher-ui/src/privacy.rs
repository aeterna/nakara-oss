// SPDX-License-Identifier: MIT

use crate::dusk::glass::{self, FAINT, INK, LINK, MUTED};
use crate::dusk::icons::{icon, Icon};
use crate::text::label;
use crate::theme;
use crate::Message;
use iced::widget::{button, column, container, opaque, row, Space};
use iced::{Background, Border, Color, Element, Length, Padding};

const BODY: Color = theme::rgb(0xb8c8c3);

const ROWS: [(Color, &str, &str); 4] = [
    (
        theme::DOT_ON,
        "ไม่ส่งข้อมูลการเล่นหรือสถิติเครื่อง",
        "launcher ไม่มี telemetry ไม่เก็บสถิติการใช้งาน และไม่ส่งรายงานเมื่อโปรแกรมพัง",
    ),
    (
        theme::GOLD,
        "ดึงข่าวและเวลาเปิดจากเว็บของเมือง",
        "เว็บของเมืองเห็น IP และชื่อโปรแกรมของคุณ เหมือนตอนเปิดเว็บทั่วไป",
    ),
    (
        theme::GOLD,
        "เช็กรุ่นใหม่จาก GitHub",
        "GitHub เห็น IP ของคุณ ไฟล์อัปเดตทุกไฟล์มีลายเซ็นให้ตรวจ",
    ),
    (
        FAINT,
        "ตรวจเครื่อง เฉพาะตอนคุณกดเอง",
        "ปุ่มตรวจเครื่องเปิด Rongroi Connect ซึ่งถามความยินยอมอีกครั้งก่อนส่งผลให้ทีมงาน",
    ),
];

pub fn view<'a>() -> Element<'a, Message> {
    let dialog = container(
        column![header(), rows(), footer()]
            .spacing(20)
            .width(Length::Fill),
    )
    .width(600)
    .padding(28)
    .style(|_theme| container::Style {
        background: Some(Background::Color(rgba(0x0c181c, 0.96))),
        border: Border {
            color: rgba(0xdcf0ea, 0.12),
            width: 1.0,
            radius: 20.0.into(),
        },
        ..container::Style::default()
    });

    opaque(
        container(dialog)
            .width(Length::Fill)
            .height(Length::Fill)
            .align_x(iced::Center)
            .align_y(iced::Center)
            .style(|_theme| container::Style {
                background: Some(Background::Color(rgba(0x03080b, 0.72))),
                ..container::Style::default()
            }),
    )
    .into()
}

fn header<'a>() -> Element<'a, Message> {
    let tile = container(icon(Icon::Shield, 22.0, LINK))
        .width(44)
        .height(44)
        .align_x(iced::Center)
        .align_y(iced::Center)
        .style(|_theme| container::Style {
            background: Some(Background::Color(rgba(0x119a7a, 0.18))),
            border: Border {
                radius: 12.0.into(),
                ..Border::default()
            },
            ..container::Style::default()
        });

    let lines = column![
        label("launcher ส่งอะไรออกไปบ้าง", 22.0, INK),
        label("อ่านครั้งเดียวตอนเปิดครั้งแรก", 13.0, MUTED),
    ]
    .spacing(2);

    row![tile, lines].spacing(14).align_y(iced::Center).into()
}

fn rows<'a>() -> Element<'a, Message> {
    let mut list = column![].spacing(8).width(Length::Fill);

    for &(dot, title, body) in &ROWS {
        list = list.push(row_item(dot, title, body));
    }

    list.into()
}

fn row_item<'a>(dot: Color, title: &'a str, body: &'a str) -> Element<'a, Message> {
    let mark = container(
        container(Space::new())
            .width(10)
            .height(10)
            .style(theme::panel(dot, 5.0)),
    )
    .padding(Padding {
        top: 6.0,
        right: 0.0,
        bottom: 0.0,
        left: 0.0,
    });

    let lines = column![label(title, 15.0, INK), label(body, 13.0, BODY),]
        .spacing(4)
        .width(Length::Fill);

    container(
        row![mark, lines]
            .spacing(14)
            .width(Length::Fill)
            .align_y(iced::Alignment::Start),
    )
    .width(Length::Fill)
    .padding([14, 16])
    .style(|_theme| container::Style {
        background: Some(Background::Color(rgba(0xdcf0ea, 0.05))),
        border: Border {
            color: rgba(0xdcf0ea, 0.07),
            width: 1.0,
            radius: 14.0.into(),
        },
        ..container::Style::default()
    })
    .into()
}

fn footer<'a>() -> Element<'a, Message> {
    let ok = button(
        container(label("เข้าใจแล้ว", 16.0, Color::WHITE))
            .height(Length::Fill)
            .align_y(iced::Center),
    )
    .height(46)
    .padding([0, 28])
    .on_press(Message::PrivacyOk)
    .style(glass::solid(crate::profile::accent(), 12.0));

    row![Space::new().width(Length::Fill), ok]
        .width(Length::Fill)
        .align_y(iced::Center)
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
