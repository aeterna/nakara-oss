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

## Commands and keys / คำสั่งและปุ่มลัด

All key mappings ship with **no default key** (ADR 0004 decision 10) so they never clash with `ox_inventory` (`TAB`, `1`–`5`). Players bind them in **Settings → Key Bindings → FiveM**:

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
busted --lpath='./packages/devkit/busted/?.lua;./?.lua;./?/init.lua' --pattern=_spec packages/invkit/spec
```

## License

MIT. See [LICENSE](../../LICENSE).
