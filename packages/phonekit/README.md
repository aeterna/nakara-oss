# aeterna_phonekit

A modular phone shell with built-in utility apps, client KVP storage, and an app API for the AETERNA Starter Kit ([ADR 0004](../../docs/adr/0004-aeterna-starter-kit.md) · [spec](../../docs/specs/aeterna_phonekit.md)).

ระบบโทรศัพท์พื้นฐานสำหรับเซิร์ฟเวอร์ FiveM ในชุด AETERNA Starter Kit มาพร้อมหน้าจอหลัก, แถบสถานะ, แอปพลิเคชันพื้นฐานในเครื่อง 4 ตัว (เครื่องคิดเลข, บันทึกข้อความ, รายชื่อผู้ติดต่อ, การตั้งค่า) และ App API สำหรับให้นักพัฒนาสร้างแอปพลิเคชันเพิ่มเติมลงในโทรศัพท์โดยไม่ต้องแก้ไขโค้ดของโทรศัพท์

---

## What it does / การทำงาน

- **Phone models (รุ่นโทรศัพท์, 0.2):** Eight models with their own frame and case colours: `keypad` 300 × 660, `burner` 300 × 660, `qwerty` 392 × 760, `slab` 392 × 812 (default), `fold` 380 × 842 open / 380 × 430 closed, `pro` 392 × 812, `book` 380 × 812 closed / 780 × 700 open, `pad` 600 × 812. The frame is scaled to fit the screen, then by the layout scale, so it never clips.
- **Status Bar & Clock (แถบสถานะ):** Shows the current time from `AeternaCore.time` (using the server's `aeterna_timezone`), formatted in 24-hour or 12-hour mode, a live pill set by an add-on, and the battery the server counts (0.2). No signal bars.
- **Lock screen, control centre, cover screen (0.2):** The lock screen (`Config.lockScreen`) shows when something is waiting; swipe up or OK unlocks. Pull down from the status bar for the control centre (text size, 24-hour clock, layout, carried phones in item mode, notification history from `aeterna_notify`). A closed `fold` shows a cover screen with time, battery, waiting items and an incoming ring.
- **Two panes (0.2):** On an open `book`, a panel spec with `detailOf` keeps the list on the left and draws the detail on the right. Folding changes the layout only; the screen, its scroll and typed text stay.
- **Home & Navigation (หน้าจอหลักและการควบคุม):** Grid of app tiles sorted by `order` then `id`, with optional badge counters (0–99, or `99+`). Back navigation via bottom home bar, Backspace, or right mouse button (RMB); ESC closes the phone from any screen.
- **Walking while open (เดินขณะเปิดใช้งาน):** Takes focus through `aeterna_core` with `keepGameInput = true` so the player can walk while the phone is open; mouse look is disabled while hovering over the frame.
- **Animation & Prop (ท่าทางและอุปกรณ์):** With `Config.animation = true`, the ped holds a phone prop and plays the base-game phone animation. Automatically closes and stops animation if the ped dies, ragdolls, or enters water.
- **Built-in Apps (แอปพลิเคชันพื้นฐานในเครื่อง):** Four standalone client apps storing data locally on the player's machine (ADR 0004 decision 8):
  - **Calculator (เครื่องคิดเลข):** Basic operations (+, -, *, /), percent, sign toggle, clear; operator order as typed (no precedence, like a phone calculator), divide-by-zero error handling, and numbers rounded to 10 significant digits.
  - **Notes (บันทึกข้อความ):** Up to 50 notes, title ≤ 60 chars, body ≤ 2000 chars, stored in client KVP `aeterna_phonekit:notes:v1`.
  - **Contacts (รายชื่อผู้ติดต่อ):** Up to 100 contacts, name ≤ 40 chars, number ≤ 20 chars, stored in client KVP `aeterna_phonekit:contacts:v1`.
  - **Settings (การตั้งค่า):** Text size (Normal / Large), 24-hour clock toggle, and "Edit layout" trigger when `aeterna_layout` runs. Stored in client KVP `aeterna_phonekit:settings:v1`.
- **App API for other resources (ระบบเชื่อมต่อแอปภายนอก):** Resources register app tiles and render server-owned UI screens using `aeterna_uikit` panel specs inside the phone frame without writing custom HTML.
- **Opening Check (ระบบตรวจสอบสิทธิ์ก่อนเปิด):** When `Config.ask = true`, the server fires `aeterna_phonekit:asking` and allows other resources (e.g. item checks) to allow or deny opening within 1000 ms.
- **Optional `aeterna_layout` integration (รองรับการจัดวางผ่าน `aeterna_layout`):** Registers element `phone` (the held model's frame size, `scalable = true`, `hideable = false`) through local client events, allowing players to drag and scale the phone across the screen. 0.2: the element is re-added with the new size on a model switch, fold or unfold; without layout 0.2 phonekit keeps the frame inside the viewport itself and saves nothing.

### Device modes and battery (0.2) / โหมดอุปกรณ์และแบตเตอรี่

- `Config.devices = 'single'`: every player holds one phone of `Config.singleModel`; battery and fold live in server resource KVP `aeterna_phonekit:device:v1:<who>` (`cid:<character id>` with `qbx_core`, else `lic:<license>`).
- `Config.devices = 'items'`: the phone is an inventory item. Phonekit never touches an inventory; the resource that owns the items (for example `aeterna_invkit`) answers the open gate with the phones the player carries and stores battery and fold in item metadata when phonekit fires `aeterna_phonekit:deviceSave`. Item definitions and images are added by the server owner in the inventory (see `aeterna_invkit`'s README). With `aeterna_invkit`, turn on both settings together: `Config.devices = 'items'` here and `Config.phone.enabled = true` in invkit; with only one of them on, players get no phone (`Config.ask = true` treats no answer as refused).
- The server counts the battery: standby drain, more while a screen is on, a call or a camera is up, divided by the model's multiplier; charging in a vehicle or from chargers other resources add. At 0 % every phone surface closes and opening is refused until it is charged.

### Deliberate limits in v0.1 / ขอบเขตที่ยังไม่รวมใน v0.1

No voice/calls, no player-to-player messaging, no camera or photo gallery, no banking, no social feeds, and no SIM/numbering plans. Servers implement these as external apps through the App API.

---

## Install / การติดตั้ง

1. Ensure dependencies start before `aeterna_phonekit`:

```cfg
ensure aeterna_core
ensure aeterna_uikit
ensure aeterna_notify
ensure aeterna_phonekit
```

2. Configure opening behavior and apps in `config.lua` if desired.

---

## Configuration / การตั้งค่า

`config.lua`:

| Key | Default | Meaning / ความหมาย |
|---|---|---|
| `Config.position` | `'bottom-right'` | Screen position: `'bottom-right'` or `'bottom-left'` (24 px inset) / ตำแหน่งเริ่มต้นบนหน้าจอ |
| `Config.ask` | `false` | When `true`, asks external resources before opening / สอบถามสิทธิ์จากรีซอร์สอื่นก่อนเปิด |
| `Config.animation` | `true` | Hold phone prop with base animation while open / ถือโทรศัพท์และเล่นแอนิเมชัน |
| `Config.apps` | `{ calculator = true, notes = true, contacts = true, settings = true }` | Built-in apps to show on the home screen / เปิดหรือปิดแอปพื้นฐาน |
| `Config.maxApps` | `24` | Maximum external apps from other resources / จำนวนแอปภายนอกสูงสุดที่ลงทะเบียนได้ |
| `Config.devices` | `'single'` | `'single'` or `'items'` (0.2) / โหมดอุปกรณ์ |
| `Config.singleModel` | `'slab'` | Model in `single` mode / รุ่นที่ทุกคนถือในโหมด single |
| `Config.names` | `'neutral'` | `'neutral'` or `'universe'` display names / ชุดชื่อรุ่น |
| `Config.models` | `{ burner = { apps = '*,-contacts' } }` | Per model: `label` (≤ 24), `apps` (app spec), `colors` (hex list), `prop` / ตั้งค่ารายรุ่น |
| `Config.prop` | `'prop_npc_phone_02'` | The held prop / อุปกรณ์ที่ถือ |
| `Config.battery` | table | `tickSec` 10, `standby` 0.25, `screen` 1.0, `call` 1.5, `media` 2.5 (%/min), `vehicleSec` 300, `warnAt` `{ 20, 10, 5 }`, `saveStep` 5, `pulseTtlSec` 45, `startPct` 100; `false` turns the battery off / แบตเตอรี่ |
| `Config.lockScreen` | `false` | Lock screen when something is waiting / หน้าจอล็อก |
| `Config.cover` | `true` | `false`: a `fold` never closes / ปิดฝาพับได้หรือไม่ |

App spec (`Config.models[m].apps`): comma-separated tokens, `*` = every app, `-x` removes `x`, anything else adds it; built-in ids (`calculator`, `notes`, `contacts`, `settings`) or `<owner>:<id>`. `settings` is always kept.

**Upgrade from 0.1:** a layout scale saved in 0.1 was chosen for a 320 × 640 frame. The same scale now applies to the larger frame, capped so it stays on screen; players who want the old size set the scale again in the layout editor (about 0.8 of the old value).

---

## App API (Server Exports) / การเรียกใช้งานสำหรับนักพัฒนา

| Export | Arguments | Description / คำอธิบาย |
|---|---|---|
| `addTile(app)` | `app = { id, label, icon, order?, ace?, needs?, handles? }` | Registers an app tile on the home screen. `id` ≤ 32, `label` ≤ 24, `icon` from uikit icon names. 0.2: `needs = 'voice'` hides it on models without calls; `handles = { 'tel', 'sms' }` makes it the target of a contact's Call / Message. Removed automatically when the owner resource stops. |
| `removeTile(id)` | `id` | Removes an app tile registered by the calling resource. |
| `showApp(src, id, spec)` | `src, id, spec` | Draws a uikit panel spec inside the phone frame for app `id`. Returns `screenId` or `nil, err`. |
| `updateApp(src, screenId, patch)` | `src, screenId, patch` | Updates the active spec screen with partial block patches. |
| `badge(src, id, count)` | `src, id, count` | Sets the badge counter on an app tile (clamped to 0–99). |
| `notifyApp(src, id, opts)` | `src, id, { title, body }` | Phone open: displays an in-phone banner. Phone closed: displays an `aeterna_notify` toast. Adds 1 to the app badge unless the app is currently on screen. |
| `listenOpen()` | — | Registers the calling resource as a listener for `Config.ask` checks. |
| `allowOpen(checkId, answer?)` | `checkId, answer?` | Answers an opening check with permission to open. 0.2: `answer = { allow = true, devices = { { id, model, battery?, fold?, color? } } }` (item mode). |
| `denyOpen(checkId, reasonKey?)` | `checkId, reasonKey?` | Denies opening with an optional locale refusal key. |

### 0.2 exports

| Export (server) | Description |
| --- | --- |
| `device(src)` | `{ model, id, label, voice, fold, battery }` of the active phone, or `nil` |
| `refreshDevices(src)` | Asks the item gate again |
| `battery(src)` · `setBattery(src, pct)` · `charge(src, pct)` | Shown value 0–100 (or `nil`), set it, add to it |
| `setCharger(src, id, secToFull \| false)` | A charger from the calling resource; the fastest wins |
| `activity(src, 'call', on)` | A connected call drains more |
| `ring(src, id, { title, body })` · `stopRing(src, ringId)` | Incoming card with Answer / Decline (`__answer` / `__decline` actions) |
| `live(src, { id, text } \| nil)` | A pill in the status bar |
| `canCall(src)` | `false` for `pad`, no phone or a dead battery |

| Export (client) | Description |
| --- | --- |
| `activity('media', on)` | A camera viewfinder drains more |
| `isOpen()` | Whether any phonekit surface is on screen |
| `getContacts()` · `addContact({ name, number })` | The built-in contact list; `aeterna_phonekit:contactsChanged` fires after a change |

Server-local events (0.2): `aeterna_phonekit:hello`, `:listen`, `:answer`, `:devicesChanged`, `:deviceSave`, `:power`; `aeterna_phonekit:asking` carries `devices = 'single' | 'items'`; `aeterna_phonekit:app` may carry `intent = { kind, number }`.

### Event Flow

1. Player taps a tile -> server checks `app.ace` -> fires `aeterna_phonekit:app` -> `(src, { owner, id })`.
2. The owner answers with `exports.aeterna_phonekit:showApp(src, id, spec)`.
3. Player clicks a button or list item -> server validates action & form values -> fires `aeterna_phonekit:action` -> `(src, { owner, id, screenId, action, values })`.
4. Back button from the root of an app fires `aeterna_phonekit:action` with `action = '__close'` and returns to the home screen.

---

## Commands and keys / คำสั่งและปุ่มลัด

- `aeterna_phonekit_open` — Console / chat command to toggle the phone.
- `+aeterna_phonekit_open` / `-aeterna_phonekit_open` — Key mapping registered via `AeternaCore.key` (no default key bound, bind in Settings -> Key Bindings -> FiveM).
- `aeterna_phonekit_fold`, `+aeterna_phonekit_fold` / `-aeterna_phonekit_fold` (0.2) — fold or unfold a `fold` or `book` while it is open (no default key).
- Backspace or Right Mouse Button (RMB) returns to the previous screen (control centre open: closes it).
- ESC closes the phone from every screen. The key bound to the open mapping also puts the phone away (an F-key works while typing).

---

## Capabilities

What this resource is allowed to do to your server, from [`oss.json`](oss.json):

| Capability | Declared |
|---|---|
| HTTP requests | none |
| `ExecuteCommand` | none |
| Registered commands | `aeterna_phonekit_open`, `+aeterna_phonekit_open`, `-aeterna_phonekit_open`, `aeterna_phonekit_fold`, `+aeterna_phonekit_fold`, `-aeterna_phonekit_fold` |
| Convars read | none |
| Convars written | none |
| Server net events (accepted from clients) | `aeterna_phonekit:sv:open`, `aeterna_phonekit:sv:close`, `aeterna_phonekit:sv:tap`, `aeterna_phonekit:sv:action`, `aeterna_phonekit:sv:screen`, `aeterna_phonekit:sv:fold`, `aeterna_phonekit:sv:device`, `aeterna_phonekit:sv:ring`, `aeterna_phonekit:sv:battery` |
| Client net events (accepted from the server) | `aeterna_phonekit:cl:open`, `aeterna_phonekit:cl:screen`, `aeterna_phonekit:cl:update`, `aeterna_phonekit:cl:badge`, `aeterna_phonekit:cl:banner`, `aeterna_phonekit:cl:refused`, `aeterna_phonekit:cl:device`, `aeterna_phonekit:cl:battery`, `aeterna_phonekit:cl:power`, `aeterna_phonekit:cl:ring`, `aeterna_phonekit:cl:ringStop`, `aeterna_phonekit:cl:live` |
| NUI | yes |
| Database tables | none (no DDL) |
| Files written | none |

---

## Support scope / ขอบเขตการรองรับ

- **Tested on / ทดสอบบน:** FXServer Enhanced & Legacy (cerulean, Lua 5.4), standalone with `aeterna_core`, `aeterna_uikit`, and `aeterna_notify`.
- **Supported / รองรับ:** Standalone FiveM servers, optional draggable/scalable positioning with `aeterna_layout`, client KVP persistence, custom CSS theme overrides via `setr aeterna_theme`, and Thai/English locales.
- **Not supported / ไม่รองรับ:** Voice or call streaming, server-side SMS databases, or execution without `aeterna_core`.

---

## Verify before you install

Every release zip is built in CI and carries a build-provenance attestation:

```sh
gh attestation verify aeterna_phonekit-<version>.zip --repo aeterna/nakara-oss --signer-workflow aeterna/nakara-oss/.github/workflows/release.yml
sha256sum -c SHA256SUMS --ignore-missing
```

---

## Self-tests / การทดสอบตัวเอง

Registered with `aeterna_core` on start; `aeterna_testkit` runs them from its menu ([spec § Self-tests (0.2)](../../docs/specs/aeterna_phonekit.md#self-tests-02)). A row whose condition does not hold reports SKIP with the reason in the last column. Destructive rows run only when `aeterna_core_allow_destructive` is on and the server is not listed publicly.
ลงทะเบียนกับ `aeterna_core` ตอนเริ่ม และกดทดสอบได้จากเมนูของ `aeterna_testkit` แถวที่เงื่อนไขไม่ตรงจะรายงาน SKIP พร้อมเหตุผล

| Name | Kind | Destructive | Checks | Skip when |
|---|---|---|---|---|
| `rules_loaded` | headless | n | Device mode, `Config.singleModel`, the eight models and the battery config loaded | never |
| `models_have_apps` | headless | n | Every model has a label and draws its built-in apps (settings always) | never |
| `battery_drain_tick` | headless | n | One minute on a fake in-memory slab with the screen on drains `standby + screen` | `Config.battery = false` |
| `battery_zero_closes_all` | mock | y | Sets the presser's battery to 0 (saved): power off, no device, no app screen, phone closed; then sets and saves the old value | `Config.battery = false`, no presser |
| `battery_kvp_roundtrip` | mock | y | Writes the presser's device KVP and reads it back, then writes the old value back | `Config.devices = 'items'`, no presser |
| `stale_pulse_is_off` | headless | n | A screen pulse older than `pulseTtlSec` drains like the screen off | `Config.battery = false` |
| `gate_items_silence_denies` | mock | n | A made-up items check nobody answers is denied with `phonekit.refused.nodevice` (the live gate is untouched) | `Config.devices = 'single'` |
| `open_close_prop` | ped | n | Opening attaches the prop to the ped (none with `Config.animation = false`); closing removes it | presser not spawned |
| `fold_keeps_screen` | ped | n | An app screen stays on top after fold and unfold | held model does not fold |
| `clamp_on_unfold` | ped | n | The opened book frame stays inside the viewport | held model is not `book` |
| `exit_contract` | ped | n | ESC closes, an open within 300 ms of the close is ignored, the bound open key closes | never |
| `eye_model_<id>` (8) | eye | n | The person checks each model's frame, status bar and home | never |
| `eye_book_two_pane` | eye | n | Book opened wide: list left, detail right | never |
| `eye_fold_cover` | eye | n | Fold closed: the cover screen | never |
| `eye_lock` | eye | n | The lock screen with one test card | `Config.lockScreen = false` |
| `eye_control_centre` | eye | n | The control centre (opened by the test) | never |
| `ring_cover` | eye | n | Fold closed: a test call card with Answer and Decline on the cover | held model is not `fold`, or `Config.cover = false` |
| `contacts_hooks` | mock, client | n | `addContact` adds, `getContacts` lists it, `contactsChanged` fires once; the list is put back | no presser (GAP) |

How the client rows work: they open the phone the normal way (open gate, focus), so a phone that cannot open (no phone item, a dead battery) fails the row with the refusal. To show another model or a fold they change the page only: nothing is sent to the server and nothing is saved, and the held phone comes back when `aeterna_core` ends the test. The test screens and the test call card exist only on the page; answering the test call card stops it locally. The eye cards are look-only: the card holds the cursor, so the test opens the control centre and unfolds the book itself.

Not registered: `eye_battery_dead`. It is a client eye test that must set the battery to 0 on the server, and a client has no way to make the server do that (the battery is server-owned and no net event may lower or raise it). `battery_zero_closes_all` covers the server half.

## Tests

From the repository root:

```sh
busted --lpath='./packages/devkit/busted/?.lua;./?.lua;./?/init.lua' --pattern=_spec packages/phonekit/spec
```

---

## License

MIT. See [LICENSE](../../LICENSE). Bundled Lucide icon SVGs are ISC-licensed; see [NOTICE](NOTICE).
