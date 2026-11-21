# aeterna_notify

Toast notifications (with action buttons), server-wide announcement and countdown banners, a notification history, and a once-per-version message of the day (MOTD) card for the AETERNA Starter Kit ([ADR 0004](../../docs/adr/0004-aeterna-starter-kit.md) · [ADR 0005](../../docs/adr/0005-starter-kit-0-2.md) · [spec](../../docs/specs/aeterna_notify.md)).

ระบบแจ้งเตือนสำหรับเซิร์ฟเวอร์ FiveM ในชุด AETERNA Starter Kit ประกอบด้วยการแจ้งเตือนรายบุคคล (Toasts), แบนเนอร์ประกาศทั่วเซิร์ฟเวอร์ (Announcements) และการ์ดข้อความต้อนรับประจำวัน (MOTD) ที่แสดงครั้งเดียวต่อเวอร์ชันหลังผู้เล่นเกิด

---

## What it does / การทำงาน

- **Toasts (การแจ้งเตือนรายบุคคล):** Displays up to `Config.toast.max` (default `4`) toasts in any screen corner (`top-left`, `top-right`, `bottom-left`, `bottom-right`). Calling `notify` with an `id` already on screen replaces that toast in place and restarts its timer without jumping. Uses the same field names as `ox_lib`'s `lib.notify`.
- **Announcements (ประกาศทั่วเซิร์ฟเวอร์):** Shows one top-centre banner at a time across all connected players, queuing up to `Config.announce.queue` (default `5`) announcements behind the current one and dropping overflow with a warning. Triggered from server exports or the ACE-checked `aeterna_announce` command.
- **MOTD (ข้อความต้อนรับประจำวัน):** Configured in `config/motd.json` and shown once per `version` after spawn (`playerSpawned`, or `QBCore:Client:OnPlayerLoaded` when `qbx_core` is started, or via the `showMotd()` client export). "Don't show again" saves `version` to client KVP `aeterna_notify:motd_seen:v1`; "Continue" or ESC closes it for the current session. Coordinates NUI focus through `aeterna_core`.
- **Optional `aeterna_layout` integration (รองรับการจัดวางผ่าน `aeterna_layout`):** Registers `toasts` and `announce` through local client events (`aeterna_layout:add`, `aeterna_layout:hello`, `aeterna_layout:apply`) with no hard dependency, so players can drag and scale both elements when `aeterna_layout` is running.
- **Action buttons (ปุ่มบน Toast, 0.2):** A toast can carry up to two `actions`. Toasts never take focus, so a player presses them with the key mappings `+aeterna_notify_action1` / `+aeterna_notify_action2` (no default key; the button shows the player's binding), or with the mouse when another resource has already freed the cursor. The press closes the toast and goes back to the resource that created it (see *Events*). A toast that times out fires nothing.
- **Merging and lifetime bar (รวม Toast ซ้ำ และแถบเวลา, 0.2):** Identical toasts (same owner, `type`, `title`, `description`) show as one toast with `×n` (`×99+` above 99) that keeps its place and restarts its timer. A 2 px bar shows the time left and is not drawn under reduced motion.
- **Sound (เสียง, 0.2):** Off unless the server owner sets `Config.sound.enabled = true`; then each player toggles it with `aeterna_notify_sound` (stored in client KVP `aeterna_notify:settings:v1`). Announcements and the MOTD make no sound. No sound files ship; base-game frontend sounds are used.
- **Countdown announcements (ประกาศนับถอยหลัง, 0.2):** `announceCountdown` or `aeterna_announce_countdown` shows a `mm:ss` banner that comes back at each mark in `Config.countdown.marks` and fires `aeterna_notify:countdownEnd` at zero. What happens at zero (a restart, a kick) is your own resource's job.
- **History (ประวัติการแจ้งเตือน, 0.2):** The client export `history(limit?)` returns recent toasts and banners (memory only, empty after a reconnect), and `aeterna_notify:added` fires for each new or updated entry, so other resources can read the history. notify never calls the reader.
- **Deliberate limits (ขอบเขตที่จำกัดไว้):** No phone notifications of its own (other resources can read the history), no Discord relays, and no scheduled announcements other than the countdown.

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
| `Config.toast.lifetimeBar` | `true` | Draw the lifetime bar on timed toasts (0.2) / แสดงแถบเวลาที่เหลือ |
| `Config.toast.merge` | `true` | Merge identical toasts into one with a count; `false` = the 0.1 stack of copies (0.2) / รวม Toast ที่เหมือนกัน |
| `Config.toast.actionDuration` | `8000` | Default `duration` of a toast with actions, ms (`1000–15000`) (0.2) |
| `Config.sound.enabled` | `false` | The server owner allows sounds at all; `false` = no sound for anyone (0.2) / อนุญาตให้มีเสียง |
| `Config.sound.playerDefault` | `false` | Whether a player who has not chosen hears sounds when they are allowed (0.2) |
| `Config.sound.byType` | base-game frontend sounds | `{ info = { name, set }, … }` played with `PlaySoundFrontend(-1, name, set, true)`. The shipped names are **not verified yet** on FXServer Enhanced (0.2) |
| `Config.countdown.marks` | `{ 600, 300, 60, 30, 10 }` | Seconds left at which a countdown shows its banner again (0.2) |
| `Config.history.max` | `50` | Entries kept in the history, `0–50`; `0` turns history off (0.2) / จำนวนประวัติที่เก็บ |

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

Shared convars read via `aeterna_core`: `aeterna_locale` (`en` or `th`, set with `setr`), `aeterna_theme` (`nui://<resource>/<path>.css`, set with `setr`), and `aeterna_theme_preset` (`asphalt` · `paper` · `night-market`, used only when `aeterna_theme` is empty).

**Upgrade note (0.1 → 0.2):** merging is on by default, so a server that sends the same toast several times now sees one toast with `×n` instead of a stack. Set `Config.toast.merge = false` for the 0.1 behaviour, or pass `merge = false` on one toast. The lifetime bar is also on by default (`Config.toast.lifetimeBar = false`). The client `notify` export now returns the `toastId` (a string) instead of `true`.

## Exports & Events / การเรียกใช้งาน

### Client exports

| Export | Returns | Description |
|---|---|---|
| `exports.aeterna_notify:notify(opts)` | `toastId` or `false, err` | Shows a toast (`{ id?, title, description?, type = 'info'\|'success'\|'warning'\|'error', duration?, icon?, actions?, sound?, history?, merge? }`). |
| `exports.aeterna_notify:clear(id?)` | `boolean` | Removes one toast by `id`, or clears all toasts when `id` is omitted. |
| `exports.aeterna_notify:showMotd()` | `boolean` | Shows the MOTD card if enabled, valid, and not already dismissed for the current `version`. |
| `exports.aeterna_notify:history(limit?)` | `table` | Newest entries first, at most `limit` (`1–50`, default `50`): `{ id, owner, kind = 'toast'\|'announce'\|'countdown', type, title, description, icon, count, at }`. `id` is the toast's `toastId`. `at` is in seconds. Actions are never kept. |
| `exports.aeterna_notify:clearHistory()` | `nil` | Empties the history. |

0.2 toast fields: `actions` = 1–2 `{ id, label, variant? }` (`id` ≤ 32 matching `^[%w_%-]+$` and unique, `label` ≤ 20, `variant` `primary` or `secondary`, default `secondary`; a third entry, a bad id or an over-long label drops all actions with one `warn`); `sound`, `history`, `merge` are booleans, default `true`. `toastId` is the toast's `id` when given, otherwise `c` + a base-36 counter for a client-made toast or `s` + a base-36 counter for a server-made one (at most 24 characters). A toast with `actions` and an `id` longer than 24 characters is refused with `id: maxLen 24 with actions` (a press carries at most 24).

```lua
local toastId = exports.aeterna_notify:notify({
    title = 'Mind sent a location', description = 'Elysian docks · 1.2 km',
    actions = { { id = 'pin', label = 'Pin it', variant = 'primary' }, { id = 'skip', label = 'Ignore' } },
})
AddEventHandler('aeterna_notify:action', function(press)
    if press.owner ~= GetCurrentResourceName() or press.toastId ~= toastId then return end
    -- press.action == 'pin' or 'skip'
end)
```

### Server exports

| Export | Returns | Description |
|---|---|---|
| `exports.aeterna_notify:notify(src, opts)` | `true, nil, clean` or `false, err` | Sends a toast to one player `src` (`src = -1` is refused; use `announce`). `clean.toastId` holds the toast's id (0.2). |
| `exports.aeterna_notify:announce(opts)` | `boolean` | Broadcasts or queues a server-wide banner (`{ title, body?, duration = 8000, by? }`). |
| `exports.aeterna_notify:announceCountdown(opts)` | `countdownId` or `nil, err` | `{ title, body?, seconds, by?, marks? }`: `title` ≤ 80, `body` ≤ 200, `by` ≤ 32, `seconds` `10–3600`, `marks` up to 8 whole seconds below `seconds` (default `Config.countdown.marks`). One at a time: a second returns `nil, 'busy'`. |
| `exports.aeterna_notify:cancelCountdown(countdownId)` | `boolean` | Hides it for everyone and fires `aeterna_notify:countdownEnd` with `cancelled = true`. Only the resource that started the countdown may cancel it (a countdown from `aeterna_announce_countdown` belongs to notify). When that resource stops, or notify stops, the countdown ends the same way. |

### Events

| Event | Side | Payload |
|---|---|---|
| `aeterna_notify:action` | client-local | `({ owner, toastId, action })` for a toast made by the client export; `owner` is the resource that called it, so filter on `owner == GetCurrentResourceName()` |
| `aeterna_notify:action` | server-local | `(src, { owner, toastId, action })` for a toast made by the server export. The server checks the toast was sent to that player, the action is one of its ids, and the press came within `duration` + 2000 ms; each toast answers once. Open action toasts are kept per owner resource + `toastId`, at most 8 per player per owner, so one resource never replaces another's; resending the same `id` without actions drops that owner's record |
| `aeterna_notify:countdownEnd` | server-local | `({ countdownId, cancelled })` |
| `aeterna_notify:added` | client-local | a history entry, for every new or updated entry |

A countdown banner shows the time left as `mm:ss`, counted down on each client from the `remainingMs` the server sends; the server is the clock that ends it. It is sent again at each mark (a player who joined late sees it from the next mark on) and goes ahead of the normal announcement queue without counting against it. One showing stays up for 8 s, or until zero when no more than 16 s are left.

## Commands and keys / คำสั่งและปุ่มลัด

- `aeterna_announce <text>` — Broadcasts an announcement (`body = <text>` ≤ 200, `title` = locale `notify.announce.title`, `by` = player name or `Console`). Requires ACE `aeterna.notify.announce` for players; server console (`src = 0`) is always allowed.
- `aeterna_announce_countdown <minutes> <text>` — Starts a countdown (`minutes` `1–60`, `title` = locale `notify.countdown.title`, `body` = `<text>`). Same ACE as `aeterna_announce`; the console is always allowed.
- `aeterna_notify_sound` — Turns notification sounds on or off for this player and shows the new state (shows `notify.sound.disabled` when the owner turned sounds off).
- `+aeterna_notify_action1` / `+aeterna_notify_action2` — Press the first or second action of the newest toast that has actions. No default key: bind them in Settings → Key Bindings → FiveM.
- ESC closes the MOTD card (acting as Continue). While another resource holds focus through `aeterna_core`'s focus overlay, the MOTD stays on screen and ignores input until focus comes back.

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
| Registered commands | `aeterna_announce`, `aeterna_announce_countdown`, `aeterna_notify_sound`, `+aeterna_notify_action1`, `-aeterna_notify_action1`, `+aeterna_notify_action2`, `-aeterna_notify_action2` |
| Convars read | none |
| Convars written | none |
| Server net events (accepted from clients) | `aeterna_notify:sv:action` (rate limited 5 / 1000 ms) |
| Client net events (accepted from the server) | `aeterna_notify:cl:toast`, `aeterna_notify:cl:announce`, `aeterna_notify:cl:countdown`, `QBCore:Client:OnPlayerLoaded` |
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

## Self-tests (0.2)

Registered with `aeterna_core` as `aeterna_notify.<name>` and run from `aeterna_testkit` (or the core console command,
where client tests are GAP). Spec: `docs/specs/aeterna_notify.md` § Self-tests (0.2).

| Name | Kind | What it checks |
| --- | --- | --- |
| `toast_opts` | headless | Three actions, a bad action id or a 21-character label fall back to no actions with one warning; a long `id` with actions, no title, durations, `sound` |
| `merge_key` | headless | The same toast merges with `×2` and restarts its timer; another description, owner, an `id`, actions or `merge = false` never merge; `×99+` |
| `action_forged` | headless | A press for an unknown toast, another action, another player, a second press or a late press is refused |
| `countdown_clock` | headless | 9 and 3601 seconds refused, `busy`, marks above `seconds` dropped, the banner at a mark, the end event once, cancel by the owner only, `mm:ss` |
| `toast_types` | eye | Four toasts, one per type, for 15 s |
| `stack_merge` | eye | Six identical toasts |
| `action_press` | ped | A toast with two buttons; the test presses its first action through the function the key mappings and the mouse use, receives the first id, and the toast closes |
| `sound_plays` | eye | Each type with the player's setting treated as on, then as off (the stored setting is not changed). SKIP when `Config.sound.enabled = false` |
| `countdown_banner` | eye | A 30-second banner on this client only, shown again at the marks and hidden at zero; no server countdown starts |
| `history_pull` | headless (client) | The history logic on a fresh instance and the shape of what the export returns. SKIP when `Config.history.max = 0` |
| `motion_reduced` | eye | A short toast every 3.5 s |

Test toasts and the test banner never enter the history and are removed when the test ends.

Core's local events (`aeterna_core:selftest`, `selftestEnd` and the focus events) count only when `aeterna_core`
fired them, and open test state is torn down when `aeterna_core` stops.

## Tests

From the repository root:

```sh
busted --lpath='./packages/devkit/busted/?.lua;./?.lua;./?/init.lua' --pattern=_spec packages/notify/spec
```

## License

MIT. See [LICENSE](../../LICENSE). Bundled Lucide icon SVGs are ISC-licensed; see [NOTICE](NOTICE).
