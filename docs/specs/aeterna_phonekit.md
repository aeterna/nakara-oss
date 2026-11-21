# aeterna_phonekit

- Package: `packages/phonekit` · resource `aeterna_phonekit` · wave W3 · status released in 0.1.0 · spec 0.2.0
  ([0.2 additions](#02-additions) at the end, [ADR 0005](../adr/0005-starter-kit-0-2.md) decision 5)
- Depends on: `aeterna_core` (focus, KVP, locale, keys, time), `aeterna_uikit` (panel spec format, menu entry),
  `aeterna_notify` (notifications while the phone is closed; 0.2: notification history through its export).
  Optional: `aeterna_layout` (local events only). 0.2 optional: `qbx_core` (character id, only when started)

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
  **Changed in 0.2:** the status bar shows the battery, because 0.2 has a real battery that the server counts
  ([Battery](#battery)). Signal bars stay out: nothing in the game measures a signal. With `Config.battery = false`
  the 0.1 status bar (time only) comes back.
- **Changed in 0.2:** the frame is no longer 320 × 640. Its size comes from the model the player holds
  ([Models and frames](#models-and-frames)); the default model `slab` is 392 × 812. Reason: one fixed frame cannot
  show a keypad phone, a clamshell and a two-pane book. Upgrade note under [Layout in 0.2](#layout-in-02).
- Home: a grid of app tiles (icon + label), sorted by `order` then `id`. A tile can carry a badge count.
- Back: the button at the bottom of the frame, Backspace, or right mouse button returns to the previous screen;
  ESC closes the phone from any screen.
- Open with the key mapping `+aeterna_phonekit_open` or the command `aeterna_phonekit_open` (no default key). The
  phone takes focus through `aeterna_core` with `keepGameInput = true` so the player can walk while it is open;
  mouse look is disabled while the cursor is over the frame. Losing focus closes the phone.
  0.2 addition: a focus **overlay** (for example the test kit's "did you see it?" card) does not take focus away. While
  `aeterna_core` reports phonekit's focus as paused (`aeterna_core:focusPaused` / `aeterna_core:focusResumed`,
  [aeterna_core](aeterna_core.md) § Focus overlay), the phone stays open on the same screen and ignores input; when the overlay
  releases, focus returns and input resumes. A real focus loss (`aeterna_core:focusLost`) still closes the phone.
- With `Config.animation`, the ped holds a phone prop and plays the base-game phone animation; both stop on close
  and when the player enters water, ragdolls or dies. The prop model and animation names are constants in
  `client/anim.lua` (0.2: the prop becomes `Config.prop`, default unchanged); **which names work on FXServer Enhanced is not verified yet** (first W3 smoke step).

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

---

## 0.2 additions

- Version: 0.2.0 ([ADR 0005](../adr/0005-starter-kit-0-2.md) decisions 1, 2, 3, 5) · Written by: Claude Code - Claude Opus 5.5 (helper)

Everything above is the 0.1 contract and stays valid except where it is marked **Changed in 0.2** (the status bar
battery and the frame size above; the battery itself under [Battery](#battery)). The App API,
the KVP keys, the net events and the server-local events of 0.1 keep their names and schemas; 0.2 only adds to them
(ADR 0005 decision 5). The device rules below are written as behaviour a player and a server owner can check; the
shell is new code on top of 0.1's NUI, under the Chrome 103 limits (no `:has()`, no container queries).

Package version 0.2.0. Depends on: `aeterna_core`, `aeterna_uikit`, `aeterna_notify` (hard); `aeterna_layout` and
`aeterna_invkit` are never dependencies: layout talks through its local events, and any resource (invkit included)
answers the open gate through phonekit's server-local events. `qbx_core` is read only when `GetResourceState` says it
is started (character id for the server KVP key, [Storage](#storage-02-additions)).

### Configuration (0.2 keys)

| Key | Default | Meaning |
| --- | --- | --- |
| `Config.devices` | `'single'` | `'single'`: every player holds one phone of `Config.singleModel`. `'items'`: the model comes from an inventory item through the open gate ([Device modes](#device-modes)) |
| `Config.singleModel` | `'slab'` | One of the eight model ids |
| `Config.names` | `'neutral'` | `'neutral'` or `'universe'` (display-name preset, [Model names](#model-names)) |
| `Config.models` | table below | Per model: `label`, `apps`, `colors`, `prop`. Missing keys take the shipped default |
| `Config.prop` | `'prop_npc_phone_02'` | The held prop (0.1 constant, now configurable). `Config.models[m].prop` overrides it per model |
| `Config.battery` | table below | `false` turns the battery off: no drain, no battery in the status bar, the phone never dies, battery exports return `nil` |
| `Config.lockScreen` | `false` | `true` turns on the lock screen ([Lock screen](#lock-screen)). Off by default so a 0.1 server keeps opening straight to home |
| `Config.cover` | `true` | `false`: a `fold` never closes (it stays open and the fold key does nothing) |

`Config.battery` (all numbers are validated at start; a bad value falls back to the default with one `warn`):

| Key | Default | Meaning |
| --- | --- | --- |
| `tickSec` | `10` | Server tick, 5–60 |
| `standby` | `0.25` | %/min while carried and switched on |
| `screen` | `1.0` | %/min extra while any phone screen is on |
| `call` | `1.5` | %/min extra while a call is connected (reported by an add-on, [Battery](#battery)) |
| `media` | `2.5` | %/min extra while a camera viewfinder is up |
| `vehicleSec` | `300` | Seconds from 0 to 100 % while sitting in a vehicle; `0` = vehicles do not charge |
| `warnAt` | `{ 20, 10, 5 }` | Warn once when the shown value crosses each, going down |
| `saveStep` | `5` | Save when the shown value crosses a multiple of this, and always at 0 and 100 |
| `pulseTtlSec` | `45` | A screen pulse older than this counts as off |
| `startPct` | `100` | Battery of a phone the server has never seen |

### Models and frames

Eight models. Sizes are design px at scale 1; the shell scales the whole frame by
`fit = min(1, (vh − 0.048 × vh) / h, (vw − 0.048 × vh) / w)` (`vw`, `vh` = NUI viewport), so a frame never clips on a
short or narrow screen, and then by the layout scale.

| Model id | Neutral name | Frame (w × h) | Folds | Home | Calls | Battery × | Rank |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `keypad` | Keypad | 300 × 660 | — | numbered list, keypad keys | yes | 4 | 1 |
| `burner` | Burner | 300 × 660 | — | numbered list, keypad keys | yes | 3 | 0 |
| `qwerty` | Qwerty | 392 × 760 | — | tile grid, 8 per page (screen above a hard keyboard) | yes | 2 | 2 |
| `slab` (default) | Slab | 392 × 812 | — | tile grid, 12 per page | yes | 1 | 4 |
| `fold` | Fold | open 380 × 842 · closed 380 × 430 | vertical clamshell, starts `open`; closed = cover screen | 12 per page | yes | 1 | 5 |
| `pro` | Pro | 392 × 812 | — | 12 per page | yes | 1.2 | 6 |
| `book` | Book | closed 380 × 812 · open 780 × 700 | book, starts `closed`; open = wide two-pane screen | 12 closed · 24 open (two pages side by side) | yes | 1 | 7 |
| `pad` | Pad | 600 × 812 | — | 20 per page | **no** | 1.5 | 3 |

- "Battery ×" divides the drain (a keypad phone lasts four times as long as a slab). "Rank" picks the active device
  ([Device modes](#device-modes)).
- "Calls = no": tiles registered with `needs = 'voice'` are hidden on that model, and `device(src).voice` is `false`
  so an add-on can refuse a call.
- Case colours are object colours of the frame bezel (`Config.models[m].colors`, hex list, first = default), not theme
  tokens; everything inside the glass uses `theme.css` tokens (`--surface`, `--raised`, type tokens `--fs-1`…`--fs-5`,
  `--lh`). Shipped colours (generic names in the locale keys `phonekit.color.<name>`):

  | Model | Colours (first = default) |
  | --- | --- |
  | `keypad` | charcoal `#33363B` · blue `#3A5F8F` · orange `#D9762B` |
  | `burner` | black `#18191B` · olive `#4B5240` |
  | `qwerty` | charcoal `#2B2D30` · silver `#B8BCC2` |
  | `slab` | graphite `#3D4046` · silver `#C9CCD1` · sand `#CDBB9A` · blue `#5C7FA8` |
  | `fold` | graphite `#36383D` · sand `#D4C3A3` · green `#6F8F7A` |
  | `pro` | graphite `#45474B` · silver `#BDBFC2` · blue `#3F536E` · sand `#B9A584` |
  | `book` | graphite `#404247` · silver `#CED0D3` |
  | `pad` | silver `#C4C7CB` · graphite `#4E5056` · blue `#6C8DB3` |
- A fold value that is not valid for the model becomes that model's default; the fold key does nothing on a model
  that does not fold.

### Model names

Display names come from locale keys `phonekit.model.<id>` (the neutral names above). `Config.names = 'universe'`
switches to a preset of names from the game's own universe: keypad "Whiz Keypad", burner "Badger Burner", qwerty
"Badger Qwerty", slab "Facade Slab", fold "Facade Fold", pro "iFruit Pro", book "iFruit Book", pad "iFruit Pad".
`Config.models[m].label` (plain text ≤ 24) wins over both. No real product names ship in either set.

### Apps per model

`Config.models[m].apps` is an app spec string: comma-separated tokens, `*` = every app, `-x` removes `x`, anything
else adds it. Tokens are built-in ids (`calculator`, `notes`, `contacts`, `settings`) or `<owner>:<id>` for an app from
another resource. Unknown tokens are kept, so an app that registers later can be listed without a restart. Defaults:
`burner = '*,-contacts'` (a burner has no contact book), every other model `'*'`. A tile a model does not list is not
drawn and its tap is refused by the server (`noapp`). `settings` is always kept (the player must reach text size and
layout).

Keypad and burner draw the same apps as a numbered list instead of tiles.

### Device modes

**`single` (default).** Every player holds one phone of `Config.singleModel` and the first case colour. Its state
(battery, fold) is server-side resource KVP `aeterna_phonekit:device:v1:<who>` = `{ battery, fold }`, where `<who>` is
`cid:<character id>` when `qbx_core` is started, else `lic:<license>` (ADR 0005 decision 3, key shape in the
[specs README](README.md)). Loaded
on character load (or join), saved on the [battery save rule](#battery), on unload and on drop.

**`items`.** The phone is an inventory item. Phonekit never touches an inventory: the resource that owns the items
(`aeterna_invkit`, or any other) answers the open gate with the devices the player carries. In this mode the gate is
always on, whatever `Config.ask` says, and silence means "no phone" (`phonekit.refused.nodevice`).

Server-local events (the local-event form of the 0.1 `listenOpen` / `allowOpen` / `denyOpen` exports, so a resource
with no hard edge to phonekit can answer; `aeterna_invkit` uses these, [aeterna_invkit § 0.2](aeterna_invkit.md)):

| Event | Fired by | Payload | Meaning |
| --- | --- | --- | --- |
| `aeterna_phonekit:hello` | phonekit | — | phonekit (re)started; listeners fire `listen` again |
| `aeterna_phonekit:listen` | answerer | — | Same as `listenOpen()`: silence now means denied |
| `aeterna_phonekit:asking` | phonekit | `(src, { checkId, devices })` | 0.1 event; 0.2 adds `devices = 'single' \| 'items'` so an answerer can stay silent in `single` mode |
| `aeterna_phonekit:answer` | answerer | `(checkId, { allow = true, devices = { … } })` or `(checkId, { allow = false, reason })` | Same as `allowOpen(checkId, answer)` / `denyOpen(checkId, reason)` |
| `aeterna_phonekit:devicesChanged` | answerer | `(src)` | A phone item left, entered or moved in this player's inventory; phonekit asks the gate again at once and puts the phone away if the active device is gone |
| `aeterna_phonekit:deviceSave` | phonekit | `(src, { id, battery, fold })` | Write these into the phone item with this `id` (item metadata `battery`, `fold`), keeping its other metadata |

`allowOpen(checkId, answer?)` (0.1 export) gains the optional `answer`; without it 0.1 behaviour is unchanged.
`answer.devices` = up to 8 of `{ id: string ≤ 64, model: model id, battery?: number 0–100, fold?: 'open'|'closed',
color?: integer index into the model's colours }`. A single device may be sent as `{ allow = true, id, model, battery?,
fold?, color? }` (the same as a one-entry list). Unknown models and duplicate ids are dropped; an empty list counts
as a denial with `phonekit.refused.nodevice`. `id` is the answerer's stable key for one physical phone (for example
a serial kept in the item metadata, such as `aeterna_invkit`'s `phoneId`, so it survives moving the item); phonekit only compares it. A missing `battery` means `startPct`,
and phonekit fires `deviceSave` with it at once. A missing `color` means the model's first colour. With
`Config.battery = false` phonekit still fires `deviceSave` for `fold` and leaves `battery` out.

Active device when several are carried: the one the player chose last, while it is still in the list; otherwise the
highest rank; ties go to the smallest `id` (never slot order). The choice is server-side resource KVP
`aeterna_phonekit:active:v1:<who>`. The player switches in the control centre (`aeterna_phonekit:sv:device`, the `id`
must be in the last answer). Only the active device drains. When the active device disappears from a new answer,
every phone surface closes, like a dead battery, without marking the battery dead.

Battery in item mode lives in the item metadata, written by the answerer when phonekit fires `deviceSave`; a phone
handed to another player keeps its charge. If nothing answers `deviceSave` the value lives only until the player
leaves. Item icons and item definitions are install instructions in the package README, not files phonekit writes.

| Export (server) | Returns |
| --- | --- |
| `device(src)` | `{ model, id, label, voice, fold, battery }` of the active device, or `nil` (no phone, or phone closed by a dead battery: `battery = 0`) |
| `refreshDevices(src)` | Asks the gate again; same as the `devicesChanged` event, for resources that depend on phonekit |

### Shell

Built on 0.1's page. Parts, top to bottom:

- **Status bar** (touch models): time (12/24 h from settings), a live pill when an add-on sets one (`live`, below),
  battery percent with an icon and a charging mark. No signal bars. Keypad models print the same in text on the LCD.
- **Screens**: home and app screens as in 0.1.
- **Home bar** (touch models): tap = home from an app; on the lock screen or at home = put the phone away; with the
  control centre open = close it. A swipe up that starts on it unlocks the lock screen.
- **Keypad keys** (keypad, burner): ↑ ↓ OK Back and 0–9 * #, drawn under the LCD and driven by the keyboard.

#### Lock screen

- Shown when the phone opens and something is waiting (a tile badge or an unread entry in the notification history);
  with nothing waiting the phone opens straight to home. One lock per phone session: after unlocking it does not come
  back until the phone closes. Only with `Config.lockScreen = true` (default `false`, the 0.1 behaviour: the phone
  opens straight to home). Upgrade note: nothing changes for a 0.1 server until the owner sets it to `true`.
- Shows time, date (`AeternaCore.time`), and up to 5 cards: tiles with a badge (label + count) and the newest
  notification history entries. Cards come from the same badges as the home grid, so a card and a badge never disagree.
  Tapping a card unlocks and opens that app.
- Unlock: swipe up ≥ 46 px on the lock screen or from the home bar; OK or Enter on keypad models. There is no PIN in
  0.2.

#### Control centre

- Opens with a pull-down ≥ 46 px that starts on the status-bar strip only; a drag that starts inside a screen scrolls
  that screen. Closes with a swipe up, the home bar, Backspace or the right mouse button. ESC closes the whole phone,
  as on every screen.
- Toggles that change something real, nothing else: text size (normal, large), 24-hour clock, "Edit layout" while
  `aeterna_layout` runs, and in item mode the list of carried phones (name, battery, active mark; tap = switch).
  No brightness, signal, Wi-Fi or flight-mode tiles.
- Under the toggles: the notification history ([Notification history](#notification-history)).
- The toggles write the 0.1 settings KVP (`aeterna_phonekit:settings:v1`, same keys), so Settings and the control
  centre never disagree.

#### Cover screen (`fold` closed)

- Replaces the phone while a `fold` is closed: time, date, battery, a count of what is waiting, and an incoming call
  with Answer and Decline when an add-on rings ([Hooks for add-ons](#hooks-for-add-ons)).
- Tapping a waiting item stores it; when the phone is opened (and unlocked) that app opens. The stored item is dropped
  when the phone closes.
- Answering on the cover does not open the phone.

#### Fold continuity

- Folding or unfolding changes the layout only: the screen on top, its scroll position and any half-typed text stay.
  The screen is never shown again from scratch.
- Closing a `book` while a detail sits beside its list: the detail becomes the single screen.
- Opening a `book` while a detail is the whole screen and the screen under it in the app's back stack holds the
  `list` or `table` block its `detailOf` names: that screen comes back on the left (with `detailItem` highlighted) and
  the detail on the right.
- A device keeps the fold it is in while its data refreshes; another device opens in the fold it was last left in
  (stored with the device: KVP in `single`, item metadata in `items`).
- The fold animation lasts about 260 ms; reduced motion turns it off.
- Fold changes are sent to the server (`aeterna_phonekit:sv:fold`) so the server knows the frame and can save the fold.

#### Two panes (`detailOf`)

The App API stays (`showApp`, `updateApp`, `badge`, `notifyApp`). Panel specs may carry uikit 0.2's `detailOf` and
`detailItem` fields ([aeterna_uikit § `detailOf`](aeterna_uikit.md#detailof--a-screen-that-details-one-list-item)):
`detailOf` names a `list` or `table` block of the screen that was on display when the spec was sent, `detailItem`
the picked row.

- On an open `book`, phonekit keeps the earlier screen on the left with `detailItem` highlighted and draws the new spec
  on the right. Picking another row on the left replaces the right pane through the app's normal action flow.
- Anywhere else (every other model, a closed book, or a `detailOf` that does not name a block of the earlier screen)
  the spec is a normal single screen.
- Back from a right pane closes that pane; the list stays.
- Phonekit keeps its own copy of uikit's spec validator, updated to accept every block type and field of uikit 0.2.
- Apps from other packages draw inside the phone only through panel specs; phonekit never loads another resource's
  page or files (ADR 0004 decision 6).

#### Exit contract

| Input | Effect |
| --- | --- |
| Open key (the `+aeterna_phonekit_open` mapping) | Puts the whole phone away from every screen. An F-key works while a field has focus (it types nothing); a letter, digit or punctuation key counts only when no field has focus and no screen used the key |
| ESC | Closes the phone from any screen, the lock screen, control centre and cover included (0.1 rule, ADR 0004 decision 10). An app on screen gets `__close` |
| Backspace / right mouse button | Back (0.1): control centre open → close it; otherwise the previous screen. Backspace inside a focused field edits the field. On keypad models at home (no field focused, not on the lock screen): put away |
| Home bar tap | Control centre → close; lock screen or home → put away; inside an app → home |

- The page may only close. Opening stays with the key mapping and the command, which ignore an open within 300 ms of a
  close (with `keepGameInput`, one key press reaches both the page and the game).
- The client sends the key currently bound to the open mapping to the page as a `KeyboardEvent.code`, so the page
  catches it while it has focus. With no key bound the page has no put-away key; ESC still closes.
- A focused field that is removed never fires `focusout`; a 500 ms check turns typing off so the player never stays
  without game input.

#### Keypad models

- The home is a numbered list. ↑ / ↓ move the highlight and wrap; OK (Enter) opens; digit 1–9 opens row 1–9 and 0 opens
  row 10; a digit with no row does nothing.
- While the lock screen is up, keys go to it, never to the list under it. In the calculator digits type; elsewhere
  they do nothing unless the app spec has a focused field.

### Battery

**Changed in 0.2** (from "no signal bars or battery" above): the phone has a battery that the server counts.

- The server owns the number. Nothing a client sends can raise it.
- Drain %/min = (`standby` + max(`screen` if on, `call` if connected, `media` if a viewfinder is up)) ÷ the model's
  battery multiplier. While charging there is no drain.
- **Screen pulse.** The client sends `aeterna_phonekit:sv:screen` with `'off'`, `'on'` (any phonekit screen, the cover
  included) or `'media'`, on every change and every 30 s while not off. A pulse older than `pulseTtlSec` counts as off,
  so a lost `off` (crash, restart) cannot keep draining. Faking `off` only saves the faker's own battery; this is
  accepted.
- `media` is reported by an add-on through the client export `activity('media', on)`; `call` by an add-on through
  the server export `activity(src, 'call', on)`. Only the resource that set an activity can clear it; it clears when
  that resource stops.
- **Charging.** Sitting in a vehicle charges 0 → 100 % in `vehicleSec` (server reads the ped's vehicle). Other resources
  add chargers with `setCharger(src, id, secToFull)` (a zone, a charging cable) and remove them with
  `setCharger(src, id, false)`; the fastest charger wins; a duration ≤ 0 means no charging. `charge(src, pct)` adds a
  lump (a power bank item), capped at 100, and works on a dead phone.
- Shown value = ceil(pct), so 0 % appears only when the phone is dead.
- Saved when the shown value crosses a multiple of `saveStep`, at 0, at 100, on unload, on drop and on resource stop.
- Warnings at each `warnAt` value going down, once each, never at 0: a phonekit banner while the phone is open, an
  `aeterna_notify` toast while it is closed.
- **At 0:** the server sends `aeterna_phonekit:cl:power { on = false }`; the client closes every phonekit surface
  (shell, cover, app screens: the app on screen gets `__close`), fires the server-local
  `aeterna_phonekit:power` → `(src, { on = false })` so add-ons end calls and viewfinders, and refuses to open with
  `phonekit.battery.dead`. Every server door (`sv:open`, `sv:tap`, `sv:action`, `showApp`, `notifyApp`'s banner) refuses
  a dead phone on its own; the client check is only for the toast. Above 0 again: `power { on = true }`.
- The tick keeps a set of loaded players, updated on load, unload and drop; it never scans every player each tick.

| Export (server) | Notes |
| --- | --- |
| `battery(src)` | Shown value 0–100, or `nil` (battery off or no phone) |
| `setBattery(src, pct)` | Sets the value and runs the same transitions as the tick (0 = full shutdown). For admin tools and tests |
| `charge(src, pct)` | Adds `pct` (0–100) |
| `setCharger(src, id, secToFull \| false)` | `id` ≤ 32, one per calling resource and id; removed when that resource stops |
| `activity(src, kind, on)` | `kind = 'call'` |

| Export (client) | Notes |
| --- | --- |
| `activity(kind, on)` | `kind = 'media'` |
| `isOpen()` | Whether any phonekit surface is on screen |

### Hooks for add-ons

Generic contracts so `aeterna_phonecall`, `aeterna_camera` or a server's own resource can build on the phone without
drawing a frame of their own (these are the names [aeterna_phonecall](aeterna_phonecall.md) N1–N5 asks for).

**Contacts (client).** The built-in Contacts app stays the only contact list (client KVP, 0.1).

| Export (client) / event | Notes |
| --- | --- |
| `getContacts()` | `{ {name, number}, … }`, a copy |
| `addContact({ name, number })` | Same limits as the app (name ≤ 40, number ≤ 20, 100 contacts, 16 KB). Returns `true` or `false, reasonKey` |
| `aeterna_phonekit:contactsChanged` (client-local, fired by phonekit) | After any add, edit or delete |

**Contact intents.** `addTile(app)` gains `handles = { 'tel' }`, `{ 'sms' }` or both. A contact's Call or Message
button is shown only when a started app handles that kind; pressing it fires the 0.1 server-local
`aeterna_phonekit:app` with an extra field: `{ owner, id, intent = { kind = 'tel' | 'sms', number } }`. With two
apps handling the same kind, the first registered wins and a `warn` names the second.

**Ring screen (server).**

| Export (server) | Notes |
| --- | --- |
| `ring(src, id, { title, body })` | `id` = the caller's own registered app; `title` ≤ 40, `body` ≤ 60. Shows an incoming card with Answer and Decline: on the cover when a `fold` is closed, on the lock screen when it is up, as a full card when the phone is open, and as an `aeterna_notify` toast when the phone is put away. Opens nothing by itself. Returns `ringId` or `nil, err` (`dead`, `nodevice`, `noapp`, `novoice`, `busy`). One ring per player; it ends by itself after 60 s |
| `stopRing(src, ringId)` | Removes the card wherever it is |
| `live(src, { id, text } \| nil)` | A pill in the status bar (`text` ≤ 24) while something is live (a call); `nil` clears it. One per player, last caller wins |
| `canCall(src)` | `false` for `pad`, for a player with no phone (item mode), or a dead battery; else `true` |

Answer and Decline come back as the 0.1 server-local `aeterna_phonekit:action` with `action = '__answer'` or
`'__decline'`, `screenId = ringId` and empty `values`, filtered on `owner` like every action. A ring card on the cover
can be answered without opening the phone.

### Notification history

The lock screen and the control centre show the newest entries of `aeterna_notify`'s history, pulled through notify's
client export `history(limit)` (entries `{ id, owner, kind, type, title, description, icon, count, at }`, newest
first; contract owned by [aeterna_notify § History](aeterna_notify.md#history)). Notify never pushes to phonekit (no
edge from notify to phonekit, ADR 0005 decision 2).

- Pulled when the lock screen or the control centre opens, at most once per second; up to 20 entries drawn
  (`count > 1` shows `×n`).
- "Clear" hides entries up to now on this phone: client KVP `aeterna_phonekit:seen:v1` = the newest `at`. Unread =
  newer than that mark. The history itself is notify's memory and is empty after a reconnect.
- With `Config.history.max = 0` in notify, the lists are empty and the lock screen uses badges only.

### Layout in 0.2

- Phonekit sends `aeterna_layout:add` again for element `phone` with the held model's frame size whenever that size
  changes (model switch, fold, unfold). Same `id`, so the player's saved place stays.
- With layout 0.2 running, layout clamps the element on that re-add, on a scale change and on a resolution change, and
  does not save the clamped place ([aeterna_layout § Clamp when an element's size changes](aeterna_layout.md#clamp-when-an-elements-size-changes)).
  Folding back therefore returns the phone to where the player put it. Phonekit applies every `apply` as in 0.1.
- Without layout (or with layout 0.1), phonekit clamps its own frame on every size change and NUI resize: from
  `Config.position` (or the last applied place), it shifts the frame inside the viewport, never saving anything.
- In every case the drawn scale is `min(place scale, fit)`, so a frame never clips.
- **Upgrade note (0.1 saved scales).** A scale a player saved in 0.1 was chosen for a 320 × 640 frame. After the
  upgrade the same scale applies to the larger 0.2 frame (a `slab` is 1.27 × taller), capped by `fit` so it stays on
  screen. Players who want the 0.1 size set the phone's scale again in the layout editor (about 0.8 of the old value).
  The package CHANGELOG and README repeat this.

### Commands and keys (0.2)

New permanent names, registered with literal names and mapped through `AeternaCore.key` with no default key
(ADR 0004 decision 10):

- `aeterna_phonekit_fold`, `+aeterna_phonekit_fold` / `-aeterna_phonekit_fold`: fold or unfold the held phone while
  it is open (`fold`, `book` only).

The 0.1 open command and mapping keep their names. The control centre and lock screen have no key of their own.

### Events (0.2 additions)

| Event | Direction | Schema | Rate limit |
| --- | --- | --- | --- |
| `aeterna_phonekit:sv:screen` | client → server | `{ level: 'off'\|'on'\|'media' }` | 4 / 1000 ms |
| `aeterna_phonekit:sv:fold` | client → server | `{ state: 'open'\|'closed' }` | 4 / 1000 ms |
| `aeterna_phonekit:sv:device` | client → server | `{ id: string ≤ 64 }` | 2 / 1000 ms |
| `aeterna_phonekit:sv:ring` | client → server | `{ ringId: string ≤ 24, answer: boolean }` (becomes `__answer` / `__decline`) | 4 / 1000 ms |
| `aeterna_phonekit:sv:battery` | client → server | none (asks for the current value after load or restart) | 1 / 2000 ms |
| `aeterna_phonekit:cl:device` | server → client | `{ model, label, fold, voice, color, devices: [{ id, label, battery, active }] }` | — |
| `aeterna_phonekit:cl:battery` | server → client | `{ pct, charging }` or `{ none = true }` | — |
| `aeterna_phonekit:cl:power` | server → client | `{ on: boolean }` | — |
| `aeterna_phonekit:cl:ring` | server → client | `{ ringId, id, title, body }` | — |
| `aeterna_phonekit:cl:ringStop` | server → client | `{ ringId }` | — |
| `aeterna_phonekit:cl:live` | server → client | `{ id, text }` or `{}` | — |
| `aeterna_phonekit:hello` · `:listen` · `:answer` · `:devicesChanged` · `:deviceSave` | server-local | see [Device modes](#device-modes) | — |
| `aeterna_phonekit:asking` | server-local | 0.1 payload + `devices = 'single' \| 'items'` | — |
| `aeterna_phonekit:power` | server-local | `(src, { on })` | — |
| `aeterna_phonekit:app` | server-local | 0.1 payload + optional `intent = { kind, number }` | — |
| `aeterna_phonekit:contactsChanged` | client-local | — | — |

Every server handler calls `AeternaCore.rateLimit` and checks the payload with `AeternaCore` validation before it
acts. `sv:fold` is refused for a model that does not fold; `sv:device` for an id not in the player's last answer.

`addTile(app)` gains `needs = 'voice'` (optional: hidden on models without calls) and `handles` (contact intents).

### NUI messages (0.2 additions)

Lua → NUI: `device {model, label, fold, voice, color, devices}`, `battery {pct, charging} | {none}`, `power {on}`,
`ring`, `ringStop`, `live`, `history {entries, seenAt}`, `closeKey {code}`.
NUI → Lua callbacks: `fold {state}`, `device {id}`, `ring {ringId, answer}`, `seen {at}`, `screen {level}`.
Each is validated before it is forwarded or stored; text from the server is set with `textContent`.

### Storage (0.2 additions)

| Where | Key | Value |
| --- | --- | --- |
| Server resource KVP (`SetResourceKvp`, server side) | `aeterna_phonekit:device:v1:<who>` | `{ battery, fold }` in `single` mode |
| Server resource KVP | `aeterna_phonekit:active:v1:<who>` | last chosen device `id` in `items` mode |
| Item metadata (written by the answerer) | `battery`, `fold` | in `items` mode |
| Client KVP | `aeterna_phonekit:seen:v1` | newest notification `at` the player cleared |

`<who>` = `cid:<character id>` when `qbx_core` is started, else `lic:<license>`. No battery, device or fold value is ever
stored in client KVP. No database tables (ADR 0004 decision 8).

### Locale keys (0.2 additions)

`phonekit.model.keypad`, `phonekit.model.burner`, `phonekit.model.qwerty`, `phonekit.model.slab`,
`phonekit.model.fold`, `phonekit.model.pro`, `phonekit.model.book`, `phonekit.model.pad`, `phonekit.key.fold`,
`phonekit.lock.hint`, `phonekit.lock.hintKeypad`, `phonekit.cc.title`, `phonekit.cc.devices`, `phonekit.cc.active`,
`phonekit.history.title`, `phonekit.history.empty`, `phonekit.history.clear`, `phonekit.cover.waiting`,
`phonekit.ring.answer`, `phonekit.ring.decline`, `phonekit.ring.busy`, `phonekit.contacts.call`, `phonekit.contacts.message`, `phonekit.color.<name>` (black, charcoal, graphite, silver, sand, blue, green, olive, orange), `phonekit.battery.low`, `phonekit.battery.dead`,
`phonekit.battery.charging`, `phonekit.refused.nodevice`, `phonekit.refused.noapp`.

### `oss.json` capabilities (0.2)

```json
{ "http": [], "commands": ["aeterna_layout"],
  "registeredCommands": ["aeterna_phonekit_open", "+aeterna_phonekit_open", "-aeterna_phonekit_open",
                         "aeterna_phonekit_fold", "+aeterna_phonekit_fold", "-aeterna_phonekit_fold"],
  "convars": { "read": [], "write": [] },
  "netEvents": { "server": ["aeterna_phonekit:sv:open", "aeterna_phonekit:sv:close", "aeterna_phonekit:sv:tap",
                            "aeterna_phonekit:sv:action", "aeterna_phonekit:sv:screen", "aeterna_phonekit:sv:fold",
                            "aeterna_phonekit:sv:device", "aeterna_phonekit:sv:ring", "aeterna_phonekit:sv:battery"],
                 "client": ["aeterna_phonekit:cl:open", "aeterna_phonekit:cl:screen", "aeterna_phonekit:cl:update",
                            "aeterna_phonekit:cl:badge", "aeterna_phonekit:cl:banner", "aeterna_phonekit:cl:refused",
                            "aeterna_phonekit:cl:device", "aeterna_phonekit:cl:battery", "aeterna_phonekit:cl:power",
                            "aeterna_phonekit:cl:ring", "aeterna_phonekit:cl:ringStop", "aeterna_phonekit:cl:live"] },
  "nui": true, "db": { "tables": [], "ddl": false }, "files": { "write": [] } }
```

The theme preset convar is read by `aeterna_core`, not by phonekit.

### Tests (0.2 additions)

busted (pure logic in `shared/logic/`, no natives):

1. Device rules: frame size per model and fold; invalid fold → default; toggle on a non-folding model = no change;
   tiles per page (book open 24, pad 20, qwerty 8, else 12); two panes only on an open book; `fit` never exceeds 1
   and keeps the frame inside a 1280 × 720 viewport.
2. Fold continuity: close with detail beside list → detail alone; open with a detail on top whose `detailOf` names a
   block of the screen under it → pair; a `detailOf` that names no block there → single screen.
3. Keypad list: ↑/↓ wrap, digit 1–9 and 0 map to rows, digit past the end does nothing, empty list stays 0.
4. Exit contract: every row of the table above, including an F-key while typing, a letter key while typing, ESC
   closing from an app screen, the lock screen and the control centre, and Backspace editing a focused field.
5. Battery: drain = standby + max(...) ÷ multiplier; charging stops drain; ≤ 0 seconds = no charging; fastest charger
   wins; `shown` 0 only at 0; save on step, 0 and 100; warnings only going down and never at 0; stale pulse = off.
6. App specs: `*`, `-x`, unknown tokens kept, `settings` always kept, `needs = 'voice'` hidden on `pad`.
7. Active device: last chosen wins while carried; else rank; ties → smallest id; empty list = no device.
8. Gate answers: `devices` schema and the single-device form, unknown model dropped, duplicate ids dropped, empty
   list = denial, item mode silence = denial, `answer` with `allow = false` = `denyOpen`, stale `checkId` ignored.
9. Own clamp (no layout): a frame that grows on unfold is shifted inside the viewport; nothing is saved; drawn scale
   = min(place scale, fit).
10. Hooks: `addContact` limits; `contactsChanged` fires once per change; an intent reaches only the handling app;
    `ring` refuses `novoice` on `pad`, `busy` on a second ring, `dead` at 0 %; answer maps to `__answer`; ring
    expires at 60 s; `canCall` truth table.

### Self-tests (0.2)

Registered with `aeterna_core`'s self-test registry (ADR 0005 decision 7); `aeterna_testkit` runs them from its menu.
`headless` and `mock` tests run on the server unless marked `side = 'client'` (then on the presser's client; GAP with
no presser). Destructive tests write a real player's stored data and run only when `aeterna_core_allow_destructive`
is on; otherwise they SKIP. Eye tests rely on the focus overlay: the phone stays open under the test card.

| Name | Kind | Players | Destructive | Expect (eye) | Skip when |
| --- | --- | --- | --- | --- | --- |
| `aeterna_phonekit.rules_loaded` | headless | 1 | n | — | never |
| `aeterna_phonekit.models_have_apps` | headless | 1 | n | — | never |
| `aeterna_phonekit.battery_drain_tick` | headless | 1 | n | — (runs the tick on a fake in-memory device, no player) | `Config.battery = false` |
| `aeterna_phonekit.battery_zero_closes_all` | mock | 1 | y (saves 0 for the presser, then restores) | — | `Config.battery = false` |
| `aeterna_phonekit.battery_kvp_roundtrip` | mock | 1 | y (writes the presser's server KVP, then restores) | — | `Config.devices = 'items'` |
| `aeterna_phonekit.stale_pulse_is_off` | headless | 1 | n | — | `Config.battery = false` |
| `aeterna_phonekit.gate_items_silence_denies` | mock | 1 | n | — | `Config.devices = 'single'` |
| `aeterna_phonekit.open_close_prop` | ped | 1 | n | — | no ped (presser not spawned) |
| `aeterna_phonekit.fold_keeps_screen` | ped | 1 | n | — | held model does not fold |
| `aeterna_phonekit.clamp_on_unfold` | ped | 1 | n | — | held model is not `book` |
| `aeterna_phonekit.exit_contract` | ped | 1 | n | — | never |
| `aeterna_phonekit.eye_model_<id>` (one per model, 8) | eye | 1 | n | That model's frame at the bottom right: its size and shape, status bar with time and battery, home in its form (tiles or numbered list), no clipped edge | never |
| `aeterna_phonekit.eye_book_two_pane` | eye | 1 | n | Book opened wide: list on the left, detail on the right, and the screen that was open before is still open | never |
| `aeterna_phonekit.eye_fold_cover` | eye | 1 | n | Fold closed: a small cover screen with time, battery and the waiting count; opening it shows the same screen as before | never |
| `aeterna_phonekit.eye_lock` | eye | 1 | n | Lock screen with one card for a test badge; swipe up reaches home | `Config.lockScreen = false` |
| `aeterna_phonekit.eye_control_centre` | eye | 1 | n | Pulling down from the status bar shows text size, 24-hour clock and the notification history, and no signal or brightness tiles | never |
| `aeterna_phonekit.eye_battery_dead` | eye | 1 | y (saves 0, then restores) | After the test sets 0 %: the phone and any app on it close at once and a "battery dead" toast shows; opening is refused until the test restores the value | `Config.battery = false` |
| `aeterna_phonekit.ring_cover` | eye | 1 | n | Fold closed: an incoming test card with Answer and Decline on the cover; Answer reports back without opening the phone | held model is not `fold`, or `Config.cover = false` |
| `aeterna_phonekit.contacts_hooks` | mock, `side = 'client'` (contacts are the presser's client KVP; restored after) | 1 | n | — | no presser |

`mock` tests change a value (battery, gate state) and restore it before they report. `ped` and `eye` tests run on the
presser's client and the server judges the result. `fold_keeps_screen` is the regression for the continuity rule: open
an app screen, fold, unfold, and the same screen key must be on top.

### Smoke (0.2, kit-test server, button menu)

1. Each of the eight models in `single` mode (switch `Config.singleModel`, restart the resource): frame, home form,
   no clipping at 1920 × 1080 and 1280 × 720.
2. `items` mode with `aeterna_invkit` answering: two phones carried, switch in the control centre, drop the active one
   and the phone closes; the battery travels with the item to a second player.
3. Battery: drain while open, no drain closed beyond standby, charge in a vehicle, warning toasts, 0 closes every
   surface, reconnect keeps the value.
4. Book and fold continuity with an app that uses `detailOf`; the frame stays on screen after unfolding near an edge.
5. Exit contract with a bound open key and with no key bound.
6. Upgrade from 0.1 with a saved layout scale: the phone stays on screen and is capped by `fit`; re-scaling in the
   editor sticks after a reconnect.

### Done when (0.2)

All busted cases pass, every self-test above reports PASS or SKIP with its reason on the kit-test server,
`fivem-devkit safety` reports 0 errors and 0 over-declared items, the smoke steps pass, and the owner has passed the
screenshots of all eight models, the open book, the closed fold, the lock screen, the control centre and the three
theme presets.
