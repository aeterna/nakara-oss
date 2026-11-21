# aeterna_layout

- Package: `packages/layout` · resource `aeterna_layout` · wave W2 · status released in 0.1.0 · spec 0.2.0
  ([0.2 additions](#02-additions) at the end, [ADR 0005](../adr/0005-starter-kit-0-2.md))
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
`AeternaCore.kvp` on Done only, and only for elements moved from their default, so a later change to a default still
reaches players. Reset all takes effect on Done; Cancel undoes it. Places of elements that are not registered right
now are kept, so a resource that is off for a while gets its place back.

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

## Decided

- **Q-L1 — `aeterna_notify` toasts are draggable** (owner, 2026-11-17). ADR 0004's table now has the optional edge
  `aeterna_notify` → `aeterna_layout`, local events only. Notify registers `toasts` and `announce`
  ([aeterna_notify § Position](aeterna_notify.md#position-and-aeterna_layout)).
- **Q-P1 — the phone is draggable** (owner, 2026-11-17). Same optional edge for `aeterna_phonekit`; it registers
  `phone` ([aeterna_phonekit § Position](aeterna_phonekit.md#position-and-aeterna_layout)).

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

---

## 0.2 additions

- Version: 0.2.0 ([ADR 0005](../adr/0005-starter-kit-0-2.md) decision 1) · edges unchanged: `aeterna_core`,
  `aeterna_uikit`
- Written by: Claude Code - Claude Opus 5.5 (helper)

Everything above stays valid. Already in 0.1, so not new here: re-adding an `owner/id` with a new size replaces the
element; grid snap (`Config.snap`, the toolbar's Snap on/off, Shift to drag without snap); **Reset this** and
**Reset all** (with a confirm); clamping on drop.

| What | New in 0.2 |
| --- | --- |
| Clamp on size change | an element that grows (a re-add with a new `w`/`h`, a scale change, a resolution change) is moved back on screen, also outside the editor |
| Presets | three layouts the player can apply in the editor |
| Grid | the grid is drawn while dragging, and the step can be picked |
| Reset | Reset all also offered outside the editor, from the menu entry's panel |
| Export / import | the player's layout as a line of text to copy and paste |

### Configuration (0.2)

| Key | Default | Meaning |
| --- | --- | --- |
| `Config.menuPanel` | `true` | The menu entry opens the Edit / Reset all / Export-import panel; `false` = 0.1 behaviour (opens the editor) |
| `Config.presets` | three presets | Preset layouts (below), up to 8 |
| `Config.snapSteps` | `{ 8, 16, 32 }` | Snap steps offered in the editor; `Config.snap` stays the default |

### Clamp when an element's size changes

0.1 clamps only when the player drops an element. In 0.2 layout also clamps when:

1. an owner sends `aeterna_layout:add` again for an existing `owner/id` with a different `w` or `h` (for example the
   phone opening into a wide screen, or hudkit switching to ring bars);
2. the player changes an element's `scale`;
3. the screen size changes (layout's page reports `innerWidth` / `innerHeight` on `resize`).

Rule: layout computes the element's box from the saved place (or the default) and the new size. If any edge is off
screen, it moves the anchor point just far enough that the whole box is on screen (same maths as the drop clamp,
`ax` / `ay` unchanged) and sends `aeterna_layout:apply` with the clamped place.

- The clamped place is **not saved**. The saved place stays what the player chose, so when the element shrinks back
  (the phone folds) it returns to exactly where it was.
- An element larger than the screen is placed at the top-left corner of the screen (`x`, `y` so its box starts at
  0, 0), still unsaved.
- In the editor, the stand-in follows the clamped place, and Done saves what the stand-in shows.
- Owners need no change: they already apply every `aeterna_layout:apply`.

### Presets

Three layouts ship in `config.lua` as plain data:

| Preset | What it does |
| --- | --- |
| `default` | Every element at its owner's default (the same as Reset all) |
| `compact` | Kit elements grouped in the bottom-left corner around the minimap at scale 0.85; toasts top-left |
| `centered` | Status and vehicle at the bottom centre, compass and announcement at the top centre, toasts top-right |

```lua
Config.presets = {
  default  = {},                                   -- empty = owners' defaults
  compact  = { ['aeterna_hudkit/status'] = { x = 0.17, y = 0.97, ax = 0, ay = 1, scale = 0.85 }, … },
  centered = { … },
}
```

- A preset is a map of `"<owner>/<id>"` → place, checked with the same rules as a drop (fractions 0–1, anchors in
  `{0, 0.5, 1}`, scale in range). A bad entry is skipped with one `warn` at start; the rest of the preset still
  works.
- Keys may name elements of any resource; layout does not need the owner to exist. Elements a preset does not name
  go to their default. Places for elements that are not registered right now are kept for when they register (the
  0.1 storage rule).
- The editor toolbar gains a **Preset** select. Picking one changes the session only: the stand-ins and the real
  elements move at once, Done saves, Cancel and ESC undo it. Every placed element is clamped as above.
- `hidden` is never set by a preset; hiding stays the player's choice.
- A server owner may edit or add presets in `config.lua` (up to 8; names ≤ 24 matching `^[%w_%-]+$`, with a locale
  key `layout.preset.<name>` or the name itself as the label).

### Grid

- While dragging, the grid at the current step is drawn faintly over the screen (`--line`); it is not drawn when
  snap is off or Shift is held.
- The toolbar's Snap control becomes a select: Off · 8 · 16 · 32 px (`Config.snapSteps = { 8, 16, 32 }`). The pick
  is kept in the KVP below. `Config.snap` stays the default for players who have not picked.

### Reset outside the editor

**Changed in 0.2** (`Config.menuPanel`, default `true`). The `aeterna_uikit` menu entry "Edit HUD layout" now opens a
small uikit panel with three buttons: **Edit**, **Reset all** (asks to confirm, then saves at once) and **Export /
import**. The command `aeterna_layout` and the key mapping still open the editor directly, as in 0.1. Reason: a player
who cannot see an element can still recover without dragging. Upgrade note: `Config.menuPanel = false` keeps the 0.1
behaviour (the menu entry opens the editor directly); Reset all and Export / import are then reached only from the
editor toolbar.

### Editor while paused

When another resource takes focus through `aeterna_core`'s focus overlay (core 0.2, [aeterna_core.md](aeterna_core.md) §
Focus), the editor stays open with its session (moves not yet saved), ignores input and sends no `apply`; when focus
comes back the player continues. A real focus loss still counts as Cancel, as in 0.1.

### Export and import as text

Export gives one line of text the player can copy; import takes such a line.

Format: the prefix `aeterna-layout:1:` followed by JSON:

```json
{ "v": 1, "places": { "aeterna_hudkit/status": { "x": 0.17, "y": 0.97, "ax": 0, "ay": 1, "scale": 0.85, "hidden": false } } }
```

| Rule | Limit |
| --- | --- |
| Whole text | ≤ 8192 bytes; must start with `aeterna-layout:1:` |
| `v` | `1` (other versions are refused with `layout.import.version`) |
| `places` | ≤ `Config.maxElements` entries (64) |
| Key | `<owner>/<id>`: `owner` ≤ 64 matching `^[%w_%-]+$`, `id` per the `def` rule |
| Place | same checks as the NUI `moved` callback; `hidden` boolean, default `false` |
| Extra fields | anywhere: refused (no silent extras) |

- Export writes every saved place (the KVP content), not defaults, so a short text means "mostly defaults".
- Import runs in the editor session: a valid text replaces the session's places, the stand-ins move, Done saves,
  Cancel undoes. A text with any error is refused as a whole and shows the first error path (for example
  `places["aeterna_hudkit/status"].scale: out of range`); nothing changes.
- Parsing happens in Lua (`json.decode` inside `pcall`, then the pure validator in `shared/logic/`), never in the
  page. The page shows the text with `textContent` / a `<textarea>` value only.
- Copying: the export text sits in a read-only `<textarea>`, selected on open, so Ctrl+C copies it. Whether
  `document.execCommand('copy')` works in CEF without a user gesture is **not verified yet**; a Copy button is added
  only if the `export_copy` self-test passes.
- The text never leaves the player's machine through layout: no net event, no HTTP.

### NUI messages (0.2)

Lua → NUI adds `editor:clamp {owner, id, place}`, `editor:presets {list}`, `export:show {text}`,
`import:result {ok, error?}`.
NUI → Lua adds `preset {name}`, `snap {step}`, `import {text}` (≤ 8192 bytes, checked before parsing),
`exportOpen {}`, `screen {w, h}` (positive integers ≤ 16384).

### Commands and keys (0.2)

No new command. The panel above opens from the existing menu entry.

### Storage (0.2)

`aeterna_layout:places:v1` is unchanged. New client KVP `aeterna_layout:prefs:v1` = `{ snap = 0 | 8 | 16 | 32 }`.

### Type tokens

0.1 sets pixel sizes in `style.css`. 0.2 uses the theme type tokens (ADR 0005 decision 9; `--fs-1` smallest …
`--fs-5` largest, line height `--lh`): stand-in labels and the selected element's scale read-out `--fs-1`, toolbar
and inspector controls `--fs-3`, the editor title `--fs-4`, the export text `--fs-2` in a monospace stack.

### Locale keys (0.2)

`layout.editor.preset`, `layout.preset.default`, `layout.preset.compact`, `layout.preset.centered`,
`layout.editor.snapOff`, `layout.menu.edit`, `layout.menu.resetAll`, `layout.menu.share`, `layout.export.title`,
`layout.export.hint`, `layout.import.title`, `layout.import.apply`, `layout.import.ok`, `layout.import.version`,
`layout.import.invalid`.

### `oss.json` (0.2)

No change: the panel uses uikit's existing server exports and the `aeterna_uikit:action` event, and layout's
existing `aeterna_layout:cl:open` event (which gains an optional `{ mode = 'editor' | 'share' }` payload).

### Tests (0.2, busted)

1. Size-change clamp: an element at the right edge grows from 320 to 780 px wide → the box ends at the right edge;
   shrinking back returns the saved place exactly; the saved place never changes; a box larger than the screen goes
   to 0, 0.
2. Scale and resolution clamp: scale 2.0 at the bottom edge, and 3440 → 1280 px width, keep the box on screen.
3. Presets: each shipped preset passes validation; a bad entry is skipped with one `warn`; a preset applies to the
   session only (Cancel restores the snapshot); unnamed elements go to default; `hidden` is never changed.
4. Export: output starts with the prefix, holds only saved places, round-trips through import to the same places.
5. Import: 8193 bytes, wrong prefix, `v = 2`, 65 entries, a bad key, a scale out of range, an extra field are each
   refused whole with the right path; a refused import changes nothing.
6. Snap prefs: only 0, 8, 16, 32 are accepted; KVP round trip; no saved value uses `Config.snap`.

### Self-tests (0.2)

Registered as `aeterna_layout.<name>`. "Skip when" is the only reason the test may report SKIP; a ped or eye test
with no person to run it reports GAP (ADR 0005 decision 7). A headless test needs no player and is listed as 1.

Kind `headless (client)` / `mock (client)` = `side = 'client'`: the test runs on the presser's client and is GAP
when there is no presser (ADR 0005 decision 7, W0 fix D3). Plain `headless` / `mock` run on the server.

| Name | Kind | Players | Destructive | Expect (what a person should see) | Skip when |
| --- | --- | --- | --- | --- | --- |
| `placement_math` | headless | 1 | n | — | never |
| `import_validate` | headless | 1 | n | — | never |
| `clamp_on_grow` | mock (client) | 1 | n | — (a test element at the right edge is re-added twice as wide; the test checks the applied place is on screen, then removes the element) | — |
| `preset_apply` | eye | 1 | n | Picking `compact` moves every kit element to the bottom-left; Cancel puts them back | — |
| `grid_drag` | ped | 1 | n | While dragging, a faint grid at the picked step shows and the element lands on it; with Shift it does not | — |
| `export_import` | ped | 1 | n | Export shows one line of text; changing a place and importing that text puts it back | — |
| `export_copy` | ped | 1 | n | Ctrl+C in the export box copies the text; pasting it into import is accepted | — |
| `reset_from_menu` | ped | 1 | y | The menu panel's Reset all, after confirming, puts every element at its default (the player's saved layout is cleared) | — |

`reset_from_menu` is destructive because it clears the presser's saved layout; it runs only when the test kit allows
destructive tests (ADR 0005 decision 7) and exports the layout first so the presser can import it back.

### Done when (0.2)

The 0.1 conditions, plus: the busted cases above pass, every self-test above is registered and passes on the
kit-test server (SKIP only for its listed reason), and the owner has passed screenshots of the editor with each
preset, the grid while dragging and the export box in all three theme presets.
