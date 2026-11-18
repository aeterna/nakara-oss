# aeterna_hudkit

Player HUD (status bars, vehicle cluster, street/compass, and game minimap integration) for the AETERNA Starter Kit ([ADR 0004](../../docs/adr/0004-aeterna-starter-kit.md) · [spec](../../docs/specs/aeterna_hudkit.md)).

ระบบแสดงผลหน้าจอผู้เล่น (HUD) สำหรับเซิร์ฟเวอร์ FiveM ในชุด AETERNA Starter Kit ประกอบด้วยแถบสถานะ แผงหน้าปัดยานพาหนะ ตำแหน่งถนนพร้อมเข็มทิศ และการเชื่อมโยงแผนที่ย่อของตัวเกม โดยทุกส่วนเชื่อมโยงกับระบบจัดวางเลย์เอาต์ `aeterna_layout` เพื่อให้ผู้เล่นสามารถปรับย้ายตำแหน่งได้อย่างอิสระ

---

## What it does / การทำงาน

- **Status bars (แถบสถานะ):** Health (mapped 100–200 → 0–100 % using `--accent`), armour, and configurable need bars (hunger, thirst, stress via player state bags `LocalPlayer.state[key]`). Bars turn `--bad` when at or below `Config.low` (default 20%).
- **Vehicle cluster (แผงยานพาหนะ):** Speed in km/h or mph (rounded to whole figures), fuel level bar, and gear indicator (`R`, `N`, `1`–`8`); visible only while driving.
- **Street & compass (ชื่อถนนและเข็มทิศ):** Current street and zone name with an 8-direction compass heading (`N`, `NE`, `E`, `SE`, `S`, `SW`, `W`, `NW`).
- **Minimap integration (แผนที่ย่อ):** The base game radar moves together with `aeterna_layout` using native component positioning (`SetMinimapComponentPosition`), tested in Spike S3. Modes: `always`, `vehicle` (shown only in vehicle), or `never`.
- **Custom bars API (เพิ่มแถบสถานะจากสคริปต์อื่น):** External resources can push custom status bars (up to 8) via client-local events without modifying `aeterna_hudkit`.
- **In-game settings (เมนูตั้งค่า):** Built-in settings card accessible from the `aeterna_uikit` menu or console command (`aeterna_hudkit_settings`), with focus managed by `aeterna_core`.

## Install / การติดตั้ง

1. Download `aeterna_hudkit-<version>.zip` from the [Releases](https://github.com/aeterna/nakara-oss/releases) page.
2. Extract into your `resources/` folder so you have `resources/aeterna_hudkit/fxmanifest.lua`.
3. Add to your `server.cfg`:

```cfg
ensure aeterna_core
ensure aeterna_uikit
ensure aeterna_layout
ensure aeterna_hudkit
```

## Config / การตั้งค่า

Configured in `config.lua` (no convars):

| Key | Default | Meaning / ความหมาย |
|---|---|---|
| `Config.tick` | `200` | ms between reads of player/vehicle values (NUI updated only on change) / ระยะเวลาอ่านค่า (ms) |
| `Config.low` | `20` | Percentage at or below which bars turn `--bad` / ระดับเปอร์เซ็นต์เตือนวิกฤต |
| `Config.needs` | `{ 'hunger', 'thirst', 'stress' }` | State bag keys read as 0–100 bars / คีย์ state bag สำหรับอ่านค่าความต้องการ |
| `Config.speedUnit` | `'kmh'` | Default speed unit (`kmh` or `mph`) / หน่วยความเร็วเริ่มต้น |
| `Config.minimap.mode` | `'always'` | Default minimap mode: `always`, `vehicle`, or `never` / โหมดแผนที่ย่อเริ่มต้น |
| `Config.hideBaseBars` | `true` | Hides base game health/armour under minimap / ซ่อนแถบเลือดเดิมใต้แผนที่ย่อ |

Shared convars read via `aeterna_core`: `aeterna_locale` (`en` or `th`, set with `setr`), `aeterna_theme` (`nui://<resource>/<path>.css`, set with `setr`).

## Parts and Layout / การเชื่อมโยงเลย์เอาต์

Each part is registered with `aeterna_layout` as an element:

| `id` | Shows | Default position | `hideable` |
|---|---|---|---|
| `status` | Health, armour, needs, and external bars | Bottom-left (right of minimap) | `true` |
| `vehicle` | Speed, fuel, gear | Bottom-right | `true` |
| `street` | Street name, zone, compass heading | Bottom-centre | `true` |
| `minimap` | Base game radar | Bottom-left (game default) | `false` (use minimap mode) |

## External bars API / การส่งแถบสถานะจากทรัพยากรภายนอก

Other resources can register extra bars in the `status` cluster using client-local events:

```lua
-- Add or update a bar
TriggerEvent('aeterna_hudkit:bar', {
    id = 'stamina',           -- string <= 32 matching ^[%w_%-]+$
    label = 'Stamina',        -- locale key or string <= 24
    icon = 'activity',        -- icon name from Lucide icon map
    value = 85,               -- 0–100, or nil to hide for now
    order = 10,               -- optional sort order (default 100)
})

-- Remove a bar
TriggerEvent('aeterna_hudkit:removeBar', 'stamina')
```

At most 8 extra bars can be active at once; any 9th bar is refused with a warning. When an external resource stops, its bars are automatically cleaned up.

## Commands and keys / คำสั่งและปุ่มลัด

- `aeterna_hudkit_settings` — Open HUD settings panel (chat or F8 console)
- `+aeterna_hudkit_settings` / `-aeterna_hudkit_settings` — Key mapping (no default key, bind in Settings → Key Bindings → FiveM)

Settings persist locally in client KVP under `aeterna_hudkit:settings:v1`.

## Support scope / ขอบเขตการรองรับ

- **Tested on / ทดสอบบน:** FXServer Enhanced & Legacy (cerulean, Lua 5.4), standalone with `aeterna_core`, `aeterna_uikit` and `aeterna_layout`, alongside `qbx_core` 1.23 and `ox_lib` 3.x.
- **Supported / รองรับ:** Standalone FiveM servers and Qbox/QBCore/ESX servers running `aeterna_core`, custom CSS theme overrides via `setr aeterna_theme`, and Thai/English locales.
- **Not supported / ไม่รองรับ:** Round minimaps (requires custom streaming textures), seatbelt or engine damage indicators (not in v0.1 scope), voice indicators without a designated voice provider.

## Capabilities

What this resource is allowed to do to your server, from [`oss.json`](oss.json):

| Capability | Declared |
|---|---|
| HTTP requests | None |
| Commands executed | `aeterna_layout` |
| Registered commands | `aeterna_hudkit_settings`, `+aeterna_hudkit_settings`, `-aeterna_hudkit_settings` |
| Convars read/write | None |
| Net events (client) | `aeterna_hudkit:cl:settings` |
| Net events (server) | None |
| NUI | Enabled (`ui_page 'html/index.html'`) |
| Database | None |
| Files written | None |
