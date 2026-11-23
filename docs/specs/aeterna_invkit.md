# aeterna_invkit

- Package: `packages/invkit` · resource `aeterna_invkit` · wave W2 · status released in 0.1.0 · spec 0.2.0
  ([0.2 additions](#02-additions) at the end, [ADR 0005](../adr/0005-starter-kit-0-2.md))
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
- Near a point the player sees a key hint (`aeterna_uikit` `keyHints`) for `+aeterna_invkit_open` (default key `F2`).
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

`+aeterna_invkit_open` / `-aeterna_invkit_open` (default key `F2`), registered with literal names. `aeterna_stash` when
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

---

## 0.2 additions

- Version: 0.2.0 ([ADR 0005](../adr/0005-starter-kit-0-2.md) decision 1) · edges: `aeterna_core`, `aeterna_uikit`
  (+ `ox_inventory`), and **new:** `aeterna_phonekit` optional, local events only (ADR 0005 decision 2)
- Written by: Claude Code - Claude Opus 5.5 (helper)

Everything above stays valid. 0.2 adds one feature: **phone item mode**. When a server owner sets
`Config.devices = 'items'` in `aeterna_phonekit`, the phones a player carries are items in their ox_inventory, and
each phone's battery and fold state live in that item's metadata. invkit answers phonekit's open gate with every phone
the player carries; phonekit chooses the active one. Self-tests for the 0.1 features are added too.

invkit never lists phonekit in `dependencies`, never calls `exports.aeterna_phonekit`, never loads its files and
works the same when phonekit is absent. Both directions are server-local events. phonekit never needs invkit: any
other resource may answer the same events. The events and payloads below are phonekit's
([aeterna_phonekit § Device modes](aeterna_phonekit.md#device-modes)); this part only says what invkit does with them.

### Configuration (0.2)

| Key | Default | Meaning |
| --- | --- | --- |
| `Config.phone.enabled` | `false` | Answer phonekit's open gate from phone items. Turn it on together with phonekit's `Config.devices = 'items'` |
| `Config.phone.items` | see below | ox item name → phone model |

```lua
Config.phone.items = {
  phone        = 'slab',     -- the common generic phone item name
  phone_keypad = 'keypad', phone_burner = 'burner', phone_qwerty = 'qwerty', phone_slab = 'slab',
  phone_fold   = 'fold',   phone_pro    = 'pro',    phone_book   = 'book',   phone_pad  = 'pad',
}
```

- Models are exactly phonekit's eight model ids: `keypad`, `burner`, `qwerty`, `slab`, `fold`, `pro`, `book`, `pad`
  (ADR 0005 decision 5). An entry with another model, or an item name that is not `^[%w_%-]+$` ≤ 64, is skipped with
  one `warn` at start. Several items may map to the same model; at most 32 entries.
- What players see as the model's name is phonekit's (`Keypad`, … or the optional in-universe preset); invkit only
  passes the model id.
- Whether the battery is used at all is phonekit's `Config.battery`; invkit has no battery switch of its own and no
  start value (a phone with no `battery` metadata is sent without `battery`, and phonekit uses its `startPct`).

### Item icons and item definitions (install instructions, not files)

invkit ships no image and writes nothing into ox_inventory (no `SaveResourceFile`, no file copied from it). The
README and the guide `docs/guides/ox-inventory-theme.md` gain a section for the server owner:

1. Add one entry per phone item to ox_inventory's own item list (`data/items.lua`), for example
   `['phone_fold'] = { label = 'Fold', weight = 190, stack = false, close = true }`. `stack = false` is required:
   each phone keeps its own battery in its metadata.
2. Put an image named `<item>.png` in ox_inventory's `web/images/` folder; the owner provides the images.
3. Set `Config.phone.enabled = true` here and `Config.devices = 'items'` in phonekit, then restart both.

The exact item fields and image folder follow the ox_inventory version on the test server; W1 confirms them before
the guide is written (same "check before coding" rule as the 0.1 table).

### Open gate (server-local events)

All six events are server-local, as phonekit lists them. invkit takes part only when `Config.phone.enabled = true`.

| Event | Fired by | Payload (phonekit's) | What invkit does |
| --- | --- | --- | --- |
| `aeterna_phonekit:hello` | phonekit | — | Fires `listen` again |
| `aeterna_phonekit:listen` | invkit | — | Fired on invkit start and on every `hello` |
| `aeterna_phonekit:asking` | phonekit | `(src, { checkId, devices })` | Answers only when `devices == 'items'`; stays silent for `single` |
| `aeterna_phonekit:answer` | invkit | `(checkId, { allow = true, devices = { … } })` | Every phone the player carries (below) |
| `aeterna_phonekit:devicesChanged` | invkit | `(src)` | Fired when a phone item left, entered or moved in that player's inventory |
| `aeterna_phonekit:deviceSave` | phonekit | `(src, { id, battery, fold })` | Writes `battery` and `fold` into the metadata of the item with that `id` |

Answering one `asking` (well within phonekit's 1000 ms window; invkit makes no wait or yield of its own):

1. Find every slot of the player that holds an item listed in `Config.phone.items`.
2. A phone item with no `metadata.phoneId` gets one now (decision 1 below), written with `SetMetadata` before the
   answer is sent.
3. Answer `(checkId, { allow = true, devices = list })`, one entry per phone item, at most 8 (phonekit's limit; the
   lowest slot numbers win when there are more):
   `{ id = <metadata phoneId>, model = <mapped model>, battery = <metadata battery>?, fold = <metadata fold>?,
   color = <metadata color>? }`.
   `battery` is sent only when the item's metadata holds a number 0–100, `fold` only when it holds `'open'` or
   `'closed'`, `color` only when it holds a non-negative integer; anything else is left out, so phonekit applies its
   own defaults (and fires `deviceSave` with them).
4. No phone carried, or ox_inventory not started, → the same answer with an empty `devices` list, which phonekit
   counts as a denial with its own `phonekit.refused.nodevice`. invkit sends no reason key of its own.

invkit never picks the active phone; phonekit does (its rule: last choice, then rank, then smallest `id`).

`deviceSave` write-back:

- invkit looks up the slot of that player whose item is in `Config.phone.items` and whose `metadata.phoneId`
  equals `id`, and writes `battery` (clamped to an integer 0–100) and `fold` (`'open'` or `'closed'`, anything else
  ignored) into the item's metadata, keeping every other metadata field.
- At most 1 write per player per 5000 ms. Saves that arrive sooner are held, and the latest one per `id` is written
  when the window opens.
- If no such item is in that player's inventory any more (dropped, given, removed), invkit writes nothing and fires
  `devicesChanged` for that player.
- In item mode the battery and fold state live only in the item (ADR 0005 decision 3). invkit never writes client KVP
  or resource KVP for them.

`devicesChanged`: invkit fires it when ox_inventory reports a move, drop, give or new item that involves a mapped
phone item for that player (hooks in the table below). A phone removed by another resource without a hook is caught
at the next `deviceSave` for it (previous paragraph).

Trust: these are server-local events, so a client cannot fire them. `checkId` comes from phonekit and is passed back
unchanged; phonekit ignores answers for unknown or expired checks and ids not in the last answer (its spec).

### ox_inventory calls (0.2) — check before coding

**Not yet verified** against the ox_inventory version on the test server; the first W1 task confirms each call and
corrects this table, as in 0.1.

| Purpose | Expected call |
| --- | --- |
| Find phone slots | server `exports.ox_inventory:Search(src, 'slots', names)` (returns slots with `slot`, `name`, `metadata`) |
| Read one slot | server `exports.ox_inventory:GetSlot(src, slot)` |
| Write `phoneId`, battery and fold | server `exports.ox_inventory:SetMetadata(src, slot, metadata)` |
| Hear moves, drops and gives | server `exports.ox_inventory:registerHook('swapItems', fn, { itemFilter = {…} })` |
| Hear new phone items | server `exports.ox_inventory:registerHook('createItem', fn, { itemFilter = {…} })` |

### Locale keys (0.2)

None. The "no phone" refusal is phonekit's `phonekit.refused.nodevice`.

### `oss.json` (0.2)

No change: no new net event, command, convar or file write. Server-local events need no declaration.

### Tests (0.2, busted)

1. Item map: the shipped map passes; an unknown model, a bad item name, a 65-char name and a 33rd entry are skipped
   with one `warn`.
2. Answer: two phones → two entries with their `phoneId` serials and their models; a phone without `phoneId` gets one
   written once and keeps it on the next answer; two new phones never get the same serial; nine phones → the eight
   lowest slots; no phone → `allow = true` with an empty list; ox not started → the same empty list.
3. Metadata pass-through: `battery` 87, `fold = 'closed'` and `color = 2` are sent; `battery = 'x'`, 120 or missing,
   `fold = 'half'` and `color = -1` are left out.
4. Gate: `devices = 'single'` → no answer; `Config.phone.enabled = false` → no `listen` and no answer; `listen` is
   fired again on `hello`.
5. `deviceSave`: battery 101 and −5 clamp; a bad `fold` is ignored and `battery` still written; a save for a `phoneId`
   no longer carried fires `devicesChanged` and writes nothing; a phone moved to another slot is still found; three
   saves within 5000 ms write the latest once; other metadata fields are kept.
6. `devicesChanged`: a hook report for a mapped item fires it once for that player; for an unmapped item it does not.

### Self-tests (0.2)

Registered as `aeterna_invkit.<name>`. "Skip when" is the only reason the test may report SKIP; a ped or eye test
with no person to run it reports GAP (ADR 0005 decision 7). A headless test needs no player and is listed as 1.

Kind `mock (client)` = `side = 'client'`: the test runs on the presser's client and is GAP when there is no presser
(W0 fix D3). Plain `headless` / `mock` run on the server.

| Name | Kind | Players | Destructive | Expect (what a person should see) | Skip when |
| --- | --- | --- | --- | --- | --- |
| `stash_id` | headless | 1 | n | — | never |
| `use_state_machine` | headless | 1 | n | — | never |
| `phone_item_map` | headless | 1 | n | — | `Config.phone.enabled = false` |
| `stash_open` | ped | 1 | n | The test moves you to a stash point and away from it, then back where you stood (the presser is moved to the first configured stash point, then 25 m + radius away, the bound key's open request is sent at each stop, then the presser is put back; timeout 30000 ms) | ox_inventory not started, or no stash point configured (`no stash point configured`) |
| `item_use` | mock (client) | 1 | y | — (a test `registerUsable` on a test item gives the presser one, runs the progress bar, checks one is removed and `used` fires once, then removes the registration) | ox_inventory not started |
| `phone_two_items` | ped | 1 | y | The test gives you a `phone_fold` and a `phone_slab` item for a moment (tagged test phones, battery 100, own `phoneId`, tag `aeterna_selftest` = run id: one fold-mapped and one slab-mapped item) | ox_inventory or `aeterna_phonekit` not started, or `Config.phone.enabled = false` |
| `phone_drop_active` | ped | 1 | y | The test gives you two phone items, then takes one back (two tagged slab test phones; the second is taken back after 4000 ms) | ox_inventory or `aeterna_phonekit` not started, or `Config.phone.enabled = false` |
| `phone_no_item` | ped | 1 | y | The test puts your phone items aside for a moment, then gives them back (the presser's own phone items are set aside and given back with the same metadata on `selftestEnd`) | ox_inventory or `aeterna_phonekit` not started, or `Config.phone.enabled = false` |
| `phone_device_save` | mock | 1 | y | — (gives the presser a test phone item with battery 100, so phonekit does not write its start battery after the test's save, fires `deviceSave` with battery 42 and fold `closed`, checks the item's metadata, then removes the item) | ox_inventory not started, or `Config.phone.enabled = false` |

The three phone rows check invkit's half only: the presser's own inventory as invkit reads it (which phones it would
offer, and that the taken-back or set-aside item is gone). phonekit's control centre, Fold screen and "no phone" toast stay
phonekit's own self-tests. The tester has nothing to carry or drop: the test does the act itself, and every item it gave
is removed on `selftestEnd` (watch time 15000 ms, row timeout 25000 ms for the phone rows).
`item_use` intercepts a use only for the presser's item tagged with the run id (`aeterna_selftest`); every other use,
by anyone, goes to ox_inventory untouched.

`item_use`, `phone_device_save` and the three phone rows (`phone_two_items`, `phone_drop_active`, `phone_no_item`) are destructive (ADR 0005 decision 7, W0 fix D4): they give a real player items
and write item metadata. They SKIP while core's destructive gate is closed, and they add and remove only the items
they create, so the presser's own inventory ends as it began when they pass.

### Decisions on the device id, colour and battery switch (0.2)

Settled by the Orchestrator on 2026-11-21:

1. **Device id is a serial in the item metadata.** The first time invkit lists a phone item that has no
   `metadata.phoneId`, it writes one (8 lowercase hex characters, random, unique among the player's items) and uses
   it as the device `id`. The id survives moving the phone to another slot or handing it to another player.
   `<item>:<slot>` is no longer used; tests that name it use the serial instead.
2. **Case colour comes from `metadata.color`** (an index into the model's colours), set by whatever gave the item (a
   shop, an admin command). invkit passes it through when present and sends nothing otherwise; phonekit then uses the
   model's first colour.
3. **Battery switch.** With `Config.battery = false`, phonekit still fires `deviceSave` for `fold` and leaves
   `battery` out; invkit writes only the fields that arrive.

### Done when (0.2)

The 0.1 conditions, plus: the 0.2 ox_inventory table and the item install steps are verified and corrected, the
event names and payloads above still match the phonekit 0.2 spec, the busted cases above pass, and every self-test
above is registered and passes on the kit-test server (SKIP only for its listed reason).

**Smoke (added after W1 review):** drain a carried phone's battery, disconnect, reconnect: the item keeps the last shown value (checks the drop flush against FXServer's real handler order, which busted only models).
