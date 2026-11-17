# aeterna_layout

- Package: `packages/layout` · resource `aeterna_layout` · wave W2 · status draft
- Depends on: `aeterna_core` (focus, KVP, locale, keys) and `aeterna_uikit` (menu entry)
- Proven by spikes S1 and S3 (ADR 0004 decision 12, 2026-11-17)

## Purpose and limits

Lets each player move and resize HUD elements that **other resources** draw, and keeps their choice on their own
machine. Every NUI page is its own frame, so no resource can drag another's DOM. Layout works as a coordinate
protocol: an owner resource describes its element, layout draws a stand-in box in its own frame for the player to
drag, then tells the owner where the element now sits. The owner moves its own element.

An element can be drawn by NUI (a health bar, a toast stack) or by the game itself (the minimap). Layout does not
care which: it only sends coordinates. Game-drawn elements are moved by their owner with natives
(`aeterna_hudkit` owns the minimap, see its spec).

Not in v0.1: rotating elements, free-form resizing of width and height separately, per-server shared presets,
syncing layouts between a player's machines, moving base-game HUD components other than the minimap.

## Install

```cfg
ensure aeterna_core
ensure aeterna_uikit
ensure aeterna_layout
```

Order among owners does not matter: an owner that starts before layout registers again when layout announces itself.

## Configuration

`config.lua` (shipped):

| Key | Default | Meaning |
| --- | --- | --- |
| `Config.snap` | `8` | Grid step in px while dragging; `0` turns snapping off. Holding Shift drags without snap |
| `Config.scale.min` / `.max` / `.step` | `0.5` / `2.0` / `0.05` | Scale range offered in the editor |
| `Config.maxElements` | `64` | Elements in the registry; more are refused with a `warn` |
| `Config.menu` | `true` | Adds the "Edit HUD layout" entry to the `aeterna_uikit` menu |

No convars.

## The coordinate model

All positions are fractions of the screen, so a layout survives a resolution change.

- `x`, `y` (0–1): where the element's **anchor point** sits on the screen.
- `ax`, `ay` (each `0`, `0.5` or `1`): which point of the element is the anchor. `0, 0` = top-left corner,
  `1, 1` = bottom-right, `0.5, 0.5` = centre.
- `scale` (`Config.scale.min`–`max`): the owner multiplies its own size by it.

The owner places its element at `left = x × screenWidth − ax × width × scale` and
`top = y × screenHeight − ay × height × scale`. When the player drops an element, layout picks the anchor from
the nearest screen edge (left third → `ax = 0`, middle third → `0.5`, right third → `1`; same for `ay`). An element
dropped near the right edge therefore stays glued to it on a wider screen. Layout clamps every drop so the whole
element stays on screen.

## Owner protocol (client, local events)

Owners talk to layout with local client events, never with exports or functions, so an owner works with or without
layout running (decision Q-L1 below) and a restarted resource leaves nothing stale.

| Event | Fired by | Payload | Meaning |
| --- | --- | --- | --- |
| `aeterna_layout:add` | owner | `def` (below) | Register or replace one element |
| `aeterna_layout:remove` | owner | `id` | Remove one element |
| `aeterna_layout:hello` | layout | — | Fired once when layout's client starts; owners send their `add` again |
| `aeterna_layout:apply` | layout | `owner, id, place` | `place = { x, y, ax, ay, scale, hidden }`. Owners act only when `owner == GetCurrentResourceName()` |

The owner comes from the runtime, not the payload, so one resource cannot move another's elements. Spike S1
put the owner in the payload. Whether `GetInvokingResource()` names the triggering resource inside a handler of a
local `TriggerEvent` is **not verified yet**; the first W2 task checks it on the kit-test server. If it does not,
`def.owner` is required and must equal a started resource. That only lets a resource the server owner installed move
another's element on that one client, and the gap is written in the package README.

`def` schema:

| Field | Type | Rule |
| --- | --- | --- |
| `id` | string | ≤ 32, `^[%w_%-]+$`, unique per owner |
| `label` | string | Locale key of the owner, or plain text ≤ 32; shown on the stand-in |
| `w`, `h` | number | Size in CSS px at scale 1, 8–2000. NUI owners measure their element (`getBoundingClientRect`); game-drawn owners convert from their native units |
| `x`, `y`, `ax`, `ay` | number | Default place, same meaning as above |
| `scalable` | boolean | Default `true`. `false` hides the scale control for this element |
| `hideable` | boolean | Default `false`. `true` lets the player hide it from the editor |

When an element is added, layout sends `aeterna_layout:apply` right away with the player's saved place, or with the
default when there is none. When an owner resource stops, its elements leave the registry (saved places stay).

## Editor

Opened from the `aeterna_uikit` menu entry, the command `aeterna_layout`, or the key mapping `+aeterna_layout_edit`
(no default key, ADR 0004 decision 10). Layout asks `aeterna_core` for focus (`cursor`, `keyboard`).

- Full-screen transparent layer. Each element gets a dashed stand-in box at its place and size with its label.
- Drag with the mouse. The owner gets `apply` at most every 100 ms while dragging and once on drop, so the real
  element follows live (S1). Snap to `Config.snap` unless Shift is held.
- Keyboard: Tab moves between elements, arrow keys nudge 1 px, Shift + arrow 10 px, `+` / `−` change scale.
- Selected element: a small panel with scale, "Reset this", and "Hide" when `hideable`.
- Bottom toolbar: Snap on/off, Reset all (asks to confirm), Cancel, Done.
- **Done** saves and closes. **Cancel** or ESC puts every element back where it was when the editor opened, then
  closes. Losing focus (`aeterna_core:focusLost`) counts as Cancel.
- Outside the editor the page draws nothing and never takes input.

## Events (network)

| Event | Direction | Schema | Rate limit |
| --- | --- | --- | --- |
| `aeterna_layout:cl:open` | server → client | none | — |

The server's only job is the menu entry: on `aeterna_uikit:menu` with `owner == 'aeterna_layout'` it sends
`aeterna_layout:cl:open` to that player. There is no client → server event; layouts never leave the player's machine.

## NUI messages

Lua → NUI: `aeterna:theme`, `locale`, `editor:open {elements, snap, scale}`, `editor:close`.
NUI → Lua callbacks: `moved {owner, id, x, y, ax, ay, scale}`, `hide {owner, id, hidden}`, `reset {owner?, id?}`,
`done {}`, `cancel {}`. Each is validated (fractions 0–1, anchors in `{0, 0.5, 1}`, scale in range, `owner` and `id`
present in the registry) before it is applied.

## Commands and keys

`aeterna_layout` (chat or F8), `+aeterna_layout_edit` / `-aeterna_layout_edit` registered with literal names and mapped
through `AeternaCore.key` with no default key.

## Storage

KVP `aeterna_layout:places:v1` = `{ ["<owner>/<id>"] = { x, y, ax, ay, scale, hidden } }`, written through
`AeternaCore.kvp` on Done and on Reset all. Places of elements that are not registered right now are kept, so a
resource that is off for a while gets its place back.

## Locale keys

`layout.menu.entry`, `layout.key.edit`, `layout.editor.title`, `layout.editor.snap`, `layout.editor.reset`,
`layout.editor.resetAll`, `layout.editor.resetAllConfirm`, `layout.editor.hide`, `layout.editor.show`,
`layout.editor.scale`, `layout.editor.cancel`, `layout.editor.done`, `layout.editor.empty`.

## `oss.json` capabilities

```json
{ "http": [], "commands": [],
  "registeredCommands": ["aeterna_layout", "+aeterna_layout_edit", "-aeterna_layout_edit"],
  "convars": { "read": [], "write": [] },
  "netEvents": { "server": [], "client": ["aeterna_layout:cl:open"] },
  "nui": true, "db": { "tables": [], "ddl": false }, "files": { "write": [] } }
```

## Decisions for the owner

- **Q-L1 — `aeterna_notify` toasts and the dependency table.** ADR 0004's table gives `aeterna_notify` no edge to
  `aeterna_layout`, so toasts stay at `Config.toast.position` in v0.1. Because the protocol is local events, an
  owner needs no hard dependency: notify could fire `aeterna_layout:add` and listen for `apply`, and nothing changes
  when layout is absent. Recommendation: add the row "`aeterna_notify` → `aeterna_layout` (optional, local events
  only)" to the table in ADR 0004 before W2, so players can move toasts too.

## Tests

busted (pure logic in `shared/logic/`):

1. Placement: `left`/`top` from `x, y, ax, ay, scale` for each anchor; round trip drop → place → pixels within 1 px.
2. Anchor choice: drops in each third pick the right `ax`/`ay`.
3. Clamp: a drop past any edge keeps the whole element on screen at every scale.
4. Snap: positions land on the grid; Shift (no snap) keeps the raw value.
5. Schema: bad `id`, size out of range, anchor `0.3`, scale outside the range are refused with a `warn`.
6. Registry: re-adding the same `owner/id` replaces it; an owner stopping removes only its own elements;
   `Config.maxElements` refuses the extra one.
7. Storage: Done writes, Cancel does not; places of unregistered elements survive a save.

Smoke (kit-test server, driven from a button menu, not typed commands):

1. Two NUI owners and one game-drawn owner (the hudkit minimap): every stand-in covers its real element.
2. Drag each one: the real element follows while dragging; Done keeps it; reconnect keeps it.
3. Cancel and ESC put everything back; Reset this and Reset all go to defaults.
4. Scale an element: the owner redraws at the new size and the stand-in matches it.
5. Change resolution and safe zone: right-anchored elements stay on the right edge; stand-ins still cover.
6. Restart an owner while the editor is open: its stand-in disappears and comes back with its saved place.
7. Keyboard only: Tab, arrows and `+`/`−` move and scale an element without the mouse.
8. Screenshots of the editor in Asphalt for the owner's visual gate.

## Done when

All busted cases pass, `fivem-devkit safety` reports 0 errors and 0 over-declared items, the smoke steps pass on the
kit-test server, and the owner has passed the screenshots.
