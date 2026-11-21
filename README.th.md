<div align="center">

[English](README.md) · **🇹🇭 ภาษาไทย**

# nakara-oss

### สคริปต์และเครื่องมือ FiveM ฟรี ที่คุณตรวจได้ก่อนลง server

[![npm](https://img.shields.io/npm/v/@aeterna_game/fivem-devkit?style=flat-square&label=fivem-devkit&color=1f6f5c)](https://www.npmjs.com/package/@aeterna_game/fivem-devkit)
[![Releases](https://img.shields.io/badge/Releases-CI--attested-0869b0?style=flat-square)](https://github.com/aeterna/nakara-oss/releases)
[![Capabilities](https://img.shields.io/badge/oss.json-checked_on_every_PR-6a4fe0?style=flat-square)](packages/devkit/docs/safety.md)
[![License](https://img.shields.io/badge/License-MIT-2b8a3e?style=flat-square)](LICENSE)

**[เว็บไซต์](https://aeterna.github.io/nakara-oss/) · [สคริปต์ที่แจก](#สคริปต์ที่แจก) · [ตรวจสคริปต์ก่อนลง](#ตรวจสคริปต์ก่อนลง) · [Trust Architecture](#️-trust-architecture) · [สิ่งที่ scanner จับไม่ได้](#สิ่งที่-scanner-จับไม่ได้)**

</div>

resource และเครื่องมือ FiveM แบบ open-source จากทีมพัฒนา **Nakara City** ทุก resource ประกาศใน
`oss.json` ว่าจะแตะอะไรได้บ้าง ทุก PR ถูกสแกนหาโค้ดอันตราย และทุก release build ใน CI พร้อม
provenance attestation คุณจึงตรวจซ้ำได้เองทั้งหมด

## สคริปต์ที่แจก

ทุกชิ้นข้างล่างใช้ฟรี (MIT) ประกาศใน `oss.json` ว่าแตะอะไรได้บ้าง และแจกเป็นไฟล์ release ที่ CI build
พร้อม provenance attestation

### Resource สำหรับ FiveM

| สคริปต์ | ทำอะไร | release ล่าสุด |
|---|---|---|
| [`nakara_tickets`](packages/tickets) + [server](tickets/deploy/README.md) | ระบบตั๋ว Discord ที่ host เอง: ตั๋วเป็น private thread · dashboard เว็บไทย/อังกฤษ · ทีมงานสั่งในเกมได้ (ดูข้อมูลผู้เล่น วาร์ป ชุบ ให้ไอเทม) ผ่าน bridge ที่ไม่เปิด port | [`nakara-tickets@0.1.0`](https://github.com/aeterna/nakara-oss/releases/tag/nakara-tickets%400.1.0) · image `ghcr.io/aeterna/nakara-tickets:0.1.0` |
| [`nakara_cargen_fix`](packages/cargen-fix) | กัน crash `CNetworkCarGenWorldStateData Pool Full` ฝั่ง client และอธิบายว่าทำไมวิธี `GAMECONFIG_FILE` ที่แชร์กันใช้ไม่ได้ ([สิ่งที่ตรวจแล้ว](packages/cargen-fix/README.md#what-we-have-verified)) | [`nakara_cargen_fix@1.0.0`](https://github.com/aeterna/nakara-oss/releases/tag/nakara_cargen_fix%401.0.0) |
| [`nakara_rongroi`](packages/rongroi) | ฝั่ง server ของ [aeterna-rongroi](https://github.com/aeterna/aeterna-rongroi) | [`nakara_rongroi@0.1.0`](https://github.com/aeterna/nakara-oss/releases/tag/nakara_rongroi%400.1.0) |

### AETERNA Starter Kit · ชุดพื้นฐาน 12 ตัว ใหม่ 5 ตัวใน 0.2 ([คู่มือ](https://aeterna.github.io/nakara-oss/starter-kit/) · [ลองธีม](https://aeterna.github.io/nakara-oss/starter-kit/theme/))

| สคริปต์ | ทำอะไร | release ล่าสุด |
|---|---|---|
| [`aeterna_core`](packages/core) | ฐานร่วม: log · event bus ในเครื่อง · ตัวช่วยข้อความภาษาไทย · ค้นข้อความตามภาษา | [`0.1.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_core%400.1.0) · 0.2 (เร็วๆ นี้) |
| [`aeterna_uikit`](packages/uikit) | panel UI ที่ server คุม · prompt (`confirm` `input` `progress` `skillCheck`) · เมนูร่วม | [`0.1.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_uikit%400.1.0) · 0.2 (เร็วๆ นี้) |
| [`aeterna_notify`](packages/notify) | toast · banner ประกาศทั้งเซิร์ฟ · การ์ดข้อความประจำวัน | [`0.1.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_notify%400.1.0) · 0.2 (เร็วๆ นี้) |
| [`aeterna_invkit`](packages/invkit) | stash ส่วนตัว · การใช้ไอเทมที่ server ตรวจ บน `ox_inventory` | [`0.1.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_invkit%400.1.0) · 0.2 (เร็วๆ นี้) |
| [`aeterna_layout`](packages/layout) | ตัวจัดวาง HUD · เก็บ layout ไว้ที่เครื่องผู้เล่น | [`0.1.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_layout%400.1.0) · 0.2 (เร็วๆ นี้) |
| [`aeterna_phonekit`](packages/phonekit) | โทรศัพท์แบบประกอบแอปได้ มีแอปพื้นฐาน และ API สำหรับเขียนแอปเอง | [`0.1.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_phonekit%400.1.0) · 0.2 (เร็วๆ นี้) |
| [`aeterna_hudkit`](packages/hudkit) | HUD ผู้เล่น: แถบสถานะ · หน้าปัดรถ · ชื่อถนนและเข็มทิศ · minimap | [`0.1.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_hudkit%400.1.0) · 0.2 (เร็วๆ นี้) |
| [`aeterna_radial`](packages/radial) | เมนูวงกลมที่ resource อื่นเพิ่มช่องได้ · ตัวเลือกที่มีผลกับผู้เล่นอื่น server ตรวจซ้ำ | ใหม่ · 0.2 (เร็วๆ นี้) |
| [`aeterna_loading`](packages/loading) | หน้าโหลดที่บอกขั้นตอนโหลดจริง · ชื่อเซิร์ฟ ภาพพื้นหลัง และเคล็ดลับ | ใหม่ · 0.2 (เร็วๆ นี้) |
| [`aeterna_testkit`](packages/testkit) | ปุ่มเดียวรัน self-test ทุกตัวของชุดบนเซิร์ฟคุณ · ได้รายงานที่แนบ issue ได้ทันที | ใหม่ · 0.2 (เร็วๆ นี้) |
| [`aeterna_phonecall`](docs/specs/aeterna_phonecall.md) | เบอร์โทร ข้อความ และโทรด้วยเสียง เป็นสองแอปในโทรศัพท์ | ใหม่ · 0.2 (เร็วๆ นี้) |
| [`aeterna_camera`](docs/specs/aeterna_camera.md) | แอปกล้องและแกลเลอรีในโทรศัพท์ · รูปเก็บบนเซิร์ฟของคุณเอง | ใหม่ · 0.2 (เร็วๆ นี้) |

### เครื่องมือ

| เครื่องมือ | ทำอะไร | release ล่าสุด |
|---|---|---|
| [`fivem-devkit`](packages/devkit) · npm `@aeterna_game/fivem-devkit` | หาโค้ดอันตรายและ bug ที่ runtime ไม่เตือน ใน Lua/JS ของ FiveM ของใครก็ได้ พร้อม busted test harness | [npm](https://www.npmjs.com/package/@aeterna_game/fivem-devkit) · `npx @aeterna_game/fivem-devkit check` |
| [AETERNA Game Launcher](docs/adr/0002-aeterna-game-launcher.md) | launcher ของ server คุณเอง เขียนด้วย Rust · [ติดตั้ง](launcher/docs/install.md) · [สำหรับเจ้าของ server](launcher/docs/server-owners.md) | [`launcher-v0.1.0`](https://github.com/aeterna/nakara-oss/releases/tag/launcher-v0.1.0) |

โหลด **ไฟล์ release** ไม่ใช่ ZIP ของทั้ง repo เพราะใน repo มีเทสต์และเครื่องมือที่ server ไม่ต้องใช้ ·
release ทั้งหมด: [Releases](https://github.com/aeterna/nakara-oss/releases)

## ตรวจสคริปต์ก่อนลง

```bash
npx @aeterna_game/fivem-devkit safety ./some_resource
```

สคริปต์ที่ได้มาจากที่อื่นจะไม่มี `oss.json` ให้ใส่ค่านี้ในไฟล์ `.fivem-devkit.json` ในโฟลเดอร์ที่รันคำสั่ง
([ตัวเลือกทั้งหมด](packages/devkit/docs/safety.md)):

```json
{ "safety": { "requireManifest": false } }
```

ผลจริงจาก resource ทดสอบ:

```text
✗ [safety/dynamic-load] resources/some_script/server/main.lua:2
    load called — loads code at runtime that nobody reviewed
✗ [safety/host-exec] resources/some_script/server/main.lua:3
    os.execute — runs or changes things on the host machine
✗ [safety/secret-convar] resources/some_script/server/main.lua:4
    GetConvar('mysql_connection_string') reads a secret convar

safety: 3 error(s), 0 warning(s)
```

ผลที่ได้คือรายการจุดที่ต้องอ่าน ไม่ใช่คำตัดสิน

## 🏗️ Trust Architecture

<img alt="Trust Architecture: source และ oss.json ผ่าน PR gate (devkit safety ทำให้ PR ล้มถ้าโค้ดใช้เกินที่ oss.json ประกาศ · oss.json ที่เปลี่ยนต้องผ่าน CODEOWNERS) แล้ว release ใน CI พร้อม provenance attestation และ SHA256SUMS แล้วคุณตรวจซ้ำด้วยเครื่องมือตัวเดียวกันก่อน ensure · scanner จับไม่ได้: logic bomb ใน API ที่ประกาศไว้ · export ของ resource อื่น · server ที่เชื่อ client" src="docs/assets/trust-architecture-th.svg" width="960">

ตรวจ release ก่อนลง:

```bash
gh attestation verify nakara_cargen_fix-1.0.0.zip --repo aeterna/nakara-oss --signer-workflow aeterna/nakara-oss/.github/workflows/release.yml
# ↑ พิสูจน์ว่า zip นี้ build โดย release workflow ของเรา ไม่ใช่มีคนอัปโหลดเอง
sha256sum -c SHA256SUMS                                        # ไฟล์ไม่ถูกแก้
npx @aeterna_game/fivem-devkit safety ./nakara_cargen_fix      # สแกนเอง
```

แล้วอ่านตาราง **Capabilities** ของ package นั้น (มาจาก `oss.json`): บอกทุก HTTP host, command,
convar, net event, ตาราง database และไฟล์ที่ resource แตะได้ ถ้าโค้ดใช้อะไรที่ไม่อยู่ในตาราง
`fivem-devkit safety` ใน CI ของเราจะล้ม และการสแกนของคุณเองก็จะล้มเหมือนกัน

## สิ่งที่ scanner จับไม่ได้

scanner บอกได้ว่าโค้ดใช้แค่สิ่งที่ประกาศไว้ แต่ตัดสินไม่ได้ว่าใช้อย่างสุจริตหรือเปล่า:

- logic bomb ที่ซ่อนใน API ที่ resource ได้รับอนุญาต
- การเรียก export ของ resource อื่น
- server event ที่เชื่อข้อมูลจาก client
- ค่าที่ประกอบขึ้นตอน runtime รายงานได้ แต่ไม่ได้ตามต่อ

ยังต้องมีคนอ่านโค้ด รายละเอียด: [safety.md](packages/devkit/docs/safety.md#what-it-can-not-catch--human-review-stays-required)

## ร่วมพัฒนา

ส่ง PR ได้เลย อ่าน [CONTRIBUTING.md](CONTRIBUTING.md) ก่อน (DCO sign-off และวิธี review)
ช่องโหว่ความปลอดภัย: [SECURITY.md](SECURITY.md) ห้ามเปิด issue สาธารณะ

## สัญญาอนุญาต

[MIT](LICENSE)
