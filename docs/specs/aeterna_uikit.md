# aeterna_uikit

- Package: `packages/uikit` · resource `aeterna_uikit` · wave W1 · status released in 0.1.0 · spec 0.2.0
  ([0.2 additions](#02-additions) at the end, [ADR 0005](../adr/0005-starter-kit-0-2.md))
- Depends on: `aeterna_core`
- Used by: `aeterna_layout`, `aeterna_hudkit`, `aeterna_phonekit`, `aeterna_invkit`

## Purpose and limits

Panels a server builds and a player answers, plus the small client prompts every server needs: confirm, input,
progress, skill check and key hints. A menu collects entry points from other resources.

The server owns every panel: it sends a spec, the client renders it, and only button and field values listed in that
spec come back. uikit never decides what a button does; the resource that opened the panel does.

Not in v0.1: drag-and-drop (that is `aeterna_layout`), toasts (`aeterna_notify`), world markers or 3D text.

## Install

```cfg
ensure aeterna_core
ensure aeterna_uikit
```

## Configuration

| Convar | Default | Meaning |
| --- | --- | --- |
| `aeterna_uikit_menu_title` | empty | Title of the menu; empty = locale `uikit.menu.title` |

## Panels (server)

### Exports

| Export | Returns | Notes |
| --- | --- | --- |
| `open(src, spec)` | panelId (string) or nil, err | Validates `spec` (below). One panel per player: opening a new one closes the old one with reason `replaced`. |
| `update(src, panelId, patch)` | boolean | `patch = { blocks = { [blockId] = partialBlock } }`; only `label`, `value`, `items`, `disabled` may change. |
| `close(src, panelId?)` | boolean | No `panelId` = whatever is open. |
| `isOpen(src)` | panelId or nil | |

### Spec

```lua
{
  title = 'string ≤ 60',  subtitle = 'string ≤ 120, optional',
  size = 'sm' | 'md' | 'lg',            -- 360 / 480 / 720 px wide
  blocks = {                             -- ≤ 40 blocks, rendered in order
    { id = 'intro', type = 'text', label = '≤ 400 chars' },
    { id = 'pick',  type = 'list', items = {          -- ≤ 50 items
        { id = 'a', label = '≤ 60', meta = '≤ 30, optional', icon = 'name, optional', disabled = false } } },
    { id = 'qty',   type = 'field', label = '≤ 40', input = 'text' | 'number',
      value = '', min = 1, max = 100, maxLen = 60, placeholder = 'optional' },
    { id = 'on',    type = 'toggle', label = '≤ 40', value = false },
    { id = 'mode',  type = 'select', label = '≤ 40', options = { { id = 'x', label = '≤ 40' } }, value = 'x' },
    { id = 'load',  type = 'progress', label = '≤ 40', value = 0.4 },          -- 0..1, display only
    { id = 'sep',   type = 'divider' },
    { id = 'act',   type = 'buttons', items = {                                 -- ≤ 4 buttons
        { id = 'ok', label = '≤ 24', variant = 'primary' | 'secondary' | 'danger' } } },
  },
}
```

Ids are ≤ 32 characters matching `^[%w_%-]+$` and unique within the spec. `panelId` is `p` + a base-36 counter (≤ 24). Unknown block types, unknown icon names or anything over a limit
make `open` return `nil, '<path>: <rule>'`.

### What comes back

When the player presses a button, picks a list item, or closes the panel, the server fires the **server-local** event
`aeterna_uikit:action` with:

```lua
(src, { owner = 'resource_that_opened', panelId = '…', action = 'ok' | '<list item id>' | '__close',
        values = { qty = 3, on = true, mode = 'x' } })
```

- `action` must be a button id or list item id from the open spec, or `__close`; anything else is dropped.
- `values` holds only `field`, `toggle` and `select` blocks, each re-checked against its own block (type, min/max,
  maxLen, option ids) and cleaned with `AeternaCore.text.clean`.
- The opening resource filters on `owner == GetCurrentResourceName()`. Cross-resource function references are never
  used, so a restarted resource cannot leave a stale callback behind.

## Client prompts

Client exports. Each one takes focus through `aeterna_core`, returns when the player answers, and gives focus back.
If focus is lost (`aeterna_core:focusLost`), the prompt resolves as cancelled.

| Export | Returns | Notes |
| --- | --- | --- |
| `confirm({ title, body?, confirm?, cancel?, danger? })` | boolean | Labels default to locale `uikit.confirm.ok` / `uikit.confirm.cancel`. |
| `input({ title, fields = { {id, label, input, min?, max?, maxLen?, value?} } })` | table or nil | ≤ 6 fields; values checked as in panels. |
| `progress({ label, duration, cancelable?, disable? })` | boolean (client-reported; see README § Payloads) | `duration` 300–60000 ms. `disable = { move, car, combat, mouse }` blocks those controls while it runs. Cancel key = the player's binding for `+aeterna_uikit_cancel` (no default) or ESC when the mouse is free. Returns `true` when it finished. Does not take focus. |
| `skillCheck({ difficulty = 'easy'|'medium'|'hard', rounds = 1..5 })` | boolean (client-reported) | A moving marker and a target zone. The player presses the key bound to `+aeterna_uikit_skill` (no default), or Space (see the note below). |
| `keyHints(list)` / `clearKeyHints()` | nil | `list = { {key = 'command name', label = '≤ 30'} }`, ≤ 4 rows. Shows the player's real binding for that command via `GetControlInstructionalButton`; unbound shows locale `uikit.key.unbound`. |

Note on `skillCheck`: while a check runs, Space is read through the jump control and jumping is disabled with
`DisableControlAction`, because a check with no bound key would be unusable. It is not a key mapping, but it is a
default input, so ADR 0004 decision 10 lists it as its one exception (with ESC, which closes panels).

## Menu

| Export (server) | Notes |
| --- | --- |
| `addMenuEntry(entry)` | `entry = { id, label, icon, order = 100, group = 'general', ace = 'aeterna.… optional' }`. `id` unique per owner resource. Removed automatically when the owner stops. |
| `removeMenuEntry(id)` | |
| `showMenu(src)` | |

The menu opens with the key mapping `+aeterna_uikit_menu` (no default) or the command `aeterna_uikit_menu`. It shows
only entries whose `ace` the player has. When the player picks one, the server checks again that the entry still
exists and that the player has its `ace`, then fires the server-local event `aeterna_uikit:menu` → `(src, { owner, id })`;
the owner opens its own panel.

## Events

| Event | Direction | Schema | Rate limit |
| --- | --- | --- | --- |
| `aeterna_uikit:sv:action` | client → server | `{ panelId: string ≤ 24, action: string ≤ 32, values: table ≤ 40 keys }` | 10 / 1000 ms |
| `aeterna_uikit:sv:menu` | client → server | `{ id: string ≤ 32, owner: string ≤ 64 }` | 5 / 1000 ms |
| `aeterna_uikit:sv:showMenu` | client → server | none | 2 / 1000 ms |
| `aeterna_uikit:cl:open` | server → client | spec + `panelId` | — |
| `aeterna_uikit:cl:update` | server → client | `{ panelId, patch }` | — |
| `aeterna_uikit:cl:close` | server → client | `{ panelId, reason }` | — |
| `aeterna_uikit:action` | server-local | see above | — |
| `aeterna_uikit:menu` | server-local | `{ owner, id }` | — |

## NUI messages

Lua → NUI: `aeterna:theme`, `panel:open`, `panel:update`, `panel:close`, `prompt:confirm`, `prompt:input`,
`prompt:progress`, `prompt:skill`, `hints:show`, `hints:clear`, `locale` (the strings the page needs).

NUI → Lua callbacks: `panelAction {panelId, action, values}`, `promptResult {kind, value}`, `escape {}`. Each is
validated with the same schemas before it is forwarded.

## Commands and keys

`aeterna_uikit_menu` (chat or F8), `+aeterna_uikit_menu`, `+aeterna_uikit_cancel`, `+aeterna_uikit_skill` — all
without a default key. Each `+`/`-` pair is registered with literal names in uikit's client code.

## Icons

An inline map of Lucide icons (ISC) under these names; specs may use only these: `home bell box user users phone
message-circle calculator file-text settings sliders map map-pin car wrench shield heart droplet utensils clock calendar
info alert-triangle check x plus minus search lock unlock key star flag trash log-out log-in chevron-right
chevron-left arrow-up arrow-down`.

## Storage

None in v0.1.

## Locale keys

`uikit.menu.title`, `uikit.confirm.ok`, `uikit.confirm.cancel`, `uikit.input.submit`, `uikit.progress.cancel`,
`uikit.skill.title`, `uikit.skill.bind`, `uikit.key.unbound`, `uikit.close`, `uikit.key.menu`, `uikit.key.cancel`,
`uikit.key.skill`.

## `oss.json` capabilities

```json
{ "http": [], "commands": [], "registeredCommands": ["aeterna_uikit_menu", "+aeterna_uikit_menu", "-aeterna_uikit_menu",
  "+aeterna_uikit_cancel", "-aeterna_uikit_cancel", "+aeterna_uikit_skill", "-aeterna_uikit_skill"],
  "convars": { "read": ["aeterna_uikit_menu_title"], "write": [] },
  "netEvents": { "server": ["aeterna_uikit:sv:action", "aeterna_uikit:sv:menu", "aeterna_uikit:sv:showMenu"],
                 "client": ["aeterna_uikit:cl:open", "aeterna_uikit:cl:update", "aeterna_uikit:cl:close"] },
  "nui": true, "db": { "tables": [], "ddl": false }, "files": { "write": [] } }
```

## Tests

busted:

1. Spec validation: a full valid spec passes; each limit (title 61 chars, 41 blocks, 51 items, 5 buttons, duplicate
   id, unknown icon, unknown type) fails with its path.
2. Action filter: an action id not in the spec, or for a closed panel, is dropped; `__close` always passes.
3. Values: number out of range, string over `maxLen`, select option not in list, and an extra key are each dropped;
   good values pass cleaned.
4. `update` refuses fields other than `label`, `value`, `items`, `disabled`.
5. Menu: entries are filtered by ACE and sorted by `order` then `label`; an owner's entries vanish when it stops; a
   pick for an entry the player lacks ACE for, or that no longer exists, is dropped.

Smoke:

1. A test resource opens a `md` panel with every block type; screenshot in Asphalt for the owner's visual gate.
2. Press each button and pick a list item: the test resource logs the expected `action` and `values`.
3. Send a forged `aeterna_uikit:sv:action` with an unknown action from the client console: the server logs a drop.
4. `confirm`, `input`, `progress` (cancel and finish), `skillCheck`, `keyHints` with bound and unbound keys.
5. Open a panel, then a second resource takes focus: the panel closes and the owner gets `__close`.
6. ESC closes every panel and prompt; keyboard-only use reaches every control with a visible focus ring.

## Done when

All busted cases pass, `fivem-devkit safety` reports 0 errors and 0 over-declared items, the smoke steps pass, and
the owner has passed the screenshots (ADR 0004 gate G3).

---

## 0.2 additions

- Version: 0.2.0 ([ADR 0005](../adr/0005-starter-kit-0-2.md) decision 1) · edges unchanged: `aeterna_core` only
- Written by: Claude Code - Claude Opus 5.5 (helper)

Everything above stays valid. A 0.1 spec opens and behaves the same in 0.2. This part only adds; the one widened
rule is marked **Changed in 0.2**.

Already in 0.1, so not new here: `toggle`, `select`, `field`, `progress`, `divider`, `list`, `buttons`, the client
prompts, the menu, and the panel card's `transition` declaration (0.1 never adds or removes a class that uses it, so
panels appear and vanish with no motion).

| What | New in 0.2 |
| --- | --- |
| Block types | `tabs`, `slider`, `table`, `empty` |
| `list` | optional `search` box and a higher item limit when it is on; optional `empty` |
| Spec field | `detailOf` and `detailItem` (a screen that is the detail of a list item) |
| Motion | enter and exit animation for panels and prompts, removed under reduced motion |
| Type | sizes come from the theme type tokens |

### New block types

```lua
-- tabs: at most one per spec, 2-6 tabs. Blocks with `tab` show only while that tab is active.
{ id = 'tabs', type = 'tabs', items = { { id = 'parts', label = '≤ 24', icon = 'name, optional' } },
  value = 'parts', report = false },
{ id = 'q', type = 'field', label = 'Search parts', tab = 'parts' },      -- any block may carry `tab`

-- slider: a number in [min, max] on a step grid.
{ id = 'vol', type = 'slider', label = '≤ 40', min = 0, max = 100, step = 5, value = 50, unit = '≤ 8, optional' },

-- table: ≤ 6 columns, ≤ 50 rows; a cell is plain text ≤ 40.
{ id = 'log', type = 'table',
  columns = { { id = 'when', label = '≤ 24', align = 'start' | 'end' } },
  rows = { { id = 'r1', cells = { when = '21:47' }, disabled = false } },
  selectable = false, empty = { icon = 'name, optional', label = '≤ 60', body = '≤ 160, optional' } },

-- empty: a stand-alone empty state with one optional button.
{ id = 'none', type = 'empty', icon = 'box', label = '≤ 60', body = '≤ 160, optional',
  action = { id = 'add', label = '≤ 24' } },
```

Rules (each failure makes `open` return `nil, '<path>: <rule>'` as in 0.1):

| Block | Rule |
| --- | --- |
| `tabs` | One per spec. 2–6 `items`, ids follow the id rule and are unique in the whole spec. `value` must be one of them (default: the first). A block's `tab` must name an item of the spec's `tabs` block; `tab` on a spec without `tabs` fails. `tabs` itself cannot carry `tab`. |
| `tabs` switching | Happens in the page, with no round trip. The active tab id comes back in `values[<tabs id>]`. With `report = true`, a switch also fires `aeterna_uikit:action` with `action = <tab item id>` so the owner can load that tab's content through `update`. |
| `slider` | `min < max`, `step > 0`, `(max − min) / step ≤ 1000`, `value` inside the range (default `min`). Comes back as a number in `values`, re-checked on the server: outside the range or off the step grid (tolerance 1e-6 × step) is dropped. Keyboard: arrows move one step, Page Up / Page Down ten steps, Home / End jump to the ends. |
| `table` | 1–6 `columns`, 0–50 `rows`, unique ids; `cells` keys must be column ids; a missing cell shows empty. `selectable = true` makes each row a button: picking it fires `action = <row id>` (row ids join the list of allowed actions). Header cells are not sortable in 0.2. |
| `empty` (block) | `label` required. `action.id` joins the list of allowed actions. |
| `list.search` | `search = { placeholder = '≤ 40, optional' }` or `true`. Filters the items in the page by `label` and `meta`, case-insensitive, no round trip. With search on, the item limit is 200 instead of 50; without it, 50 as in 0.1. |
| `empty` (option) | `list` and `table` accept `empty = { icon?, label, body? }`, shown when `items` / `rows` is empty or the search matches nothing. |

**Changed in 0.2 — `update`.** `patch` may also change `rows` (table), `value` of `tabs` and `slider`, and
`empty`. The 0.1 keys (`label`, `value`, `items`, `disabled`) behave as before. Reason: tables and tabs are useless
if the owner cannot refresh them. Upgrade note: none; a 0.1 caller never sends the new keys.

`values` in `aeterna_uikit:action` now also holds `slider` and `tabs` blocks. Limits for the whole spec stay: ≤ 40
blocks, each id unique.

### `detailOf` — a screen that details one list item

Top-level spec fields, both optional:

```lua
{ title = 'Mind', detailOf = 'contacts', detailItem = 'c42', blocks = { … } }
```

- `detailOf` names a `list` or `table` block id of the screen that was on display when this spec was sent;
  `detailItem` names the picked item or row id in it (≤ 32, id rule).
- uikit's own panel window ignores both: it shows the spec alone, as in 0.1.
- A host that has room for two panes (in 0.2: `aeterna_phonekit` on its wide `book` model) keeps the earlier screen
  on the left with `detailItem` highlighted and draws this spec on the right. Without room, the host shows this spec
  in place of the earlier one, as in 0.1.
- Validation here checks only the shape (both ids follow the id rule; `detailItem` without `detailOf` fails). The
  host checks that `detailOf` names a block of the earlier screen and falls back to a single pane when it does not.
- phonekit keeps its own copy of the spec validator, so its 0.2 copy accepts every new block type and field in this
  part (see `aeterna_phonekit.md`, 0.2).

### Motion

- Panels and prompts enter with opacity 0 → 1 and an 8 px rise over `--enter`, and leave with opacity 1 → 0 over
  `--fast`, using `--ease`. A panel replaced by another (`replaced`) swaps without an exit animation.
- The exit animation never delays the answer: `aeterna_uikit:action` with `__close` fires when the player closes,
  not when the animation ends. Focus goes back to `aeterna_core` at the same moment.
- Reduced motion: `theme.css` already sets `--fast` and `--enter` to `0ms` under `prefers-reduced-motion: reduce`.
  0.2 also drops the 8 px rise there, so nothing moves; elements appear and disappear. Whether CEF passes the
  Windows setting through to `prefers-reduced-motion` is **not verified yet**; self-test `motion_reduced` checks it.
- Tab switches, the slider thumb and table row focus use `--fast` and follow the same rule.

### Paused by a focus overlay

**Changed in 0.2.** When another resource takes focus through `aeterna_core`'s focus overlay (core 0.2,
[aeterna_core.md](aeterna_core.md) § Focus), the holder is paused, not cancelled. An open panel or prompt then stays on
screen, ignores every input (no button, field, ESC or cancel key acts) and sends nothing; when the overlay releases,
focus comes back and the panel or prompt works again from where it was. A progress bar keeps running while paused; a
skill check's marker stops and resumes. A real focus loss (`aeterna_core:focusLost`, another resource taking focus
without the overlay option) still closes the panel with `__close` and cancels prompts, as in 0.1. Reason: the test kit's
eye card is an overlay and must be able to ask about a panel without closing it. Upgrade note: none for callers;
`__close` still fires for every close.

### Type tokens

0.1 sets pixel sizes in `style.css`. 0.2 uses the theme type tokens from ADR 0005 decision 9 (`--fs-1` smallest …
`--fs-5` largest, line height `--lh`), so a theme preset or override changes every size at once:

| Text | Token |
| --- | --- |
| Table header, list `meta`, slider unit, key hints | `--fs-1` |
| List item `meta`, empty-state body, field help | `--fs-2` |
| Body text, list labels, table cells, buttons, tab labels | `--fs-3` |
| Panel title, empty-state label | `--fs-4` |
| Not used by uikit | `--fs-5` |

The pixel value of each token lives in `theme.css` only.

### NUI messages (0.2)

Lua → NUI: unchanged names; `panel:open` and `panel:update` carry the new block types.
NUI → Lua: `panelAction` may carry `action = <tab item id>` (with `report = true`), `<row id>` (selectable table)
or `<empty action id>`; the same validation applies.

### Locale keys (0.2)

`uikit.search.placeholder`, `uikit.search.none`, `uikit.table.empty`, `uikit.tabs.label`.

### `oss.json` (0.2)

No change: no new net event, command, convar or file.

### Tests (0.2, busted)

1. `tabs`: two `tabs` blocks fail; one tab or seven tabs fail; `tab` naming an unknown tab fails; `value` defaults
   to the first tab; the active tab comes back in `values`; with `report = true` a tab id is an allowed action.
2. `slider`: `min ≥ max`, `step ≤ 0`, more than 1000 steps, and `value` out of range fail; a returned value off the
   step grid or out of range is dropped; a good one passes as a number.
3. `table`: seven columns, 51 rows, a cell key that is not a column, a duplicate row id each fail; a row id is an
   allowed action only when `selectable = true`.
4. `list.search`: 200 items pass with search on, 51 fail with it off.
5. `empty`: block without `label` fails; its `action.id` is an allowed action.
6. `detailOf`: bad id fails; `detailItem` without `detailOf` fails; both pass through to the cleaned spec.
7. `update`: `rows`, tab `value` and slider `value` patch; a slider `value` out of range is refused.
8. A 0.1 spec (every 0.1 block type) validates to the same cleaned spec as in 0.1.
9. Pause: while paused, a `panelAction` or `promptResult` from the page is dropped; after resume it passes; a real
   focus loss still fires `__close`.

### Self-tests (0.2)

Registered with `aeterna_core`'s self-test registry as `aeterna_uikit.<name>`. "Skip when" is the only reason the
test may report SKIP; a ped or eye test with no person to run it reports GAP, not SKIP (ADR 0005 decision 7).
"Players" counts players needed in the game; a headless test needs none and is listed as 1.

| Name | Kind | Players | Destructive | Expect (what a person should see) | Skip when |
| --- | --- | --- | --- | --- | --- |
| `spec_limits` | headless | 1 | n | — | never |
| `values_recheck` | headless | 1 | n | — | never |
| `forged_action` | headless | 1 | n | — | never |
| `panel_every_block` | eye | 1 | n | An `md` panel with tabs, a searchable list, a slider, a table and an empty state, in the active theme preset; text sizes follow the theme | — |
| `tabs_switch` | ped | 1 | n | Switching tabs changes the blocks below without a flicker; the server receives the tab id when `report = true` | — |
| `slider_keyboard` | ped | 1 | n | Arrow keys move the slider one step; the value shown next to it matches what the server receives | — |
| `motion_reduced` | eye | 1 | n | With reduced motion on in Windows, the panel appears and disappears with no fade or rise | — |
| `focus_lost_closes` | ped | 1 | n | A second resource takes focus without the overlay option; the panel closes and the owner receives `__close` | — |
| `overlay_pauses` | eye | 1 | n | While this eye card (an overlay) is up, the test panel behind it stays open and ignores clicks; after answering, the panel works again | — |

### Done when (0.2)

The 0.1 conditions, plus: the busted cases above pass, every self-test above is registered and passes on the
kit-test server (SKIP only for its listed reason), and the owner has passed screenshots of `panel_every_block` in all
three theme presets.
