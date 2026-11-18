# aeterna_invkit

- Package: `packages/invkit` · resource `aeterna_invkit` · wave W2 · status released in 0.1.0
- Depends on: `aeterna_core`, `aeterna_uikit` · calls `ox_inventory` only when it is started, never listed as a
  dependency ([ADR 0004](../adr/0004-aeterna-starter-kit.md) decision 15)

## Purpose and limits

Two things most servers add around ox_inventory: a **personal stash** players open at set places, and an **item-use
registry** that shows a progress bar, plays an animation, and only then takes the item and applies its effect. Plus a
**theming guide** for ox_inventory itself.

Not here: a hotbar (ox_inventory has one), an inventory UI, shops, crafting, any file copied or adapted from
ox_inventory (GPL-3.0). Without ox_inventory started, the package logs one `warn` and does nothing.

## ox_inventory calls — check before coding

These are the calls this spec expects. **Not yet verified** against the ox_inventory version on the test server; W2's
first engineer task is to confirm each one in ox_inventory's documentation and correct this table if needed.

| Purpose | Expected call |
| --- | --- |
| Create a stash | server `exports.ox_inventory:RegisterStash(id, label, slots, maxWeight, owner)` |
| Open it for a player | server `exports.ox_inventory:forceOpenInventory(src, 'stash', id)` |
| Hear that an item is used | server `exports.ox_inventory:registerHook('usingItem', fn, { itemFilter = {…} })` |
| Check and remove | server `exports.ox_inventory:GetItemCount(src, name)`, `RemoveItem(src, name, count, metadata, slot)` |

## Install

```cfg
ensure ox_inventory
ensure aeterna_core
ensure aeterna_uikit
ensure aeterna_invkit
```

## Configuration (`config.lua`)

| Key | Default | Meaning |
| --- | --- | --- |
| `Config.stash.scope` | `'character'` | `character` (one stash per character) or `account` (shared by every character of the same license) |
| `Config.stash.slots` | `40` | |
| `Config.stash.maxWeight` | `100000` | grams |
| `Config.stash.label` | locale `invkit.stash.label` | |
| `Config.stash.points` | `{}` | `{ { coords = vec3(…), radius = 2.0 } }` where the stash can be opened |
| `Config.stash.command` | `false` | `true` enables the fixed command `aeterna_stash` (still needs a point within `radius`, unless `anywhere = true`) |
| `Config.stash.anywhere` | `false` | Open from anywhere; for testing |

## Personal stash

- Stash id: `aeterna_stash:c:<citizenid>` or `aeterna_stash:a:<license>` (qbx citizenid when `qbx_core` is started,
  otherwise the `license:` identifier for both scopes). Registered on first open, not at start.
- Near a point the player sees a key hint (`aeterna_uikit` `keyHints`) for `+aeterna_invkit_open` (no default key).
  Pressing it sends `aeterna_invkit:sv:open`.
- The server checks: rate limit, that the player is within `radius` of a configured point (server-side ped
  coordinates, which needs OneSync), then registers and opens the stash.

| Export (server) | Notes |
| --- | --- |
| `openStash(src, opts?)` | Opens the player's own stash without the distance check; for other resources (a house, a garage). `opts.scope` overrides the config. |
| `stashId(src, scope?)` | Returns the id, so other resources can add items to it through ox_inventory. |

## Item use

| Export (server) | Notes |
| --- | --- |
| `registerUsable(item, def)` | `item` = ox item name. `def = { label, duration = 2000, anim = { dict, clip, flag = 49 }?, prop = { model, bone, pos, rot }?, consume = 1, cancelable = true, ask = false }`. Plain data only, no functions. The owning resource is recorded; the entry is removed when it stops. |
| `unregisterUsable(item)` | |
| `allowUse(useId)` / `denyUse(useId, reasonKey)` | The owner's answer when `ask = true` (below). |

The owner hears about uses through server-local events, filtered on `owner == GetCurrentResourceName()`:

- `aeterna_invkit:asking` → `(src, { owner, item, slot, useId })`, only when `ask = true`. The owner must call
  `allowUse` or `denyUse` within 1000 ms; silence counts as denied.
- `aeterna_invkit:used` → `(src, { owner, item, slot, count })`, after the item has been removed. This is where the
  owner applies the effect.

Flow for one use:

1. ox_inventory reports the use; invkit cancels ox's own consumption for that item and looks up the entry.
2. If `ask = true`, the owner answers through `allowUse` / `denyUse`. A denial sends `aeterna_invkit:cl:refused`
   `{ item, reason }` to the player, where `reason` is the owner's locale key; invkit does not show it itself.
3. The client runs `aeterna_uikit` `progress` with `label`, `duration`, the animation and prop. Cancel → nothing is
   taken.
4. On finish the client sends `aeterna_invkit:sv:done`; the server checks the use is still pending for that player and
   item, that the time since start ≥ `duration − 250 ms`, and that the player still has `consume` of the item in that
   slot. Then it removes the item and fires `aeterna_invkit:used`.
5. One use per player at a time. A second use while one is pending is refused.

## Theming ox_inventory

`docs/guides/ox-inventory-theme.md` (written in W4): which CSS selectors ox_inventory's web build exposes, how to map
Asphalt tokens onto them in the server owner's own override, and why the kit ships no ox file. Prose and selectors only.

## Events

| Event | Direction | Schema | Rate limit |
| --- | --- | --- | --- |
| `aeterna_invkit:sv:open` | client → server | none | 2 / 1000 ms |
| `aeterna_invkit:sv:done` | client → server | `{ useId: string ≤ 24 }` | 4 / 1000 ms |
| `aeterna_invkit:sv:cancel` | client → server | `{ useId: string ≤ 24 }` | 4 / 1000 ms |
| `aeterna_invkit:cl:use` | server → client | `{ useId, label, duration, anim?, prop?, cancelable }` | — |
| `aeterna_invkit:cl:refused` | server → client | `{ item: string ≤ 64, reason: string ≤ 64 }` | — |
| `aeterna_invkit:asking` | server-local | `{ owner, item, slot, useId }` | — |
| `aeterna_invkit:used` | server-local | `{ owner, item, slot, count }` | — |

## Commands and keys

`+aeterna_invkit_open` / `-aeterna_invkit_open` (no default), registered with literal names. `aeterna_stash` when
`Config.stash.command = true`.

## Storage

None of its own. Items live in ox_inventory's tables.

## Locale keys

`invkit.stash.label`, `invkit.stash.hint`, `invkit.stash.far`, `invkit.use.busy`, `invkit.use.cancelled`,
`invkit.key.open`, `invkit.noox`.

## `oss.json` capabilities

```json
{ "http": [], "commands": [], "registeredCommands": ["+aeterna_invkit_open", "-aeterna_invkit_open", "aeterna_stash"],
  "convars": { "read": [], "write": [] },
  "netEvents": { "server": ["aeterna_invkit:sv:open", "aeterna_invkit:sv:done", "aeterna_invkit:sv:cancel"],
                 "client": ["aeterna_invkit:cl:use", "aeterna_invkit:cl:refused"] },
  "nui": false, "db": { "tables": [], "ddl": false }, "files": { "write": [] } }
```

`aeterna_stash` is always registered in code (literal name) and returns at once when `Config.stash.command` is false,
so the declaration stays exact.

## Tests

busted:

1. Stash id for both scopes, with and without qbx.
2. Distance check: inside radius passes, outside fails, no points configured fails unless `anywhere`.
3. Use state machine: start → done too early refused; done after duration passes once; second start while pending
   refused; cancel clears; owner stop clears its entries.
4. `registerUsable` rejects a `def` holding a function, a duration outside 300–60000, or a non-positive `consume`.
5. `ask = true`: no answer within 1000 ms = denied and `cl:refused` sent; `allowUse` with a stale `useId` is ignored.

Smoke (needs ox_inventory on the test server):

1. Walk to a point, press the bound key, the stash opens; walk away and press again: refused with `invkit.stash.far`.
2. `account` scope: two characters on one license see the same items; `character` scope: they do not.
3. A test resource registers `water`: progress bar runs, cancel keeps the item, finishing removes one and fires
   `aeterna_invkit:used` once.
4. Spam `aeterna_invkit:sv:done` from the client console: no extra items removed.

## Done when

The ox_inventory table above is verified and corrected, all busted cases pass, `fivem-devkit safety` reports 0 errors
and 0 over-declared items, and the smoke steps pass.
