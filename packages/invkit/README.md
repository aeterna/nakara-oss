# aeterna_invkit

Personal stashes and a server-validated item-use progress registry around `ox_inventory` for the AETERNA Starter Kit ([ADR 0004](../../docs/adr/0004-aeterna-starter-kit.md) · [spec](../../docs/specs/aeterna_invkit.md)).

ระบบตู้เก็บของส่วนตัว (Personal Stash) และระบบลงทะเบียนการใช้งานไอเทมพร้อมหลอดความคืบหน้าและแอนิเมชันสำหรับใช้งานร่วมกับ `ox_inventory` ในชุด AETERNA Starter Kit

---

## What it does / การทำงาน

- **Personal stash (ตู้เก็บของส่วนตัว):** Players open their personal stash (`aeterna_stash:c:<citizenid>` for `character` scope, or `aeterna_stash:a:<license>` for `account` scope) at configured points using `+aeterna_invkit_open` (with `aeterna_uikit` key hints) or via server export `openStash`. Stashes are registered on first open, not at server start.
- **Item-use registry (ระบบใช้งานไอเทม):** Other resources register usable items with plain data (`label`, `duration`, `anim`, `prop`, `consume`, `cancelable`, `ask`). When an item is used in `ox_inventory`, `aeterna_invkit` cancels `ox_inventory`'s immediate consumption, optionally asks the owning resource (`aeterna_invkit:asking` with a 1000 ms timeout), runs `aeterna_uikit:progress` on the client, verifies elapsed time and item count on the server, removes the item, and emits `aeterna_invkit:used`.
- **Clean GPL-3.0 boundary (แยกขอบเขตชัดเจน):** Calls `ox_inventory` exports only when `GetResourceState('ox_inventory') == 'started'`, never lists it as a dependency, and ships no files copied or adapted from `ox_inventory`. Without `ox_inventory` started, `aeterna_invkit` logs one `warn` and remains inactive.
- **Deliberate limits (ขอบเขตที่จำกัดไว้):** No hotbar (`ox_inventory` provides one), no inventory UI, no shops, and no crafting.

## Install / การติดตั้ง

1. Download `aeterna_invkit-<version>.zip` from the [Releases](https://github.com/aeterna/nakara-oss/releases) page and verify it (see below).
2. Extract it into your `resources/` folder so you have `resources/aeterna_invkit/fxmanifest.lua`.
3. Ensure `ox_inventory`, `aeterna_core`, and `aeterna_uikit` start before `aeterna_invkit` in `server.cfg`:

   ```cfg
   ensure ox_inventory
   ensure aeterna_core
   ensure aeterna_uikit
   ensure aeterna_invkit
   ```

4. Phone item mode (0.2, optional): set `Config.phone.enabled = true` here **and** `Config.devices = 'items'` in `aeterna_phonekit`. Each setting does nothing without the other: phonekit asks for phone items only in `items` mode, and invkit answers only when `Config.phone.enabled` is on. See [Phone items](#phone-items--โทรศัพท์แบบไอเทม-02) for the ox_inventory item entries.

## Config / การตั้งค่า (`config.lua`)

| Key | Default | Meaning / ความหมาย |
|---|---|---|
| `Config.stash.scope` | `'character'` | `'character'` (one stash per character; uses `qbx_core` `citizenid` when started, else `license:`) or `'account'` (shared across characters of the same `license:`) / ขอบเขตตู้เก็บของ (`character` แยกตามตัวละคร หรือ `account` ใช้ร่วมกันทั้งบัญชี) |
| `Config.stash.slots` | `40` | Number of stash slots / จำนวนช่องเก็บของ |
| `Config.stash.maxWeight` | `100000` | Maximum stash weight in grams / น้ำหนักสูงสุด (กรัม) |
| `Config.stash.label` | `'invkit.stash.label'` | Stash title or locale key / ชื่อตู้เก็บของหรือคีย์ภาษา |
| `Config.stash.points` | `{}` | Array of `{ coords = vec3(...), radius = 2.0 }` where players can open their stash / พิกัดจุดที่เปิดตู้เก็บของได้ |
| `Config.stash.command` | `false` | `true` enables the command `aeterna_stash` (still requires a point within `radius` unless `anywhere = true`) / เปิดใช้คำสั่ง `aeterna_stash` |
| `Config.stash.anywhere` | `false` | Allow opening the stash from anywhere (for testing) / เปิดตู้เก็บของได้จากทุกที่ (สำหรับการทดสอบ) |
| `Config.phone.enabled` | `false` | Answer `aeterna_phonekit`'s open gate from phone items. Turn on together with phonekit's `Config.devices = 'items'` / ใช้โทรศัพท์จากไอเทมใน `ox_inventory` (เปิดคู่กับ `Config.devices = 'items'` ของ phonekit) |
| `Config.phone.items` | 9 entries (below) | ox item name → phonekit model id (`keypad`, `burner`, `qwerty`, `slab`, `fold`, `pro`, `book`, `pad`). At most 32; an entry with another model or a name that is not `^[%w_%-]+$` ≤ 64 is skipped with one `warn` at start / ชื่อไอเทม → รุ่นโทรศัพท์ |

```lua
Config.phone.items = {
    phone = 'slab', -- the common generic phone item name
    phone_keypad = 'keypad', phone_burner = 'burner', phone_qwerty = 'qwerty', phone_slab = 'slab',
    phone_fold = 'fold', phone_pro = 'pro', phone_book = 'book', phone_pad = 'pad',
}
```

## Exports & Events / การเรียกใช้งาน

### Server exports

| Export | Returns | Description |
|---|---|---|
| `exports.aeterna_invkit:openStash(src, opts?)` | `boolean` | Opens the player's personal stash without a distance check (e.g., from a house or garage resource). `opts.scope` overrides `Config.stash.scope`. |
| `exports.aeterna_invkit:stashId(src, scope?)` | `string \| nil, err` | Returns the player's stash ID (`aeterna_stash:c:<citizenid>` or `aeterna_stash:a:<license>`). |
| `exports.aeterna_invkit:registerUsable(item, def)` | `boolean, err?` | Registers a usable item (`def = { label, duration = 2000, anim?, prop?, consume = 1, cancelable = true, ask = false }`, plain data only). Automatically removed when the owning resource stops. |
| `exports.aeterna_invkit:unregisterUsable(item)` | `boolean` | Removes a registered usable item. |
| `exports.aeterna_invkit:allowUse(useId)` | `boolean` | Approves a pending item use when `ask = true` (must be called within 1000 ms). |
| `exports.aeterna_invkit:denyUse(useId, reasonKey)` | `boolean` | Denies a pending item use when `ask = true` and sends `aeterna_invkit:cl:refused` `{ item, reason }` to the player. |

### Server-local events

Filter on `data.owner == GetCurrentResourceName()`:

- `aeterna_invkit:asking` → `(src, { owner, item, slot, useId })` — fired when `ask = true`. Call `allowUse(useId)` or `denyUse(useId, reasonKey)` within 1000 ms; silence counts as denied.
- `aeterna_invkit:used` → `(src, { owner, item, slot, count })` — fired after the progress bar finishes and the item has been removed from the player's inventory.

## Phone items / โทรศัพท์แบบไอเทม (0.2)

With `Config.phone.enabled = true` and `aeterna_phonekit` set to `Config.devices = 'items'`, the phones a player carries are items in their `ox_inventory`. `aeterna_invkit` answers phonekit's open gate with every phone item carried (at most 8, lowest slots first) and phonekit chooses the active one. phonekit is optional: the two talk only through server-local events, and `aeterna_invkit` works the same without it.

- Each phone item gets a serial in `metadata.phoneId` (8 lowercase hex characters) the first time it is listed. The serial is the phone's id, so it survives moving the item to another slot or giving it to another player.
- `metadata.battery` (0–100), `metadata.fold` (`'open'` or `'closed'`) and `metadata.color` (case colour index, set by whatever gives the item: a shop, an admin command) are sent to phonekit when valid; otherwise phonekit uses its own defaults.
- phonekit saves battery and fold back into the item metadata (at most one write per player per 5 seconds). A phone handed to another player keeps its charge.
- Moving, dropping, giving or receiving a phone item makes phonekit check again, so a dropped active phone is put away at once.

### Install the items in ox_inventory / เพิ่มไอเทมใน ox_inventory

`aeterna_invkit` ships no image and writes nothing into `ox_inventory`. The server owner adds the items (checked against `ox_inventory` 2.44.0):

1. Add one entry per phone item to `ox_inventory/data/items.lua`. `stack = false` is required: each phone keeps its own battery in its metadata.

   ```lua
   ['phone_fold'] = { label = 'Fold', weight = 190, stack = false, close = true },
   ['phone_keypad'] = { label = 'Keypad', weight = 120, stack = false, close = true },
   ```

   `ox_inventory` already ships a `phone` item (`stack = false`, with its own `phone.png`); keep it, it maps to the `slab` model. Its `client.add` / `client.remove` functions only call another phone resource through `pcall` and do nothing without it.
2. Put an image named `<item>.png` (for example `phone_fold.png`) in `ox_inventory/web/images/`, or in the folder your `inventory:imagepath` convar points to. You provide the images.
3. Set `Config.phone.enabled = true` here and `Config.devices = 'items'` in `aeterna_phonekit`, then restart both.

### Server-local events (phonekit's contract)

| Event | Fired by | What `aeterna_invkit` does |
|---|---|---|
| `aeterna_phonekit:hello` | phonekit | Fires `aeterna_phonekit:listen` again |
| `aeterna_phonekit:listen` | invkit | Fired on start and on every `hello` |
| `aeterna_phonekit:asking` `(src, { checkId, devices })` | phonekit | Answers only when `devices == 'items'` |
| `aeterna_phonekit:answer` `(checkId, { allow = true, devices })` | invkit | `devices` = `{ id, model, battery?, fold?, color? }` per phone; an empty list when none is carried or `ox_inventory` is not started |
| `aeterna_phonekit:devicesChanged` `(src)` | invkit | A phone item left, entered or moved in that player's inventory |
| `aeterna_phonekit:deviceSave` `(src, { id, battery?, fold? })` | phonekit | Writes the fields that arrive into the item with that `phoneId` |

## Self-tests / การทดสอบตัวเอง (0.2)

invkit registers these tests with `aeterna_core` on start (`aeterna_testkit` lists and runs them). A test reports
SKIP only for the reason in the last column; a ped or client test with nobody to run it is GAP. Client tests that need
server state are prepared by invkit's server on core's `aeterna_core:selftestStarted` and torn down on its server-side
`aeterna_core:selftestEnd`; the result always comes from the presser's client. Every test write goes through core's
write guard (`AeternaCore.selftest.mayWrite`) first.

`stash_open` and the three phone rows carry a short instruction as `expect` ("The test gives you two phone items, then takes one back"); `aeterna_testkit` shows it while the row runs.

Self-test events are accepted only from `aeterna_core` (the invoking resource), so no other resource can start a test or its server preparation. When `aeterna_core` stops mid-test, the server removes its tagged test item and the test usable.

| Test | Kind | Runs | What it checks | SKIP when |
|---|---|---|---|---|
| `aeterna_invkit.stash_id` | headless | server | Stash ids for both scopes, with and without qbx; no identifier or an unknown scope gives none | never |
| `aeterna_invkit.use_state_machine` | headless | server | A private use manager on a fake clock: done too early refused, busy while pending, done once, cancel, owner stop. No item is touched | never |
| `aeterna_invkit.phone_item_map` | headless | server | `Config.phone.items` validates with nothing skipped and at least one item mapped | `Config.phone.enabled` not `true` |
| `aeterna_invkit.stash_open` | ped | presser | Moves the presser to the first configured stash point, then 25 m + radius away from every point, and sends the same request as the bound key at each stop; at a stash point the stash must open (ox_inventory's `invOpen` state, closed again at once), away from every point the `invkit.stash.far` refusal must come. The presser is then put back where they stood. With `Config.stash.anywhere = true` one opening is enough. Timeout 30000 ms | ox_inventory not started, or no stash point configured |
| `aeterna_invkit.item_use` | mock (client), destructive | presser | The server registers a usable on the first of `water`, `burger`, `sandwich` that no resource has registered, gives the presser one tagged with the run id and starts the use. The client sees the item, one progress bar, and the item gone. Only that tagged item is taken: any other player's use of the same item, and the presser's own untagged ones, go to ox_inventory untouched. The registration is dropped when `used` fires; on test end (or when `aeterna_core` or invkit stops) any tagged item left is removed | ox_inventory not started |
| `aeterna_invkit.phone_two_items` | ped, destructive | presser | The server gives two tagged test phones (battery 100, own `phoneId`, tag `aeterna_selftest` = run id): one fold-mapped and one slab-mapped item; the inventory shows both, each with its battery. Watch time 15000 ms, row timeout 25000 ms | ox_inventory or `aeterna_phonekit` not started, or `Config.phone.enabled` not `true` |
| `aeterna_invkit.phone_drop_active` | ped, destructive | presser | The server gives two tagged slab test phones and takes the second back after 4000 ms; the inventory shows one gone and another still carried (compared by `phoneId`, or item and slot for a phone without one). Watch time 15000 ms, row timeout 25000 ms | same |
| `aeterna_invkit.phone_no_item` | ped, destructive | presser | The server puts the presser's own phone items aside; the inventory shows no phone item. They are given back with the same metadata on `selftestEnd`. Watch time 15000 ms, row timeout 25000 ms | same |
| `aeterna_invkit.phone_device_save` | mock, destructive | server | Gives the presser one test phone item (battery 100, so phonekit does not write its start battery after the test's save) with a fresh `phoneId`, fires `deviceSave` with battery 42 and fold `closed`, checks the item's metadata, then removes that item by its `phoneId`; restored only when the item count is back to what it was | ox_inventory not started, `Config.phone.enabled` not `true`, or nobody pressed (`needs a presser`) |

The three phone rows check only what the presser's inventory shows. They are destructive: the tester has nothing to carry or drop, and everything the server gave is removed on `selftestEnd`. Whether phonekit's control centre,
fold screen and "no phone" toast look right is phonekit's own check; invkit cannot see phonekit's screen.

## Commands and keys / คำสั่งและปุ่มลัด

`+aeterna_invkit_open` suggests the default key `F2` (it does not clash with `ox_inventory`'s `TAB` and `1`–`5`); a player's own binding always wins. Players bind or change keys in **Settings → Key Bindings → FiveM**. The server owner can change or turn off the defaults with `setr aeterna_keys` (see the `aeterna_core` README).


- `+aeterna_invkit_open` / `-aeterna_invkit_open` — Open personal stash when near a configured point
- `aeterna_stash` — Open personal stash when `Config.stash.command = true`

## Support scope / ขอบเขตการรองรับ

- **Tested on / ทดสอบบน:** FXServer Enhanced & Legacy (cerulean, Lua 5.4, OneSync), `aeterna_core`, `aeterna_uikit`, `ox_inventory` 2.x, and optionally `qbx_core` 1.23+ and `ox_lib` 3.x.
- **Supported / รองรับ:** Standalone servers with `ox_inventory` and Qbox servers (`qbx_core`), Thai and English locales via `setr aeterna_locale`.
- **Not supported / ไม่รองรับ:** Passing functions across exports in `registerUsable`, running stash/item features without `ox_inventory`, or server-side distance checks without OneSync.

## Capabilities

What this resource is allowed to do to your server, from [`oss.json`](oss.json). Keep this table in sync with `oss.json`; widening a capability needs maintainer review.

| Capability | Declared |
|---|---|
| HTTP requests | none |
| `ExecuteCommand` | none |
| Registered commands | `+aeterna_invkit_open`, `-aeterna_invkit_open`, `aeterna_stash` |
| Convars read | none |
| Convars written | none |
| Server net events (accepted from clients) | `aeterna_invkit:sv:open`, `aeterna_invkit:sv:done`, `aeterna_invkit:sv:cancel` |
| Client net events (accepted from the server) | `aeterna_invkit:cl:use`, `aeterna_invkit:cl:refused` |
| NUI | no |
| Database tables | none (no DDL) |
| Files written | none |

## Verify before you install

Every release zip is built in CI and carries a build-provenance attestation. Check both the attestation and the checksum before you put it on your server:

```sh
gh attestation verify aeterna_invkit-<version>.zip --repo aeterna/nakara-oss --signer-workflow aeterna/nakara-oss/.github/workflows/release.yml
sha256sum -c SHA256SUMS --ignore-missing
```

Then read the capability table above (or `oss.json` inside the zip).

## Tests

From the repository root:

```sh
busted --config-file=.busted packages/invkit/spec
```

## License

MIT. See [LICENSE](../../LICENSE).
