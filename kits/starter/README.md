# AETERNA Starter Kit

ชุดพื้นฐาน 12 ตัว (0.2) สำหรับเปิดเซิร์ฟ FiveM ของตัวเอง ใช้แยกทีละตัวหรือลงทั้งชุดก็ได้ · Twelve base resources (0.2) for running your own FiveM server. Use one or use them all.

| Resource | Version | ไทย | English |
| --- | --- | --- | --- |
| `aeterna_core` | 0.2.0 | ฐานร่วม: focus, ภาษา, เวลา, ที่เก็บข้อมูล, ทะเบียน self-test | Shared base: focus, locale, time, storage, self-test registry |
| `aeterna_uikit` | 0.2.0 | panel, confirm, input, progress, skill check, เมนู | Panels, prompts, progress, skill check, menu |
| `aeterna_notify` | 0.2.0 | toast, ประกาศ, ข้อความต้อนรับ | Toasts, announcements, message of the day |
| `aeterna_layout` | 0.2.0 | ให้ผู้เล่นลากและย่อขยาย UI | Lets players move and scale the UI |
| `aeterna_hudkit` | 0.2.0 | แถบสถานะ, รถ, ถนน, มินิแมป, ตัวบอกเสียงพูด (ถ้ามี `pma-voice`) | Status bars, vehicle, street, minimap, voice indicator (with `pma-voice`) |
| `aeterna_phonekit` | 0.2.0 | โทรศัพท์และ API ให้เพิ่มแอป | Phone shell and an app API |
| `aeterna_invkit` | 0.2.0 | stash ส่วนตัวและการใช้ไอเทมบน `ox_inventory` | Personal stash and item use on `ox_inventory` |
| `aeterna_radial` | 0.1.0 | เมนูวงกลมที่ resource อื่นเพิ่มช่องได้ | A radial menu other resources add slots to |
| `aeterna_loading` | 0.1.0 | หน้าโหลดที่บอกขั้นตอนโหลดจริง | A loading screen that shows the real loading stages |
| `aeterna_testkit` | 0.1.0 | เมนูทดสอบในเกม รัน self-test ทุกตัวและเขียนรายงาน | In-game test menu that runs every self-test and writes a report |
| `aeterna_phonecall` | 0.1.0 | เบอร์โทร ข้อความ และโทรด้วยเสียง (ใช้ `pma-voice` บน Legacy) | Phone numbers, SMS and voice calls (`pma-voice` on Legacy) |
| `aeterna_camera` | 0.1.0 | แอปกล้องและแกลเลอรี (ถ่ายรูปเมื่อมี `screenshot-basic`) | Camera and gallery apps (photos need `screenshot-basic`) |

ตัวเสริมที่ไม่บังคับ · Optional: `ox_inventory` (`aeterna_invkit`), `pma-voice` (`aeterna_phonecall`, ตัวบอกเสียงของ `aeterna_hudkit`), `screenshot-basic` (`aeterna_camera`). ถ้าไม่มี ฟีเจอร์ที่ต้องใช้จะบอกว่าใช้ไม่ได้ · Without them, the feature that needs them reports itself unavailable.

## ติดตั้ง · Install

1. ดาวน์โหลด `aeterna-starter-kit-0.2.0.zip` จาก [Releases](https://github.com/aeterna/nakara-oss/releases/tag/aeterna-starter-kit%400.2.0) แล้วแตกลง `resources/` (ได้โฟลเดอร์ `resources/[aeterna_kit]/` ที่มี resource ทั้ง 12 ตัวกับ `resources.cfg`) · Download `aeterna-starter-kit-0.2.0.zip` from [Releases](https://github.com/aeterna/nakara-oss/releases/tag/aeterna-starter-kit%400.2.0) and unpack it into `resources/` (you get `resources/[aeterna_kit]/` with all 12 resources plus `resources.cfg`). หรือโหลดทีละตัวจาก [Releases](https://github.com/aeterna/nakara-oss/releases?q=aeterna_) แล้วแตกลง `resources/[aeterna_kit]/` · Or download the packages one by one and unpack them into `resources/[aeterna_kit]/`.
2. คัดลอกเนื้อหา [`resources.cfg`](resources.cfg) ลง `server.cfg` ต่อจาก framework · Copy the contents of [`resources.cfg`](resources.cfg) into `server.cfg`, after your framework.
3. รีสตาร์ตเซิร์ฟ เข้าเกมด้วยบัญชีที่มี ACE `aeterna.testkit.run` กด F9 แล้วเลือก Run all ทุกแถวควรผ่านหรือข้าม · Restart, join as an account with ACE `aeterna.testkit.run`, press F9 and choose Run all. Every row should pass or skip.

## ปุ่มตั้งต้น · Default keys

F5 เมนู · M โทรศัพท์ · F3 เมนูวง (คีย์บอร์ด) · F2 แผง inventory · F9 เมนูทดสอบ · Y/U ปุ่มบน toast · PageUp/PageDown รับ/วางสาย · F5 menu, M phone, F3 radial (keyboard), F2 inventory panel, F9 test menu, Y/U toast actions, PageUp/PageDown answer/hang up.

ผู้เล่นเปลี่ยนปุ่มเองได้ที่ Settings → Key Bindings → FiveM เจ้าของเซิร์ฟเปลี่ยนหรือปิดค่าตั้งต้นด้วย `setr aeterna_keys` (ดู [`resources.cfg`](resources.cfg)) · Players rebind in Settings → Key Bindings → FiveM; owners change or turn the defaults off with `setr aeterna_keys` (see [`resources.cfg`](resources.cfg)).

ธีมสำเร็จรูป · Theme presets: `setr aeterna_theme_preset asphalt|paper|night-market`

คู่มือเต็ม: [ไทย](../../docs/guides/starter-kit.th.md) · Full guide: [English](../../docs/guides/starter-kit.en.md) · [CHANGELOG](CHANGELOG.md)
