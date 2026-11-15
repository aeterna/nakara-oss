// SPDX-License-Identifier: MIT

use crate::dusk::glass::{self, INK, INK2, LINK, MUTED};
use crate::dusk::icons::{icon, Icon};
use crate::text::{label, t};
use crate::theme;
use crate::Message;
use iced::widget::{button, column, container, opaque, row, text_input, Space};
use iced::{Background, Border, Color, Element, Length};
use launcher_connect::{CodeError, ConnectError, Outcome};
use std::path::{Path, PathBuf};
use std::time::Duration;

pub const MISSING: &str = "ไม่พบ Rongroi Connect ในโฟลเดอร์ของ launcher";
pub const RUN_TIMEOUT: Duration = Duration::from_secs(30 * 60);

const BODY: Color = theme::rgb(0xb8c8c3);

pub fn connect_exe_in(dir: &Path) -> PathBuf {
    dir.join("rongroi-connect").join("rongroi-connect.exe")
}

pub fn connect_exe() -> Option<PathBuf> {
    let exe = std::env::current_exe().ok()?;
    let dir = exe.parent()?;
    let path = connect_exe_in(dir);
    if path.is_absolute() && path.is_file() {
        Some(path)
    } else {
        None
    }
}

pub fn outcome_text(o: &Outcome) -> String {
    match o {
        Outcome::ReportAccepted => "ส่งผลตรวจให้ทีมงานแล้ว".to_string(),
        Outcome::DeclineAccepted => "แจ้งทีมงานแล้วว่าคุณไม่ยินยอม".to_string(),
        Outcome::ClosedByPlayer => "ปิด Connect ก่อนส่ง ไม่มีอะไรถูกส่ง".to_string(),
        Outcome::Refused => "รหัสนี้ใช้ไม่ได้ ขอรหัสใหม่จากทีมงาน".to_string(),
        Outcome::RecordRefused | Outcome::UploadFailed => {
            "ส่งผลตรวจไม่สำเร็จ ขอรหัสใหม่จากทีมงาน".to_string()
        }
        Outcome::Unknown(n) => {
            format!("Connect จบด้วยรหัส {n} ลองอีกครั้ง หรือติดต่อทีมงาน")
        }
        Outcome::Internal | Outcome::Sidecar | Outcome::Signal => {
            "Connect ทำงานไม่สำเร็จ ลองอีกครั้ง หรือติดต่อทีมงาน".to_string()
        }
    }
}

pub fn error_text(e: &ConnectError) -> String {
    match e {
        ConnectError::Code(CodeError::Prefix) => "รหัสไม่ถูกต้อง ต้องขึ้นต้นด้วย rr1.".to_string(),
        ConnectError::Code(CodeError::TooLong) => "รหัสยาวเกินไป".to_string(),
        ConnectError::Code(CodeError::NotPrintable) => "รหัสมีช่องว่างหรือตัวอักษรที่ใช้ไม่ได้".to_string(),
        ConnectError::Unsupported => "Rongroi Connect ใช้ได้บน Windows เท่านั้น".to_string(),
        ConnectError::Timeout => "Connect ไม่ตอบในเวลาที่กำหนด".to_string(),
        ConnectError::Io(_)
        | ConnectError::NotAbsolute
        | ConnectError::PipeClientMismatch { .. } => "เปิด Rongroi Connect ไม่ได้".to_string(),
    }
}

pub fn view<'a>(code: &str, busy: bool, status: Option<&str>) -> Element<'a, Message> {
    let input = text_input(&t("rr1.…"), code)
        .on_input(Message::ConnectCode)
        .size(14)
        .padding([12, 14])
        .width(Length::Fill)
        .style(input_style);

    let mut body = column![header(), input].spacing(20).width(Length::Fill);

    if let Some(status) = status {
        body = body.push(label(status, 13.0, BODY));
    }

    body = body.push(footer(code, busy));

    let dialog = container(body)
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
        label("ตรวจเครื่องด้วย Rongroi Connect", 22.0, INK),
        label(
            "วางรหัสที่ทีมงานให้ แล้วกดเปิด หน้าต่าง Connect จะถามความยินยอมของคุณเอง",
            13.0,
            MUTED,
        ),
    ]
    .spacing(2);

    row![tile, lines].spacing(14).align_y(iced::Center).into()
}

fn footer<'a>(code: &str, busy: bool) -> Element<'a, Message> {
    let close_color = if busy { MUTED } else { INK2 };
    let mut close = button(
        container(label("ปิด", 15.0, close_color))
            .height(Length::Fill)
            .align_y(iced::Center),
    )
    .height(46)
    .padding([0, 22])
    .style(glass::pill(false, 12.0));

    if !busy {
        close = close.on_press(Message::ConnectClose);
    }

    let can_start = !busy && !code.trim().is_empty();
    let start_bg = if can_start {
        crate::profile::accent()
    } else {
        rgba(0xdcf0ea, 0.10)
    };
    let start_fg = if can_start { Color::WHITE } else { MUTED };

    let mut start = button(
        container(label("เปิด Rongroi Connect", 16.0, start_fg))
            .height(Length::Fill)
            .align_y(iced::Center),
    )
    .height(46)
    .padding([0, 28])
    .style(glass::solid(start_bg, 12.0));

    if can_start {
        start = start.on_press(Message::ConnectStart);
    }

    row![Space::new().width(Length::Fill), close, start]
        .spacing(10)
        .width(Length::Fill)
        .align_y(iced::Center)
        .into()
}

fn input_style(_theme: &iced::Theme, _status: text_input::Status) -> text_input::Style {
    text_input::Style {
        background: Background::Color(rgba(0xdcf0ea, 0.05)),
        border: Border {
            color: rgba(0xdcf0ea, 0.12),
            width: 1.0,
            radius: 12.0.into(),
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

fn rgba(hex: u32, a: f32) -> Color {
    Color {
        r: ((hex >> 16) & 0xff) as f32 / 255.0,
        g: ((hex >> 8) & 0xff) as f32 / 255.0,
        b: (hex & 0xff) as f32 / 255.0,
        a,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io;

    #[test]
    fn connect_exe_in_joins_rongroi_connect_folder_and_binary() {
        let dir = Path::new("/opt/aeterna-launcher");
        let path = connect_exe_in(dir);
        assert_eq!(
            path,
            dir.join("rongroi-connect").join("rongroi-connect.exe")
        );
        assert_eq!(
            path.file_name().and_then(|s| s.to_str()),
            Some("rongroi-connect.exe")
        );
        assert_eq!(
            path.parent()
                .and_then(|p| p.file_name())
                .and_then(|s| s.to_str()),
            Some("rongroi-connect")
        );
    }

    #[test]
    fn outcome_text_maps_every_variant() {
        assert_eq!(outcome_text(&Outcome::ReportAccepted), "ส่งผลตรวจให้ทีมงานแล้ว");
        assert_eq!(
            outcome_text(&Outcome::DeclineAccepted),
            "แจ้งทีมงานแล้วว่าคุณไม่ยินยอม"
        );
        assert_eq!(
            outcome_text(&Outcome::ClosedByPlayer),
            "ปิด Connect ก่อนส่ง ไม่มีอะไรถูกส่ง"
        );
        assert_eq!(
            outcome_text(&Outcome::Refused),
            "รหัสนี้ใช้ไม่ได้ ขอรหัสใหม่จากทีมงาน"
        );
        assert_eq!(
            outcome_text(&Outcome::Unknown(77)),
            "Connect จบด้วยรหัส 77 ลองอีกครั้ง หรือติดต่อทีมงาน"
        );
        for other in [Outcome::RecordRefused, Outcome::UploadFailed] {
            assert_eq!(
                outcome_text(&other),
                "ส่งผลตรวจไม่สำเร็จ ขอรหัสใหม่จากทีมงาน",
                "{other:?}"
            );
        }
        for other in [Outcome::Internal, Outcome::Sidecar, Outcome::Signal] {
            assert_eq!(
                outcome_text(&other),
                "Connect ทำงานไม่สำเร็จ ลองอีกครั้ง หรือติดต่อทีมงาน",
                "{other:?}"
            );
        }
    }

    #[test]
    fn error_text_maps_every_variant() {
        assert_eq!(
            error_text(&ConnectError::Code(CodeError::Prefix)),
            "รหัสไม่ถูกต้อง ต้องขึ้นต้นด้วย rr1."
        );
        assert_eq!(
            error_text(&ConnectError::Code(CodeError::TooLong)),
            "รหัสยาวเกินไป"
        );
        assert_eq!(
            error_text(&ConnectError::Code(CodeError::NotPrintable)),
            "รหัสมีช่องว่างหรือตัวอักษรที่ใช้ไม่ได้"
        );
        assert_eq!(
            error_text(&ConnectError::Unsupported),
            "Rongroi Connect ใช้ได้บน Windows เท่านั้น"
        );
        assert_eq!(
            error_text(&ConnectError::Timeout),
            "Connect ไม่ตอบในเวลาที่กำหนด"
        );
        assert_eq!(
            error_text(&ConnectError::NotAbsolute),
            "เปิด Rongroi Connect ไม่ได้"
        );
        assert_eq!(
            error_text(&ConnectError::Io(io::Error::new(
                io::ErrorKind::NotFound,
                "missing"
            ))),
            "เปิด Rongroi Connect ไม่ได้"
        );
        assert_eq!(
            error_text(&ConnectError::PipeClientMismatch {
                expected: 10,
                got: 20,
            }),
            "เปิด Rongroi Connect ไม่ได้"
        );
    }
}
