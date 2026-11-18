# aeterna_notify

Toast notifications, server-wide announcement banners, and a once-per-version message of the day (MOTD) card for the AETERNA Starter Kit ([ADR 0004](../../docs/adr/0004-aeterna-starter-kit.md) · [spec](../../docs/specs/aeterna_notify.md)).

ระบบแจ้งเตือนสำหรับเซิร์ฟเวอร์ FiveM ในชุด AETERNA Starter Kit ประกอบด้วยการแจ้งเตือนรายบุคคล (Toasts), แบนเนอร์ประกาศทั่วเซิร์ฟเวอร์ (Announcements) และการ์ดข้อความต้อนรับประจำวัน (MOTD) ที่แสดงครั้งเดียวต่อเวอร์ชันหลังผู้เล่นเกิด

---

## What it does / การทำงาน

- **Toasts (การแจ้งเตือนรายบุคคล):** Displays up to `Config.toast.max` (default `4`) toasts in any screen corner (`top-left`, `top-right`, `bottom-left`, `bottom-right`). Calling `notify` with an `id` already on screen replaces that toast in place and restarts its timer without jumping. Uses the same field names as `ox_lib`'s `lib.notify`.
- **Announcements (ประกาศทั่วเซิร์ฟเวอร์):** Shows one top-centre banner at a time across all connected players, queuing up to `Config.announce.queue` (default `5`) announcements behind the current one and dropping overflow with a warning. Triggered from server exports or the ACE-checked `aeterna_announce` command.
- **MOTD (ข้อความต้อนรับประจำวัน):** Configured in `config/motd.json` and shown once per `version` after spawn (`playerSpawned`, or `QBCore:Client:OnPlayerLoaded` when `qbx_core` is started, or via the `showMotd()` client export). "Don't show again" saves `version` to client KVP `aeterna_notify:motd_seen:v1`; "Continue" or ESC closes it for the current session. Coordinates NUI focus through `aeterna_core`.
- **Optional `aeterna_layout` integration (รองรับการจัดวางผ่าน `aeterna_layout`):** Registers `toasts` and `announce` through local client events (`aeterna_layout:add`, `aeterna_layout:hello`, `aeterna_layout:apply`) with no hard dependency, so players can drag and scale both elements when `aeterna_layout` is running.
- **Deliberate limits (ขอบเขตที่จำกัดไว้):** No sound effects, no phone notifications (handled by `aeterna_phonekit`), no Discord relays, and no scheduled announcements in v0.1.

## Install / การติดตั้ง

1. Download `aeterna_notify-<version>.zip` from the [Releases](https://github.com/aeterna/nakara-oss/releases) page and verify it (see below).
2. Extract it into your `resources/` folder so you have `resources/aeterna_notify/fxmanifest.lua`.
3. Ensure `aeterna_core` starts before `aeterna_notify` and grant the announcement ACE permission to admins in `server.cfg`:

   ```cfg
   ensure aeterna_core
   ensure aeterna_notify
   add_ace group.admin aeterna.notify.announce allow
   ```

## Config / การตั้งค่า

### `config.lua`

| Key | Default | Meaning / ความหมาย |
|---|---|---|
| `Config.toast.position` | `'top-left'` | `top-left` · `top-right` · `bottom-left` · `bottom-right` (24 px inset) / มุมหน้าจอที่แสดง Toast |
| `Config.toast.max` | `4` | Maximum visible toasts; older ones leave first / จำนวน Toast สูงสุดที่แสดงพร้อมกัน |
| `Config.toast.defaultDuration` | `4000` | Default toast duration in ms (`1000–15000`) / ระยะเวลาแสดงผลเริ่มต้น (มิลลิวินาที) |
| `Config.announce.queue` | `5` | Announcements waiting behind the current one; more are dropped with a `warn` / จำนวนคิวประกาศที่รอได้สูงสุด |
| `Config.motd.enabled` | `true` | Enable or disable the MOTD card / เปิดหรือปิดการแสดงการ์ด MOTD |

### `config/motd.json`

```json
{
  "version": "2026-11-17",
  "eyebrow": "Message of the day",
  "title": "Welcome",
  "lines": [
    "Bind your phone key in Settings → Key Bindings → FiveM"
  ],
  "buttons": {
    "dismiss": true
  }
}
```

Limits: `version` ≤ 40, `eyebrow` ≤ 60, `title` ≤ 80, up to 8 `lines` of ≤ 160 characters. A file that fails validation disables the MOTD and logs one `warn` with the failing path.

Shared convars read via `aeterna_core`: `aeterna_locale` (`en` or `th`, set with `setr`), `aeterna_theme` (`nui://<resource>/<path>.css`, set with `setr`).

## Exports & Events / การเรียกใช้งาน

### Client exports

| Export | Returns | Description |
|---|---|---|
| `exports.aeterna_notify:notify(opts)` | `boolean` | Shows a toast (`{ id?, title, description?, type = 'info'\|'success'\|'warning'\|'error', duration?, icon? }`). |
| `exports.aeterna_notify:clear(id?)` | `boolean` | Removes one toast by `id`, or clears all toasts when `id` is omitted. |
| `exports.aeterna_notify:showMotd()` | `boolean` | Shows the MOTD card if enabled, valid, and not already dismissed for the current `version`. |

### Server exports

| Export | Returns | Description |
|---|---|---|
| `exports.aeterna_notify:notify(src, opts)` | `boolean` | Sends a toast to one player `src` (`src = -1` is refused; use `announce`). |
| `exports.aeterna_notify:announce(opts)` | `boolean` | Broadcasts or queues a server-wide banner (`{ title, body?, duration = 8000, by? }`). |

## Commands and keys / คำสั่งและปุ่มลัด

- `aeterna_announce <text>` — Broadcasts an announcement (`body = <text>` ≤ 200, `title` = locale `notify.announce.title`, `by` = player name or `Console`). Requires ACE `aeterna.notify.announce` for players; server console (`src = 0`) is always allowed.
- ESC closes the MOTD card (acting as Continue).

## Support scope / ขอบเขตการรองรับ

- **Tested on / ทดสอบบน:** FXServer Enhanced & Legacy (cerulean, Lua 5.4), standalone with `aeterna_core`, and alongside `qbx_core` 1.23 and `ox_lib` 3.x.
- **Supported / รองรับ:** Standalone FiveM servers and Qbox/QBCore/ESX servers running `aeterna_core`, optional draggable positioning with `aeterna_layout`, custom CSS theme overrides via `setr aeterna_theme`, and Thai/English locales.
- **Not supported / ไม่รองรับ:** Broadcasting toasts with `notify(-1, ...)` (use `announce`), rendering raw HTML in notifications or MOTD lines, or running without `aeterna_core`.

## Capabilities

What this resource is allowed to do to your server, from [`oss.json`](oss.json). Keep this table in sync with `oss.json`; widening a capability needs maintainer review.

| Capability | Declared |
|---|---|
| HTTP requests | none |
| `ExecuteCommand` | none |
| Registered commands | `aeterna_announce` |
| Convars read | none |
| Convars written | none |
| Server net events (accepted from clients) | none |
| Client net events (accepted from the server) | `aeterna_notify:cl:toast`, `aeterna_notify:cl:announce`, `QBCore:Client:OnPlayerLoaded` |
| NUI | yes |
| Database tables | none (no DDL) |
| Files written | none |

## Verify before you install

Every release zip is built in CI and carries a build-provenance attestation. Check both the attestation and the checksum before you put it on your server:

```sh
gh attestation verify aeterna_notify-<version>.zip --repo aeterna/nakara-oss --signer-workflow aeterna/nakara-oss/.github/workflows/release.yml
sha256sum -c SHA256SUMS --ignore-missing
```

Then read the capability table above (or `oss.json` inside the zip).

## Tests

From the repository root:

```sh
busted --lpath='./packages/devkit/busted/?.lua;./?.lua;./?/init.lua' --pattern=_spec packages/notify/spec
```

## License

MIT. See [LICENSE](../../LICENSE). Bundled Lucide icon SVGs are ISC-licensed; see [NOTICE](NOTICE).
