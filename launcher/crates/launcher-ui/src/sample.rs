// SPDX-License-Identifier: MIT

/// Sample data for the Home screen. Real data comes from the profile and feed.
#[derive(Clone, Copy)]
pub struct Instance {
    pub initials: &'static str,
    pub name: &'static str,
    pub status: &'static str,
    pub status_on: bool,
    pub skin: u32,
    pub chips: [&'static str; 2],
    pub sub: &'static str,
    pub pick_label: &'static str,
    pub pick_value: &'static str,
    pub play_label: &'static str,
    pub play_enabled: bool,
    pub show_hours: bool,
    pub show_invite: bool,
    pub news: &'static [(&'static str, &'static str)],
    pub patch_title: &'static str,
    pub patch: &'static [(&'static str, &'static [&'static str])],
    pub operator: &'static str,
    pub contact: &'static str,
}

const SAMPLES: [Instance; 4] = [
    Instance {
        initials: "NC",
        name: "Nakara City",
        status: "เปิด 17:00",
        status_on: false,
        skin: 0xd4af37,
        chips: ["FiveM Enhanced", "Early Access"],
        sub: "เมืองปิดอยู่ เปิดอีกครั้ง 17:00 วางรหัสเชิญไว้ก่อนได้",
        pick_label: "เซิร์ฟเวอร์",
        pick_value: "Nakara · EA",
        play_label: "เปิด 17:00",
        play_enabled: false,
        show_hours: true,
        show_invite: true,
        news: &[
            ("ชั่วโมงเมืองใหม่ 17:00–00:00", "13 พ.ย."),
            ("ภารกิจวันแรกสำหรับคนเพิ่งเข้าเมือง", "10 พ.ย."),
        ],
        patch_title: "แพตช์ 13 พ.ย. · ร่าง",
        patch: &[
            (
                "ใหม่",
                &["เว็บและเกมอ่านชั่วโมงเปิดจากที่เดียว", "หน้าเว็บแสดงเวลาเปิดตามจริง"],
            ),
            ("แก้", &["แจ้งเหตุซ้ำในช่อง Discord หยุดแล้ว"]),
        ],
        operator: "AETERNA Game",
        contact: "contact@example.com",
    },
    Instance {
        initials: "RB",
        name: "Roblox RP",
        status: "ทดสอบภายใน",
        status_on: false,
        skin: 0x7fb0e6,
        chips: ["Roblox", "ทดสอบภายใน"],
        sub: "ยังเปิดเฉพาะทีมงาน จะขึ้นที่นี่เมื่อการทดสอบสองคนผ่าน",
        pick_label: "เวอร์ชัน",
        pick_value: "PoC",
        play_label: "รอเปิดทดสอบ",
        play_enabled: false,
        show_hours: false,
        show_invite: false,
        news: &[
            ("ระบบทดสอบในเกมพร้อมแล้ว", "8 พ.ย."),
            ("Lobby สำหรับทดสอบสองคน", "8 พ.ย."),
        ],
        patch_title: "PoC · ร่าง",
        patch: &[("ใหม่", &["ปุ่มทดสอบทั้งชุดในเมนู F6"])],
        operator: "AETERNA Game",
        contact: "contact@example.com",
    },
    Instance {
        initials: "VN",
        name: "Visual novel",
        status: "ยังไม่ประกาศชื่อ",
        status_on: false,
        skin: 0xe2a0a8,
        chips: ["Ren'Py", "เร็วๆ นี้"],
        sub: "ชื่อเกมยังไม่ประกาศ ติดตามข่าวใน Discord ของสตูดิโอ",
        pick_label: "ช่องทาง",
        pick_value: "Steam (ยังไม่เปิด)",
        play_label: "ติดตามใน Discord",
        play_enabled: false,
        show_hours: false,
        show_invite: false,
        news: &[
            ("ภาพตัวละครชุดใหม่", "22 ต.ค."),
            ("เปิดห้อง Playtest ใน Discord", "12 พ.ย."),
        ],
        patch_title: "ยังไม่มีแพตช์",
        patch: &[],
        operator: "AETERNA Game",
        contact: "contact@example.com",
    },
    Instance {
        initials: "RR",
        name: "Rongroi",
        status: "0.14.0",
        status_on: true,
        skin: 0x4fc2ad,
        chips: ["เครื่องมือ", "0.14.0"],
        sub: "ตรวจเครื่องของตัวเองแบบออฟไลน์ หรือวางรหัสจับคู่ที่เซิร์ฟให้มาเพื่อส่งรายงานด้วย Connect",
        pick_label: "โหมด",
        pick_value: "Offline",
        play_label: "เปิด Rongroi",
        play_enabled: true,
        show_hours: false,
        show_invite: false,
        news: &[
            ("กฎใหม่: ชื่อโปรแกรมนอกโฟลเดอร์ Windows", "12 พ.ย."),
            ("Connect พร้อมทดสอบวงปิด", "7 พ.ย."),
        ],
        patch_title: "0.14.0 · 3 พ.ย.",
        patch: &[
            ("ใหม่", &["sidecar สำหรับ Connect"]),
            ("แก้", &["แผนภาพใน README"]),
        ],
        operator: "AETERNA Game",
        contact: "contact@example.com",
    },
];

/// The neutral entry 0 for builds without the studio's games. Everything that
/// belongs to Nakara City is left blank and filled from the profile.
const NEUTRAL: Instance = Instance {
    initials: "",
    name: "",
    status: "ยังไม่มีข้อมูลสถานะ",
    status_on: false,
    skin: SAMPLES[0].skin,
    chips: ["", ""],
    sub: "สถานะและข่าวจะขึ้นที่นี่เมื่อเซิร์ฟเชื่อมต่อ feed",
    pick_label: "เซิร์ฟเวอร์",
    pick_value: "",
    play_label: "เข้าเกม",
    play_enabled: true,
    show_hours: false,
    show_invite: false,
    news: &[],
    patch_title: "ยังไม่มีแพตช์",
    patch: &[],
    operator: "",
    contact: "",
};

/// The instances shown on Home. Entry 0 is the profile's server; the studio's
/// other games follow only when the profile enables `studio_games`. Status, news
/// and patch notes are sample data for the studio's entries.
pub fn instances() -> &'static [Instance] {
    static INSTANCES: std::sync::OnceLock<Vec<Instance>> = std::sync::OnceLock::new();
    INSTANCES.get_or_init(|| {
        let p = crate::profile::get();
        let studio = p.features.studio_games;
        let mut first = if studio { SAMPLES[0] } else { NEUTRAL };

        first.name = &p.server.name;
        first.initials = Box::leak(crate::profile::initials(&p.server.name).into_boxed_str());
        first.chips[0] = crate::profile::game_label(&p.server.game);
        first.operator = &p.server.operator;
        first.contact = &p.server.contact_email;

        if !studio {
            first.pick_value = &p.server.name;
        }

        let mut instances = vec![first];
        if p.features.studio_games {
            instances.extend_from_slice(&SAMPLES[1..]);
        }

        instances
    })
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
