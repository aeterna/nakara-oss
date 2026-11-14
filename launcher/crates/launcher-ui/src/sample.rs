// SPDX-License-Identifier: MIT

use crate::model::{Instance, Kind, NewsItem};

/// Sample data for the studio's other games shown in the sidebar when
/// `profile.features.studio_games` is enabled.
pub fn studio() -> Vec<Instance> {
    vec![
        Instance {
            initials: "RB".to_string(),
            name: "Roblox RP".to_string(),
            status: "ทดสอบภายใน".to_string(),
            status_on: false,
            skin: 0x7fb0e6,
            chips: ["Roblox".to_string(), "ทดสอบภายใน".to_string()],
            sub: "ยังเปิดเฉพาะทีมงาน จะขึ้นที่นี่เมื่อการทดสอบสองคนผ่าน".to_string(),
            pick_label: "เวอร์ชัน".to_string(),
            pick_value: "PoC".to_string(),
            play_label: "รอเปิดทดสอบ".to_string(),
            play_enabled: false,
            show_hours: false,
            hours: None,
            show_invite: false,
            news: vec![
                NewsItem {
                    title: "ระบบทดสอบในเกมพร้อมแล้ว".to_string(),
                    date: "8 พ.ย.".to_string(),
                    url: None,
                },
                NewsItem {
                    title: "Lobby สำหรับทดสอบสองคน".to_string(),
                    date: "8 พ.ย.".to_string(),
                    url: None,
                },
            ],
            patch_title: "PoC · ร่าง".to_string(),
            patch: vec![("ใหม่".to_string(), vec!["ปุ่มทดสอบทั้งชุดในเมนู F6".to_string()])],
            operator: "AETERNA Game".to_string(),
            contact: "contact@example.com".to_string(),
            kind: Kind::Studio,
        },
        Instance {
            initials: "VN".to_string(),
            name: "Visual novel".to_string(),
            status: "ยังไม่ประกาศชื่อ".to_string(),
            status_on: false,
            skin: 0xe2a0a8,
            chips: ["Ren'Py".to_string(), "เร็วๆ นี้".to_string()],
            sub: "ชื่อเกมยังไม่ประกาศ ติดตามข่าวใน Discord ของสตูดิโอ".to_string(),
            pick_label: "ช่องทาง".to_string(),
            pick_value: "Steam (ยังไม่เปิด)".to_string(),
            play_label: "ติดตามใน Discord".to_string(),
            play_enabled: false,
            show_hours: false,
            hours: None,
            show_invite: false,
            news: vec![
                NewsItem {
                    title: "ภาพตัวละครชุดใหม่".to_string(),
                    date: "22 ต.ค.".to_string(),
                    url: None,
                },
                NewsItem {
                    title: "เปิดห้อง Playtest ใน Discord".to_string(),
                    date: "12 พ.ย.".to_string(),
                    url: None,
                },
            ],
            patch_title: "ยังไม่มีแพตช์".to_string(),
            patch: Vec::new(),
            operator: "AETERNA Game".to_string(),
            contact: "contact@example.com".to_string(),
            kind: Kind::Studio,
        },
        Instance {
            initials: "RR".to_string(),
            name: "Rongroi".to_string(),
            status: "0.14.0".to_string(),
            status_on: true,
            skin: 0x4fc2ad,
            chips: ["เครื่องมือ".to_string(), "0.14.0".to_string()],
            sub: "ตรวจเครื่องของตัวเองแบบออฟไลน์ หรือวางรหัสจับคู่ที่เซิร์ฟให้มาเพื่อส่งรายงานด้วย Connect"
                .to_string(),
            pick_label: "โหมด".to_string(),
            pick_value: "Offline".to_string(),
            play_label: "เปิด Rongroi".to_string(),
            play_enabled: true,
            show_hours: false,
            hours: None,
            show_invite: false,
            news: vec![
                NewsItem {
                    title: "กฎใหม่: ชื่อโปรแกรมนอกโฟลเดอร์ Windows".to_string(),
                    date: "12 พ.ย.".to_string(),
                    url: None,
                },
                NewsItem {
                    title: "Connect พร้อมทดสอบวงปิด".to_string(),
                    date: "7 พ.ย.".to_string(),
                    url: None,
                },
            ],
            patch_title: "0.14.0 · 3 พ.ย.".to_string(),
            patch: vec![
                ("ใหม่".to_string(), vec!["sidecar สำหรับ Connect".to_string()]),
                ("แก้".to_string(), vec!["แผนภาพใน README".to_string()]),
            ],
            operator: "AETERNA Game".to_string(),
            contact: "contact@example.com".to_string(),
            kind: Kind::Rongroi,
        },
    ]
}

/// Sample featured event; the real one comes from the feed. Only the studio
/// build shows it.
pub fn event() -> Option<(&'static str, &'static str)> {
    if crate::profile::get().features.studio_games {
        Some(("ลอยกระทงที่ท่าน้ำนคร", "เสาร์ 22 พ.ย. · 20:00 ในเมือง"))
    } else {
        None
    }
}
