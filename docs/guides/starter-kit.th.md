# คู่มือ AETERNA Starter Kit

resource ของ FiveM 7 ตัว สัญญาอนุญาต MIT สำหรับเซิร์ฟของคุณเอง ใช้เป็นแม่แบบได้ อ่าน แก้ และเลือกเก็บเฉพาะที่ต้องการ

## สิ่งที่ต้องมี

ทดสอบร่วมกันบน FXServer Enhanced (game build 3788) กับ `qbx_core` 1.23.0, `ox_lib` 3.30.6, `oxmysql` 2.14.3 และ
`ox_inventory` 2.44.0 เวอร์ชันอื่นอาจใช้ได้แต่ยังไม่ได้ทดสอบ มีแค่ `aeterna_invkit` ที่ต้องใช้ `ox_inventory`

| Resource | ต้องมี |
| --- | --- |
| `aeterna_core` | ไม่ต้องมีตัวอื่น |
| `aeterna_uikit` | `aeterna_core` |
| `aeterna_notify` | `aeterna_core` (เพิ่ม `aeterna_layout` ถ้าอยากให้ลาก toast ได้) |
| `aeterna_layout` | `aeterna_core`, `aeterna_uikit` |
| `aeterna_hudkit` | `aeterna_core`, `aeterna_uikit`, `aeterna_layout` |
| `aeterna_phonekit` | `aeterna_core`, `aeterna_uikit`, `aeterna_notify` (เพิ่ม `aeterna_layout` ถ้าอยากให้ลากโทรศัพท์ได้) |
| `aeterna_invkit` | `aeterna_core`, `aeterna_uikit`, `ox_inventory` |

## ติดตั้ง

1. ดาวน์โหลด zip จาก [Releases](https://github.com/aeterna/nakara-oss/releases?q=aeterna_) และตรวจไฟล์ก่อน:
   `gh attestation verify <zip> --repo aeterna/nakara-oss`
2. แตกไฟล์ลง `resources/[aeterna_kit]/` โดยคงชื่อโฟลเดอร์ไว้ เช่น `aeterna_core`
3. คัดลอก [`kits/starter/resources.cfg`](../../kits/starter/resources.cfg) ลง `server.cfg` ต่อจาก framework
4. รีสตาร์ตเซิร์ฟ แล้วรัน `aeterna_core_selftest` ใน console ของเซิร์ฟ ทุกบรรทัดควรผ่าน

ทุกแพ็กเกจไม่ตั้งปุ่มเริ่มต้น จึงไม่ชนกับ resource อื่น ผู้เล่นตั้งปุ่มเองได้ที่ Settings → Key Bindings → FiveM

| คำสั่ง | Key mapping | ใช้ทำอะไร |
| --- | --- | --- |
| `aeterna_uikit_menu` | `+aeterna_uikit_menu` | เปิดเมนูของชุด |
| `aeterna_layout` | `+aeterna_layout_edit` | เปิดหน้าจัดตำแหน่ง UI |
| `aeterna_hudkit_settings` | `+aeterna_hudkit_settings` | เปิดตั้งค่า HUD |
| `aeterna_phonekit_open` | `+aeterna_phonekit_open` | เปิดโทรศัพท์ |
| `aeterna_stash` | `+aeterna_invkit_open` | เปิด stash ส่วนตัว เมื่อเปิดใช้ใน config |
| `aeterna_announce <ข้อความ>` | ไม่มี | ส่งประกาศ ต้องมี ACE `aeterna.notify.announce` |
| `aeterna_core_selftest` | ไม่มี | รัน self-test ต้องมี ACE `aeterna.core.selftest` |

## การตั้งค่า

| Convar | ความหมาย |
| --- | --- |
| `aeterna_locale` | `en` หรือ `th` ใช้ `setr` |
| `aeterna_timezone` | เวลาที่แสดง เช่น `+07:00` ใช้ `setr` |
| `aeterna_theme` | ไฟล์ธีมของคุณ ดูด้านล่าง ใช้ `setr` |
| `aeterna_core_log_level` | ระดับ log ของชุด |
| `aeterna_uikit_menu_title` | ชื่อเมนูของชุด |

แต่ละแพ็กเกจมี `config.lua` ของตัวเอง ค่าตั้งและตำแหน่ง UI ของผู้เล่นเก็บในเครื่องผู้เล่น ชุดนี้ไม่สร้างตารางในฐานข้อมูล

## เปลี่ยนหน้าตา

ทุกหน้าจออ่านสีจาก `html/theme.css` ถ้าอยากเปลี่ยนทั้งชุด ให้สร้าง resource เล็กๆ:

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

## ข้อจำกัด

โทรศัพท์ไม่มีการโทร ข้อความระหว่างผู้เล่น กล้อง หรือธนาคาร เพิ่มเองได้ในรูปแบบแอป HUD ไม่มีตัวบอกเสียงพูดและมินิแมปทรงกลม
ชุดนี้ให้ใช้ตามสภาพภายใต้สัญญาอนุญาต MIT หากพบปัญหา เปิด issue พร้อมเวอร์ชันและข้อความ error
