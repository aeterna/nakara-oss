# aeterna_radial

- Package: `packages/radial` · resource `aeterna_radial` · version 0.1.0 · wave W1 of Starter Kit 0.2 · status spec
- Depends on: `aeterna_core` (focus, keys, locale, validation, rate limit, self-tests), `aeterna_uikit` (key hints
  while the menu is open) — [ADR 0005](../adr/0005-starter-kit-0-2.md) decision 2

## Purpose and limits

A radial menu: a ring of 4–8 slots around the centre of the screen, where a slot can open a second ring. Other
resources add and remove slots by export, with conditions that decide when a slot shows. The player picks with the
mouse or a gamepad.

Two kinds of slot, so nothing that reaches other players is decided by the client:

- **client slots** (client export) run a client-local event in the owning resource. For things that affect only the
  player who pressed (toggle a HUD part, open the owner's own panel).
- **server slots** (server export) send the pick to the server, which re-checks the slot's conditions with server data,
  then fires a server-local event in the owning resource. For anything that affects other players (give keys, call a
  job, open a shared stash).

Not in 0.1: a third ring level, slot icons from files, per-player slot ordering, a built-in slot set (vehicle doors,
emotes). The kit ships an empty menu; a server fills it.

## Install

```cfg
ensure aeterna_core
ensure aeterna_uikit
ensure aeterna_radial
```

The player binds a key in Settings → Key Bindings → FiveM → "Radial menu" (keyboard or gamepad). The keyboard mapping suggests `F3` by
default (ADR 0004 decision 10, amended 2026-11-22); the gamepad mapping has no default key.

## Configuration

`config.lua` (shipped):

| Key | Default | Meaning |
| --- | --- | --- |
| `Config.mode` | `'hold'` | `hold`: the menu is open while the key is held; releasing it picks the slot under the pointer (or closes when none). `toggle`: press to open, pick with a click or the accept button, press again or ESC to close |
| `Config.radius` | `150` | Ring radius in px at scale 1 (the CSS uses `--fs-*` tokens for labels) |
| `Config.deadZone` | `0.35` | Centre area, as a fraction of the radius (mouse) or of the stick range (gamepad), where no slot is hovered |
| `Config.maxPerOwner` | `64` | Slots one resource may register (client and server counted apart); more are refused with a `warn` |
| `Config.maxTotal` | `128` | Slots across all resources, per side |
| `Config.whileDead` | `false` | When `false`, the menu does not open while the player's ped is dead or ragdolling |

## Slots

### Schema

Written in the `AeternaCore.validate` format ([aeterna_core § Validation](aeterna_core.md#validation)):

```lua
{ type = 'table', fields = {
    id     = { type = 'string', maxLen = 32, pattern = '^[%w_%-]+$' },          -- unique per owner and side
    label  = { type = 'string', maxLen = 20 },
    icon   = { type = 'string', maxLen = 24, optional = true },                 -- uikit icon names (copied map)
    order  = { type = 'number', integer = true, min = 0, max = 1000, optional = true },  -- default 100
    parent = { type = 'string', maxLen = 32, pattern = '^[%w_%-]+$', optional = true },  -- id of a root slot of the same owner
    when   = { type = 'table', optional = true, fields = {
        vehicle = { type = 'string', enum = { 'in', 'out', 'driver' }, optional = true },
        jobs    = { type = 'array', items = { type = 'string', maxLen = 32 }, maxItems = 8, optional = true },
        grade   = { type = 'number', integer = true, min = 0, max = 100, optional = true },  -- needs jobs
        ace     = { type = 'string', maxLen = 64, pattern = '^aeterna%.', optional = true },  -- server slots only
        flags   = { type = 'array', items = { type = 'string', maxLen = 32, pattern = '^[%w_%-]+$' },
                    maxItems = 4, optional = true },                             -- all must be true
    }, extra = false },
}, extra = false }
```

A slot with children is a **group**: picking it opens its ring instead of firing an event. A slot whose `parent` is
itself a child, or names a slot of another owner, is refused (`parent: depth` / `parent: unknown`). A group with no
visible children is hidden.

### Rings

- The root ring shows the visible root slots of every owner, sorted by `order`, then owner, then `id`. A child ring
  shows the visible children of one group, sorted the same way.
- A ring draws `max(4, n)` positions for `n` visible slots (up to 8); positions past `n` are drawn empty and cannot be
  picked. Slot 1 sits at the top; the rest follow clockwise.
- More than 8 visible slots in one ring: the first 8 by sort order show, and one `warn` per open names the owners
  whose slots were cut. The menu never adds a third level to fit them.
- The centre shows the hovered slot's label; in a child ring it also shows "Back".

### Conditions (`when`)

All present conditions must hold. Absent = no condition.

| Condition | Client (decides if the slot shows) | Server (server slots: re-checked on pick) |
| --- | --- | --- |
| `vehicle` | `in`: the ped is in a vehicle · `out`: on foot · `driver`: in the driver seat | Same, from `GetVehiclePedIsIn(GetPlayerPed(src), false)` and the seat ped |
| `jobs` (+ `grade`) | Job name from `qbx_core` player data when `qbx_core` is started; otherwise never true and one `warn` per slot | Same, from `qbx_core` on the server |
| `ace` | Server slots only: the server sends a player only the server slots whose `ace` they pass | `AeternaCore.can(src, ace)` again on pick |
| `flags` | Each flag name, scoped to the owner, must have been set true with `setFlag` on this client | **Not re-checked** — the client holds them. The owner re-checks its own state in its handler |

Custom predicates are flags: resources never pass functions to each other (specs README § Names), so the owner
evaluates its own predicate and calls `setFlag(name, value)` when the result changes. Flags reset when the owner
stops.

## Exports

### Client

| Export | Returns | Notes |
| --- | --- | --- |
| `addSlot(slot)` | `true` or `false, err` | Client slot owned by `GetInvokingResource()`. Same `owner/id` replaces in place. Removed when the owner stops |
| `removeSlot(id)` | boolean | Removes the slot and, for a group, its children |
| `setFlag(name, value)` | nil | `name` ≤ 32 `^[%w_%-]+$`, `value` boolean, scoped to the invoking resource; ≤ 32 flags per owner |
| `isOpen()` | boolean | |
| `close()` | nil | Closes the menu with no pick |

### Server

| Export | Returns | Notes |
| --- | --- | --- |
| `addSlot(slot)` | `true` or `false, err` | Server slot owned by `GetInvokingResource()`, sent to every client that passes its `ace` (now and on join). Removed when the owner stops |
| `removeSlot(id)` | boolean | |

### What comes back

- Client slot picked: client-local event `aeterna_radial:select` → `(owner, id)`. The owner filters on
  `owner == GetCurrentResourceName()`.
- Server slot picked: the client sends `aeterna_radial:sv:select`. The server checks that the slot exists, that the
  player passes `vehicle`, `jobs`/`grade` and `ace` now, then fires server-local `aeterna_radial:select` →
  `(src, { owner, id })`. A pick that fails a check on the server is dropped with a `debug` log; the server sends
  nothing back.
- Before it sends a pick, the client checks the slot's `when` again (the player may have left the car or a flag may
  have flipped since the ring was drawn). If that check fails, the pick is not sent, the centre shows the locale line
  `radial.denied` for 1 s, and the ring stays open. In `hold` mode, when the key is already released, the ring closes
  after that second. A server-side drop gives the player no such line.
- **Not verified yet:** whether the server should tell the client about a dropped pick (an event, so the centre can show
  `radial.denied` for server checks too). Today a pick that passes the client check and fails on the server (for
  example a changed job) closes the ring with no sign. Left open for the owner to decide; no denial event exists in
  0.2.

## Input

| Action | Mouse and keyboard | Gamepad |
| --- | --- | --- |
| Open | The bound key (`+aeterna_radial_open`) | The bound button (same command, gamepad mapper) |
| Hover | Pointer angle from the centre, outside the dead zone | Left stick angle, outside the dead zone |
| Pick | Release the key (`hold`) or left click (`toggle`); in `hold` mode a left click or Enter on the hovered slot, read by the page, also picks while the key is still held | Release the button (`hold`) or accept (`toggle`); accept is ignored while the button is held |
| Back (child ring) | Right click, Backspace, or pick the centre | Cancel button |
| Close | ESC, or release over the centre in the root ring | Cancel button in the root ring |

- Focus: `AeternaCore.requestFocus({ cursor = true, keyboard = false, keepGameInput = true })`, so the player keeps
  walking and driving; camera look and weapon fire are disabled with `DisableControlAction` while the menu is open.
  Losing focus (`aeterna_core:focusLost`) closes the menu with no pick. While another resource holds focus in core's
  overlay mode (for example the test kit's eye card, [aeterna_core § Focus](aeterna_core.md#focus)), the menu is
  paused, not closed: it stays on screen, ignores input, and resumes when focus returns (ADR 0005 decision 7).
- Gamepad sticks and buttons are read with `GetDisabledControlNormal` / `IsDisabledControlJustReleased` on the
  frontend controls; the control ids are constants in `client/input.lua`.
- `AeternaCore.key` maps the keyboard. Radial also calls `RegisterKeyMapping('+aeterna_radial_open', …,
  'PAD_DIGITALBUTTON', '')` itself, with the same literal command and an empty default, so gamepad players can bind
  it too.
- While open in `hold` mode, radial shows one uikit `keyHints` row for pick (the open command `+aeterna_radial_open`, label
  `radial.hint.pick`) and clears it on close. In `toggle` mode it shows no hint, because a uikit hint names a command and
  only the hold-mode pick (release the open key) has one. Back has no command either, so it has no hint row; the centre
  shows `radial.back` (in a child ring) or `radial.close` under the label instead. The locale key `radial.hint.back`
  is shipped but nothing uses it.
- **Not verified yet:** whether a back hint belongs in the kit (it would need either a uikit hint with a fixed label and
  no bound key, or a hint for the Back control). Not decided; 0.2 shows none.
- Releasing the key over a group slot opens that group's ring and the menu stays open, as in `toggle` mode.

## Events (network)

| Event | Direction | Schema | Rate limit |
| --- | --- | --- | --- |
| `aeterna_radial:sv:hello` | client → server | none | 2 / 5000 ms |
| `aeterna_radial:sv:select` | client → server | `{ owner: string ≤ 64, id: string ≤ 32 }` | 4 / 1000 ms |
| `aeterna_radial:cl:slots` | server → client | `{ slots: array ≤ 128 }` (full list of server slots this player may see) | — |
| `aeterna_radial:cl:slot` | server → client | `{ op: 'add'|'remove', owner, slot?, id? }` | — |
| `aeterna_radial:select` | client-local and server-local | see above | — |

`sv:hello` asks for `cl:slots` after the client starts (and after `aeterna_radial` restarts).

## NUI messages

Lua → NUI: `aeterna:theme`, `locale`, `ring:open {slots, mode, radius, deadZone}` (`deadZone` is `Config.deadZone`, so the page and the stick use the same centre; a value outside 0–1 in `Config.deadZone` falls back to 0.35 with a `warn`), `ring:child {groupId, slots}`,
`ring:hover {index}` (gamepad), `ring:denied`, `ring:close`.
NUI → Lua callbacks: `hover {index: number 0–8}`, `pick {index: number 1–8}`, `back {}`, `escape {}`. Each is
validated; an index that does not map to a visible slot is dropped.

## Commands and keys

Permanent names: `aeterna_radial_open` (chat or F8, opens in `toggle` mode), `+aeterna_radial_open`,
`-aeterna_radial_open` (key mapping, keyboard default `F3`, gamepad no default key).

## Storage

None. Slots and flags live in memory and are re-registered by their owners on start.

## Locale keys

`radial.key.open`, `radial.back`, `radial.close`, `radial.denied`, `radial.empty` (shown when the root ring has no
visible slot), `radial.hint.pick`, `radial.hint.back`.

## `oss.json` capabilities

```json
{ "http": [], "commands": [],
  "registeredCommands": ["aeterna_radial_open", "+aeterna_radial_open", "-aeterna_radial_open"],
  "convars": { "read": [], "write": [] },
  "netEvents": { "server": ["aeterna_radial:sv:hello", "aeterna_radial:sv:select"],
                 "client": ["aeterna_radial:cl:slots", "aeterna_radial:cl:slot"] },
  "nui": true, "db": { "tables": [], "ddl": false }, "files": { "write": [] } }
```

No HTTP hosts, no convars, no `SaveResourceFile`.

## Tests

busted (pure logic in `shared/logic/`):

1. Registry: add, replace same `owner/id`, `Config.maxPerOwner` and `Config.maxTotal`, owner stop removes its slots
   and flags only, a child of a child and a cross-owner `parent` are refused.
2. Schema: each limit (label 21 chars, 9 `jobs`, `grade` without `jobs`, `ace` not starting with `aeterna.`, unknown
   icon) fails with its path.
3. Ring building: sort order; `max(4, n)` positions; 9 visible slots show 8 and log one `warn`; a group with no
   visible children is hidden.
4. Conditions: `vehicle` in/out/driver, `jobs` + `grade`, `flags` all-true, missing `qbx_core` makes `jobs` false.
5. Geometry: pointer or stick angle → slot index for 4, 5 and 8 positions; inside the dead zone → none; slot 1 at the
   top, clockwise.
6. Server pick: unknown slot, failed `vehicle`, failed `jobs`, failed `ace` are dropped; a good pick fires one
   `aeterna_radial:select` with `{ owner, id }`.

Smoke (kit-test server, driven from the test menu):

1. Bind a key; with a test resource's 6 client slots and 2 server slots, open in `hold` and `toggle` mode; hover and
   pick each; the test resource logs the right ids.
2. A group with 3 children: open it, Back with right click, Backspace and the centre.
3. Get in and out of a vehicle: `vehicle` slots appear and vanish; set and clear a flag.
4. Gamepad: bind a button, hover with the stick, pick, back, close.
5. Send a forged `aeterna_radial:sv:select` for a slot the player fails: the server drops it.
6. Screenshots in all three theme presets for the owner's visual gate; reduced motion removes all movement.

## Self-tests (0.2)

Registered with `aeterna_core`'s self-test registry; `aeterna_testkit` only lists and runs them.

| name | kind | players | destructive | expect (eye) | skip-when |
| --- | --- | --- | --- | --- | --- |
| `aeterna_radial.registry` | headless | 1 | n | — | — |
| `aeterna_radial.conditions` | headless | 1 | n | — | — |
| `aeterna_radial.server_recheck` | ped | 1 | n | — | presser is in a vehicle (the test needs on foot; it asks to step out) |
| `aeterna_radial.open_pick` | eye | 1 | n | A ring of 6 slots opens around the centre; hovering one highlights it and shows its label in the centre; picking "Test 3" closes the ring and a line "picked Test 3" appears | — |
| `aeterna_radial.child_ring` | eye | 1 | n | Picking the group opens a second ring of 3; right click returns to the first ring with the group still highlighted | — |
| `aeterna_radial.gamepad` | eye | 1 | n | Moving the left stick moves the highlight around the ring; accept picks; cancel closes | — (a presser with no gamepad presses "Skip": GAP) |

`server_recheck` registers a temporary server slot with `when.vehicle = 'in'`, sends a pick while on foot and expects
a drop, then removes the slot. Focus handover between resources is tested by `aeterna_core` itself. The eye tests register temporary slots under the owner `aeterna_radial` and remove them after.

## Done when

All busted cases pass, `fivem-devkit safety` reports 0 errors and 0 over-declared items, `check-kit-graph` accepts
the edges, the smoke steps pass on the kit-test server, the self-tests report PASS or SKIP, and the owner has passed
the screenshots.
