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
- **Bar style (รูปแบบแถบ, 0.2):** Each player picks bars or rings (circular gauges) for the status bars, extra bars and fuel.
- **Compass tape (เข็มทิศแบบแถบ, 0.2):** A tape centred on the camera heading at the top centre, with a tick every 15°, the eight direction labels and the heading in whole degrees.
- **Voice indicator (สถานะเสียงพูด, 0.2):** Shown only while `pma-voice` is started (detected at run time, never a dependency): microphone lit while talking, the proximity mode, and a radio icon on a channel, highlighted while transmitting.
- **Seatbelt icon (ไอคอนเข็มขัดนิรภัย, 0.2):** Shows a state another resource sets through a local event. hudkit has no seatbelt system of its own.

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
| `Config.barStyle` | `'bar'` | Default bar style (`bar` or `ring`) for players who have not picked one / รูปแบบแถบเริ่มต้น |
| `Config.compass.enabled` | `true` | Register the `compass` element; `false` = no tape compass (the 0.1 screen) / เปิดเข็มทิศแบบแถบ |
| `Config.compass.span` | `120` | Degrees visible on the tape, clamped to 60–180 / องศาที่มองเห็นบนแถบ |
| `Config.voice.enabled` | `true` | Show the voice indicator while `pma-voice` is started; `false` = never / แสดงสถานะเสียงพูด |
| `Config.seatbelt.enabled` | `true` | Show the seatbelt icon once a resource has set a state; `false` = never / แสดงไอคอนเข็มขัด |

Shared convars read via `aeterna_core`: `aeterna_locale` (`en` or `th`, set with `setr`), `aeterna_theme` (`nui://<resource>/<path>.css`, set with `setr`).

## Parts and Layout / การเชื่อมโยงเลย์เอาต์

Each part is registered with `aeterna_layout` as an element:

| `id` | Shows | Default position | `hideable` |
|---|---|---|---|
| `status` | Health, armour, needs, and external bars | Bottom-left (right of minimap) | `true` |
| `vehicle` | Speed, fuel, gear | Bottom-right | `true` |
| `street` | Street name, zone, compass heading | Bottom-centre | `true` |
| `minimap` | Base game radar | Bottom-left (game default) | `false` (use minimap mode) |
| `compass` | Tape compass and heading in degrees (0.2) | Top-centre | `true` |
| `voice` | Microphone, proximity mode, radio (0.2, only while `pma-voice` is started) | Above `status` | `true` |

**Upgrade note (0.2):** servers that upgrade see a new `compass` element at the top centre. Set `Config.compass.enabled = false` to keep the 0.1 screen. Hide the compass, voice or street part per player in the layout editor.
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

## Seatbelt state / สถานะเข็มขัดนิรภัย (0.2)

A seatbelt resource fires this client-local event when the state changes and when the player enters a vehicle:

```lua
TriggerEvent('aeterna_hudkit:seatbelt', { on = true })  -- fastened
TriggerEvent('aeterna_hudkit:seatbelt', { on = false }) -- unfastened (shown in --bad)
TriggerEvent('aeterna_hudkit:seatbelt', nil)            -- hide the icon
```

The icon shows in the `vehicle` part only while the player is in a vehicle. The last resource that fired the event owns the state (taken from the invoking resource, never from the payload); only that resource can hide it with `nil`, and when it stops, the icon is hidden. hudkit never blocks leaving a vehicle and never adds ejection.

## Voice indicator / สถานะเสียงพูด (0.2)

hudkit checks `GetResourceState('pma-voice')` on start, whenever `pma-voice` starts or stops, and once a second. It never lists `pma-voice` as a dependency and never calls its exports. It reads:

| Value | Source |
|---|---|
| Talking | `NetworkIsPlayerTalking(PlayerId())` |
| Proximity mode | state bag `proximity` = `{ index, distance, mode }`; index 1–3 shows Whisper / Normal / Shout, any other shows the distance in metres |
| On a radio channel | state bag `radioChannel` (a number above 0) |
| Transmitting | the local event `pma-voice:radioActive` |

A missing value hides its part of the indicator.

## Self-tests / การทดสอบตัวเอง (0.2)

hudkit registers these tests with `aeterna_core` on start (`aeterna_testkit` lists and runs them). A test reports SKIP
only for the reason in the last column; a ped or eye test with nobody to run it is GAP.

Every client row except `bar_style` carries a short instruction as `expect` ("Talk into your microphone, then change your voice range"; `compass_tape` and `minimap_follows`: "Keep still while the test moves the camera and radar"); `aeterna_testkit` shows it while the row runs.

Self-test events are accepted only from `aeterna_core` (the invoking resource), so no other resource can start a test or its server preparation.

| Test | Kind | Runs | What it checks | SKIP when |
|---|---|---|---|---|
| `aeterna_hudkit.values_mapping` | headless | server | Health 100–200 → 0–100 %, km/h and mph, gear text, heading sectors, identical values send nothing | never |
| `aeterna_hudkit.compass_math` | headless | server | Tape offsets with the 360° wrap, span clamp 60–180, direction labels | never |
| `aeterna_hudkit.bar_style` | eye | presser | Shows Bar, then Ring (not saved); the tester confirms every status bar is a ring. The player's own style comes back when the test ends | — |
| `aeterna_hudkit.compass_tape` | ped | presser | Turns the camera a full circle in 30° steps; the degree sent to the page follows the camera and N sits on the centre mark facing north; the camera turns back | `Config.compass.enabled = false` |
| `aeterna_hudkit.voice_indicator` | ped | presser | Within 25 s the presser talks and changes proximity mode: the microphone lights and the mode label changes | `pma-voice` not started, or `Config.voice.enabled = false` |
| `aeterna_hudkit.voice_radio` | ped | presser | Within 25 s the presser joins a radio channel and transmits: the radio icon shows and is highlighted | `pma-voice` not started, or `Config.voice.enabled = false` |
| `aeterna_hudkit.seatbelt_event` | mock | presser | Waits up to 20 s for the presser to sit in a vehicle, then fires `true`, `false`, `nil` through `aeterna_hudkit:seatbelt` and checks the icon state hudkit's own handler sent to the page, then puts the previous state and owner back | `Config.seatbelt.enabled = false`, or the presser is not in a vehicle after 20 s |
| `aeterna_hudkit.minimap_follows` | ped | presser | Moves the radar to the top-right and back; at each place its corner is under the stand-in and the mask and blur line up | — |

## Commands and keys / คำสั่งและปุ่มลัด

- `aeterna_hudkit_settings` — Open HUD settings panel (chat or F8 console)
- `+aeterna_hudkit_settings` / `-aeterna_hudkit_settings` — Key mapping (no default key, bind in Settings → Key Bindings → FiveM)

Settings (show numbers, speed unit, minimap mode, bar style) persist locally in client KVP under `aeterna_hudkit:settings:v1`. A value saved by 0.1 has no bar style and reads as `Config.barStyle`.

## Support scope / ขอบเขตการรองรับ

- **Tested on / ทดสอบบน:** FXServer Enhanced & Legacy (cerulean, Lua 5.4), standalone with `aeterna_core`, `aeterna_uikit` and `aeterna_layout`, alongside `qbx_core` 1.23 and `ox_lib` 3.x.
- **Supported / รองรับ:** Standalone FiveM servers and Qbox/QBCore/ESX servers running `aeterna_core`, custom CSS theme overrides via `setr aeterna_theme`, and Thai/English locales.
- **Not supported / ไม่รองรับ:** Round minimaps (requires a streamed mask texture; planned for 0.3), a seatbelt system of its own (hudkit only shows a state other resources set), engine damage, weapon display, voice indicators for voice resources other than `pma-voice`. On FiveM Enhanced (no Mumble) whether the proximity mode and radio parts still mean anything is not verified yet; talking still shows.

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
