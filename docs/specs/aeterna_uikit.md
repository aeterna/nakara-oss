# aeterna_uikit

- Package: `packages/uikit` · resource `aeterna_uikit` · wave W1 · status released in 0.1.0
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
