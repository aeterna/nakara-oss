# aeterna_phonekit

- Package: `packages/phonekit` · resource `aeterna_phonekit` · wave W3 · status released in 0.1.0
- Depends on: `aeterna_core` (focus, KVP, locale, keys, time), `aeterna_uikit` (panel spec format, menu entry),
  `aeterna_notify` (notifications while the phone is closed)

## Purpose and limits

A phone shell a server can build on: a home screen, a status bar, four small apps that work with no server code,
and an app API so other resources add their own apps without touching phonekit's files. Apps from other resources
are uikit panel specs drawn inside the phone frame. The server owns every app screen; phonekit only draws it and
sends back the values the spec allows.

Not in v0.1: calls and voice, messages between players, a camera or photos, banking, social feeds, a phone item or
phone numbers. These need storage and a voice resource that ADR 0004's table does not allow; servers add them as apps
through the API below.

## Install

```cfg
ensure aeterna_core
ensure aeterna_uikit
ensure aeterna_notify
ensure aeterna_phonekit
```

## Configuration

`config.lua` (shipped):

| Key | Default | Meaning |
| --- | --- | --- |
| `Config.position` | `'bottom-right'` | `bottom-right` · `bottom-left`, 24 px inset |
| `Config.ask` | `false` | When `true`, the server asks other resources before the phone opens (below) |
| `Config.animation` | `true` | Hold a phone prop with the base-game phone animation while it is open |
| `Config.apps` | `{ calculator = true, notes = true, contacts = true, settings = true }` | Built-in apps to show |
| `Config.maxApps` | `24` | Apps from other resources; more are refused with a `warn` |

## The phone

- Frame 320 × 640 px at scale 1, Asphalt surfaces (`--surface`, `--raised`), radius 14 outside, 10 for app tiles.
- Status bar: time from `AeternaCore.time` (the server's `aeterna_timezone`), and nothing that pretends to be real
  data (no signal bars or battery).
- Home: a grid of app tiles (icon + label), sorted by `order` then `id`. A tile can carry a badge count.
- Back: the button at the bottom of the frame, Backspace, or right mouse button returns to the previous screen;
  ESC closes the phone from any screen.
- Open with the key mapping `+aeterna_phonekit_open` or the command `aeterna_phonekit_open` (no default key). The
  phone takes focus through `aeterna_core` with `keepGameInput = true` so the player can walk while it is open;
  mouse look is disabled while the cursor is over the frame. Losing focus closes the phone.
- With `Config.animation`, the ped holds a phone prop and plays the base-game phone animation; both stop on close
  and when the player enters water, ragdolls or dies. The prop model and animation names are constants in
  `client/anim.lua`; **which names work on FXServer Enhanced is not verified yet** (first W3 smoke step).

## Built-in apps (client only, no server code)

| App | What it does | Stored |
| --- | --- | --- |
| Calculator | Four operations, percent, sign, clear; numbers in tabular figures. Pure logic in `shared/logic/calc.lua` | nothing |
| Notes | Up to 50 notes, title ≤ 60, body ≤ 2000 | KVP `aeterna_phonekit:notes:v1` |
| Contacts | Up to 100 contacts, name ≤ 40, number ≤ 20 as free text (phonekit has no numbering plan) | KVP `aeterna_phonekit:contacts:v1` |
| Settings | Text size (normal, large), 24-hour or 12-hour clock, "Edit layout" when layout runs | KVP `aeterna_phonekit:settings:v1` |

All data stays on the player's machine (ADR 0004 decision 8). Notes and contacts are refused past 16 KB each with a
locale message, which is the `AeternaCore.kvp` limit.

## App API (server)

| Export | Notes |
| --- | --- |
| `addTile(app)` | `app = { id, label, icon, order = 100, ace = 'aeterna.… optional' }`. `id` ≤ 32 `^[%w_%-]+$`, unique per owner; `label` ≤ 24; `icon` from the uikit icon names. Removed when the owner stops |
| `removeTile(id)` | |
| `showApp(src, id, spec)` | Draws a uikit panel spec (blocks, limits and validation from [aeterna_uikit § Spec](aeterna_uikit.md#spec)) inside the phone for app `id`. Returns `screenId` or `nil, err`. `size` is ignored; the phone width is used |
| `updateApp(src, screenId, patch)` | Same patch rules as uikit `update` |
| `badge(src, id, count)` | Badge on the tile, 0–99 (`99+` above) |
| `notifyApp(src, id, opts)` | `opts = { title ≤ 60, body ≤ 160 }`. Phone open: a banner inside the phone. Phone closed: an `aeterna_notify` toast with the app's icon. Adds 1 to the badge unless the app is on screen |

Flow, the same rule as uikit (server-local events, the owner filtered by `owner == GetCurrentResourceName()`, no
functions crossing resources):

1. The player taps a tile. The server checks the app still exists and the player has its `ace`, then fires
   `aeterna_phonekit:app` → `(src, { owner, id })`. The owner answers with `showApp`.
2. A button press or list pick inside the app fires `aeterna_phonekit:action` →
   `(src, { owner, id, screenId, action, values })`, checked against the spec on screen exactly like
   `aeterna_uikit:action` (unknown action dropped, values re-checked and cleaned).
3. Back returns to the app's previous screen (the server keeps up to 8 per player). Back from the first screen returns
   home and fires `aeterna_phonekit:action` with `action = '__close'`; so does closing the phone with an app on screen.

`showApp` and `updateApp` work only for the resource that registered the app, for a player whose phone is open and who
passes the app's `ace`.

## Opening check (`Config.ask = true`)

The client asks the server (`aeterna_phonekit:sv:open`). The server fires `aeterna_phonekit:asking` →
`(src, { checkId })`. Another resource (for example one that requires a phone item) answers with
`allowOpen(checkId)` or `denyOpen(checkId, reasonKey)` within 1000 ms; silence counts as allowed when no resource
listens and as denied when one has called `listenOpen()` (so a server that wires a check is never bypassed by a
slow answer). A denial sends `aeterna_phonekit:cl:refused` with the reason key, shown as a toast.

## Events (network)

| Event | Direction | Schema | Rate limit |
| --- | --- | --- | --- |
| `aeterna_phonekit:sv:open` | client → server | none | 2 / 1000 ms |
| `aeterna_phonekit:sv:close` | client → server | none | 5 / 1000 ms |
| `aeterna_phonekit:sv:tap` | client → server | `{ id: string ≤ 32, owner: string ≤ 64 }` | 5 / 1000 ms |
| `aeterna_phonekit:sv:action` | client → server | `{ screenId: string ≤ 24, action: string ≤ 32, values: table ≤ 40 keys }` | 10 / 1000 ms |
| `aeterna_phonekit:cl:open` | server → client | `{ apps }` (the tiles this player may see) | — |
| `aeterna_phonekit:cl:screen` | server → client | spec + `screenId`, `id` | — |
| `aeterna_phonekit:cl:update` | server → client | `{ screenId, patch }` | — |
| `aeterna_phonekit:cl:badge` | server → client | `{ id, count }` | — |
| `aeterna_phonekit:cl:banner` | server → client | `{ id, title, body }` | — |
| `aeterna_phonekit:cl:refused` | server → client | `{ reason: string ≤ 64 }` | — |
| `aeterna_phonekit:app` | server-local | `{ owner, id }` | — |
| `aeterna_phonekit:action` | server-local | see above | — |
| `aeterna_phonekit:asking` | server-local | `{ checkId }` | — |

## NUI messages

Lua → NUI: `aeterna:theme`, `locale`, `shell:open {apps, settings}`, `shell:close`, `screen:show`, `screen:update`,
`badge`, `banner`, `builtin:data {notes, contacts}`.
NUI → Lua callbacks: `tap {owner, id}`, `action {screenId, action, values}`, `back {}`, `close {}`,
`builtin:save {app, data}`, `settings {key, value}`. Each is validated before it is forwarded or stored.

## Commands and keys

`aeterna_phonekit_open` (chat or F8), `+aeterna_phonekit_open` / `-aeterna_phonekit_open` registered with literal
names and mapped through `AeternaCore.key` with no default key.

## Storage

KVP `aeterna_phonekit:notes:v1`, `aeterna_phonekit:contacts:v1`, `aeterna_phonekit:settings:v1`
(`{ textSize, clock24 }`). Nothing on the server.

## Locale keys

`phonekit.key.open`, `phonekit.home.title`, `phonekit.back`, `phonekit.app.calculator`, `phonekit.app.notes`,
`phonekit.app.contacts`, `phonekit.app.settings`, `phonekit.notes.new`, `phonekit.notes.empty`, `phonekit.notes.full`,
`phonekit.contacts.new`, `phonekit.contacts.empty`, `phonekit.contacts.full`, `phonekit.settings.textSize`,
`phonekit.settings.clock24`, `phonekit.settings.layout`, `phonekit.refused.default`.

## `oss.json` capabilities

```json
{ "http": [], "commands": ["aeterna_layout"],
  "registeredCommands": ["aeterna_phonekit_open", "+aeterna_phonekit_open", "-aeterna_phonekit_open"],
  "convars": { "read": [], "write": [] },
  "netEvents": { "server": ["aeterna_phonekit:sv:open", "aeterna_phonekit:sv:close", "aeterna_phonekit:sv:tap",
                            "aeterna_phonekit:sv:action"],
                 "client": ["aeterna_phonekit:cl:open", "aeterna_phonekit:cl:screen", "aeterna_phonekit:cl:update",
                            "aeterna_phonekit:cl:badge", "aeterna_phonekit:cl:banner", "aeterna_phonekit:cl:refused"] },
  "nui": true, "db": { "tables": [], "ddl": false }, "files": { "write": [] } }
```

## Position and `aeterna_layout`

`Config.position` is the default. When `aeterna_layout` is started, phonekit registers one element, `phone`
(320 × 640 at scale 1, `scalable = true`, `hideable = false`), through layout's local events and applies its place
(ADR 0004 table: optional edge, local events only; owner, 2026-11-17). Without layout nothing changes. Phonekit never
lists layout in `dependencies`, never calls its exports and never loads its files. The Settings app shows "Edit
layout" only while layout runs.

## Tests

busted (pure logic in `shared/logic/`):

1. Calculator: operator order as typed (no precedence, like a phone calculator), percent, divide by zero shows an
   error state, long results rounded to 10 significant digits.
2. Notes and contacts: limits on count and length; the 16 KB limit refuses with the locale key; round trip.
3. App registry: `addTile`, replace same `owner/id`, `Config.maxApps`, owner stop removes only its apps, sort order,
   `ace` filters tiles per player.
4. Action validation: unknown `screenId`, an action not in the spec on screen, values outside their block's limits
   are dropped.
5. Opening check: no listener = allowed; listener + silence = denied; stale `checkId` ignored.
6. Badges: `notifyApp` adds 1 unless the app is on screen; `badge` clamps to 0–99.

Smoke (kit-test server, driven from a button menu, not typed commands):

1. Animation and prop on open and close on Enhanced (decides the open item above); walking while the phone is open.
2. Built-in apps: calculator sums, a note and a contact survive a reconnect.
3. A test resource adds an app with a list and a form; picks and button values reach the server; back returns home.
4. `notifyApp` while closed shows a toast and a badge; while open shows a banner.
5. With `aeterna_layout` started: drag and scale the phone, Done, reconnect, it stays; stop layout and it goes back
   to `Config.position`.
6. `Config.ask = true` with a test listener that denies: the phone does not open and the refusal toast shows.
7. Screenshots in Asphalt (home, an app, a banner, large text) for the owner's visual gate; reduced motion stops all
   movement.

## Done when

All busted cases pass, `fivem-devkit safety` reports 0 errors and 0 over-declared items, the smoke steps pass on the
kit-test server, and the owner has passed the screenshots.
