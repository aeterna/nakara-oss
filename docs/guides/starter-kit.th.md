# คู่มือ AETERNA Starter Kit

resource ของ FiveM 12 ตัว (0.2) สัญญาอนุญาต MIT สำหรับเซิร์ฟของคุณเอง ใช้เป็นแม่แบบได้ อ่าน แก้ และเลือกเก็บเฉพาะที่ต้องการ

## สิ่งที่ต้องมี

ทดสอบร่วมกันบน FXServer Enhanced (game build 3788) กับ `qbx_core` 1.23.0, `ox_lib` 3.30.6, `oxmysql` 2.14.3 และ
`ox_inventory` 2.44.0 เวอร์ชันอื่นอาจใช้ได้แต่ยังไม่ได้ทดสอบ มี 3 ตัวที่ไม่บังคับ แค่เปิดฟีเจอร์เพิ่ม: `ox_inventory` (`aeterna_invkit`), `pma-voice` (การโทรของ
`aeterna_phonecall` บน Legacy และตัวบอกเสียงพูดของ `aeterna_hudkit`) และ `screenshot-basic` (ถ่ายรูปใน `aeterna_camera`) ถ้าไม่มี
ฟีเจอร์ที่ต้องใช้จะบอกว่าใช้ไม่ได้

| Resource | ต้องมี |
| --- | --- |
| `aeterna_core` | ไม่ต้องมีตัวอื่น |
| `aeterna_uikit` | `aeterna_core` |
| `aeterna_notify` | `aeterna_core` (เพิ่ม `aeterna_layout` ถ้าอยากให้ลาก toast ได้) |
| `aeterna_layout` | `aeterna_core`, `aeterna_uikit` |
| `aeterna_hudkit` | `aeterna_core`, `aeterna_uikit`, `aeterna_layout` |
| `aeterna_phonekit` | `aeterna_core`, `aeterna_uikit`, `aeterna_notify` (เพิ่ม `aeterna_layout` ถ้าอยากให้ลากโทรศัพท์ได้) |
| `aeterna_invkit` | `aeterna_core`, `aeterna_uikit`, `ox_inventory` |
| `aeterna_testkit` | `aeterna_core`, `aeterna_uikit` |
| `aeterna_radial` | `aeterna_core`, `aeterna_uikit` |
| `aeterna_loading` | ไม่ต้องมีตัวอื่น (เพิ่ม `aeterna_core` ถ้าอยากให้ลงทะเบียน self-test) |
| `aeterna_phonecall` | `aeterna_core`, `aeterna_uikit`, `aeterna_phonekit` |
| `aeterna_camera` | `aeterna_core`, `aeterna_uikit`, `aeterna_phonekit`, `aeterna_notify` |

## ติดตั้ง

1. ดาวน์โหลด `aeterna-starter-kit-0.2.0.zip` จาก
   [Releases](https://github.com/aeterna/nakara-oss/releases/tag/aeterna-starter-kit%400.2.0) (tag `aeterna-starter-kit@0.2.0`)
   และตรวจไฟล์ก่อน: `gh attestation verify <zip> --repo aeterna/nakara-oss`
2. แตกไฟล์ลง `resources/` จะได้โฟลเดอร์ `resources/[aeterna_kit]/` ที่มี resource ทั้ง 12 ตัวและ `resources.cfg` ถ้าอยากเลือกเอง โหลดทีละแพ็กเกจจาก
   [Releases](https://github.com/aeterna/nakara-oss/releases?q=aeterna_) แล้วแตกลง `resources/[aeterna_kit]/` โดยคงชื่อโฟลเดอร์ไว้ เช่น `aeterna_core`
3. คัดลอก [`kits/starter/resources.cfg`](../../kits/starter/resources.cfg) (มีอยู่ใน zip ด้วย) ลง `server.cfg` ต่อจาก framework
4. รีสตาร์ตเซิร์ฟ เข้าเกมด้วยบัญชีที่มี ACE `aeterna.testkit.run` กด F9 แล้วเลือก **Run all** ทุกแถวควรผ่านหรือข้าม
   รายงานถูกเก็บไว้ใน `aeterna_testkit/reports/` แนบ issue ได้ทันที ส่วน `aeterna_core_selftest` ใน console ของเซิร์ฟยังรันเฉพาะของ core

## ปุ่มตั้งต้น

ชุดนี้แนะนำปุ่มให้ตัวเปิดหน้าจอ: F5 เมนู · M โทรศัพท์ · F3 เมนูวง (คีย์บอร์ด) · F2 แผง inventory · F9 เมนูทดสอบ · Y และ U
สำหรับปุ่มบน toast · PageUp และ PageDown รับและวางสาย ปุ่มที่ผู้เล่นตั้งเองที่ Settings → Key Bindings → FiveM มาก่อนเสมอ
เจ้าของเซิร์ฟเปลี่ยนหรือปิดค่าตั้งต้นได้ด้วย convar ตัวเดียว:

```
setr aeterna_keys ""                                           # ใช้ค่าตั้งต้นของชุด
setr aeterna_keys "off"                                        # ไม่ตั้งปุ่มให้เลย
setr aeterna_keys "+aeterna_phonekit_open=F1, +aeterna_testkit_menu="   # เปลี่ยนหนึ่งปุ่ม ล้างหนึ่งปุ่ม
```

| คำสั่ง | Key mapping | ใช้ทำอะไร |
| --- | --- | --- |
| `aeterna_uikit_menu` | `+aeterna_uikit_menu` | เปิดเมนูของชุด |
| `aeterna_layout` | `+aeterna_layout_edit` | เปิดหน้าจัดตำแหน่ง UI |
| `aeterna_hudkit_settings` | `+aeterna_hudkit_settings` | เปิดตั้งค่า HUD |
| `aeterna_phonekit_open` | `+aeterna_phonekit_open` | เปิดโทรศัพท์ |
| ไม่มี | `+aeterna_radial_open` | เปิดเมนูวง |
| ไม่มี | `+aeterna_testkit_menu` | เปิดเมนูทดสอบ ต้องมี ACE `aeterna.testkit.run` |
| `aeterna_stash` | `+aeterna_invkit_open` | เปิด stash ส่วนตัว เมื่อเปิดใช้ใน config |
| `aeterna_announce <ข้อความ>` | ไม่มี | ส่งประกาศ ต้องมี ACE `aeterna.notify.announce` |
| `aeterna_core_selftest` | ไม่มี | รัน self-test ของ core ต้องมี ACE `aeterna.core.selftest` |

## การตั้งค่า

| Convar | ความหมาย |
| --- | --- |
| `aeterna_locale` | `en` หรือ `th` ใช้ `setr` |
| `aeterna_timezone` | เวลาที่แสดง เช่น `+07:00` ใช้ `setr` |
| `aeterna_theme` | ไฟล์ธีมของคุณ ดูด้านล่าง ใช้ `setr` |
| `aeterna_theme_preset` | `asphalt` (ค่าเริ่มต้น) `paper` หรือ `night-market` ใช้ `setr` |
| `aeterna_keys` | เปลี่ยนหรือปิดปุ่มตั้งต้น ดูด้านบน ใช้ `setr` |
| `aeterna_core_log_level` | ระดับ log ของชุด |
| `aeterna_uikit_menu_title` | ชื่อเมนูของชุด |

แต่ละแพ็กเกจมี `config.lua` ของตัวเอง ค่าตั้งและตำแหน่ง UI ของผู้เล่นเก็บในเครื่องผู้เล่น ชุดนี้ไม่สร้างตารางในฐานข้อมูล

## เปลี่ยนหน้าตา

เลือกธีมสำเร็จรูปได้ด้วย `setr aeterna_theme_preset asphalt` หรือ `paper` (สว่าง) หรือ `night-market` (มืด สีส้ม) ถ้าอยากไปไกลกว่านั้น
ทุกหน้าจออ่านสีจาก `html/theme.css` ให้สร้าง resource เล็กๆ เพื่อเปลี่ยนทั้งชุด:

```lua
-- my_theme/fxmanifest.lua
fx_version 'cerulean'
game 'gta5'
files { 'theme.css' }
```

```css
/* my_theme/theme.css */
:root {
    --accent: #0f9d76;
    --surface: #17191c;
    --raised: #202328;
    --radius-m: 6px;
}
```

จากนั้นใส่ `ensure my_theme` ก่อนชุดนี้ และตั้ง `setr aeterna_theme "nui://my_theme/theme.css"` ไฟล์ของคุณโหลดต่อจากไฟล์หลัก
จึงใส่เฉพาะค่าที่อยากเปลี่ยนได้ และจะวางฟอนต์ไว้ใน resource เดียวกันพร้อม `@font-face` ก็ได้

`ox_inventory` มีหน้าจอและสัญญาอนุญาต GPL-3.0 ของตัวเอง ชุดนี้ไม่แต่งหน้าจอของมันและไม่มีไฟล์ของมันอยู่ข้างใน
ถ้าคุณแก้ไฟล์เว็บของ `ox_inventory` ส่วนที่แก้ต้องเป็นไปตามสัญญาอนุญาตนั้น

## ต่อยอด

- Panel และ prompt: [`aeterna_uikit`](../specs/aeterna_uikit.md)
- Toast และประกาศ: [`aeterna_notify`](../specs/aeterna_notify.md)
- ทำให้ UI ของคุณลากได้: [`aeterna_layout`](../specs/aeterna_layout.md)
- เพิ่มแถบ HUD: [`aeterna_hudkit`](../specs/aeterna_hudkit.md)
- สร้างแอปโทรศัพท์: [`aeterna_phonekit`](../specs/aeterna_phonekit.md)
- Stash และการใช้ไอเทม: [`aeterna_invkit`](../specs/aeterna_invkit.md)
- เพิ่มช่องในเมนูวง: [`aeterna_radial`](../specs/aeterna_radial.md)
- หน้าโหลด: [`aeterna_loading`](../specs/aeterna_loading.md)
- ลงทะเบียน self-test ของคุณเอง: [`aeterna_testkit`](../specs/aeterna_testkit.md)
- เบอร์โทร ข้อความ และการโทร: [`aeterna_phonecall`](../specs/aeterna_phonecall.md)
- กล้องและแกลเลอรี: [`aeterna_camera`](../specs/aeterna_camera.md)

## ข้อจำกัด

ยังไม่ได้ตรวจบนเซิร์ฟจริง: ข้อความระหว่างผู้เล่นสองคน การโทรระหว่างผู้เล่นสองคน สายไม่ว่าง และการ์ดผู้เล่น B ของเมนูทดสอบ
(ดู [CHANGELOG](../../kits/starter/CHANGELOG.md)) โทรศัพท์ไม่มีธนาคาร ชุดนี้ทดสอบกับผู้เล่นหนึ่งคนบน FXServer Enhanced b177 กับ `qbx_core`
ให้ใช้ตามสภาพภายใต้สัญญาอนุญาต MIT หากพบปัญหา เปิด issue พร้อมเวอร์ชันและข้อความ error (รายงานของเมนูทดสอบมีทั้งสองอย่าง)
