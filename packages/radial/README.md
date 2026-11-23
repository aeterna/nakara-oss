# aeterna_radial

A radial menu for the AETERNA Starter Kit: a ring of 4–8 slots around the screen centre, where a slot can open a second ring. Other resources add slots by export, with conditions that decide when each slot shows ([ADR 0005](../../docs/adr/0005-starter-kit-0-2.md) · [spec](../../docs/specs/aeterna_radial.md)).

เมนูวงกลมสำหรับชุด AETERNA Starter Kit: ช่องคำสั่ง 4–8 ช่องเรียงรอบกลางจอ ช่องหนึ่งเปิดวงที่สองได้ ทรัพยากรอื่นเพิ่มช่องผ่าน export พร้อมเงื่อนไขว่าช่องนั้นจะแสดงเมื่อใด

---

## What it does / การทำงาน

- **Client slots (ช่องฝั่งผู้เล่น):** fire a client-local event in the owning resource. For things that affect only the player who pressed (toggle a HUD part, open the player's own panel). / ส่ง event ภายในเครื่องผู้เล่นให้ทรัพยากรเจ้าของ ใช้กับสิ่งที่มีผลต่อผู้กดคนเดียว
- **Server slots (ช่องฝั่งเซิร์ฟเวอร์):** send the pick to the server, which re-checks `vehicle`, `jobs`/`grade` and `ace` with its own data before it fires a server-local event in the owning resource. For anything that reaches other players. / ส่งการเลือกไปเซิร์ฟเวอร์ ซึ่งตรวจเงื่อนไขซ้ำด้วยข้อมูลของตัวเองก่อนส่ง event ให้ทรัพยากรเจ้าของ ใช้กับทุกอย่างที่มีผลต่อผู้เล่นคนอื่น
- **Rings (วง):** the root ring shows the visible root slots of every resource, sorted by `order`, then resource, then `id`. A group (a slot with children) opens its own ring. More than 8 visible slots: the first 8 show and one `warn` names the resources that were cut. / วงแรกแสดงช่องที่มองเห็นของทุกทรัพยากร เกิน 8 ช่องจะแสดง 8 ช่องแรกและเตือนใน log
- **Deliberate limits (ขอบเขตที่จำกัดไว้):** no third ring level, no icons from files, no per-player ordering, no built-in slots. The kit ships an empty menu; a server fills it. / ไม่มีวงชั้นที่สาม ไม่มีไอคอนจากไฟล์ ไม่มีชุดช่องสำเร็จรูป

## Install / การติดตั้ง

1. Download `aeterna_radial-<version>.zip` from the [Releases](https://github.com/aeterna/nakara-oss/releases) page and verify it (see below).
2. Extract it into your `resources/` folder so you have `resources/aeterna_radial/fxmanifest.lua`.
3. Start it after `aeterna_core` and `aeterna_uikit` in `server.cfg`:

   ```cfg
   ensure aeterna_core
   ensure aeterna_uikit
   ensure aeterna_radial
   ```

4. Players bind a key or a gamepad button in **Settings → Key Bindings → FiveM → "Open radial menu"**. The keyboard mapping suggests `F3` by default; the gamepad mapping has no default. The server owner can change or turn off defaults with `setr aeterna_keys` (see the `aeterna_core` README). / ผู้เล่นตั้งปุ่มเองใน Settings → Key Bindings → FiveM (คีย์บอร์ดตั้งต้น `F3` จอยไม่มีปุ่มตั้งต้น)

## Config / การตั้งค่า

`config.lua`:

| Key | Default | Meaning / ความหมาย |
|---|---|---|
| `Config.mode` | `'hold'` | `hold`: open while the key is held; releasing picks the slot under the pointer, or closes when none. `toggle`: press to open, pick with a click or accept, press again or Esc to close / `hold` กดค้างเพื่อเปิด ปล่อยเพื่อเลือก · `toggle` กดเปิด คลิกเลือก กดอีกครั้งหรือ Esc เพื่อปิด |
| `Config.radius` | `150` | Ring radius in px at 1080p / รัศมีวงที่ความสูงจอ 1080 px |
| `Config.deadZone` | `0.35` | Centre area, as a fraction of the radius (mouse) or of the stick range (gamepad), where no slot is hovered; a value outside 0–1 falls back to `0.35` with a `warn` / พื้นที่กลางวงที่ไม่เลือกช่องใด (นอกช่วง 0–1 จะใช้ `0.35`) |
| `Config.maxPerOwner` | `64` | Slots one resource may register, client and server counted apart; more are refused with a `warn` / จำนวนช่องสูงสุดต่อทรัพยากร |
| `Config.maxTotal` | `128` | Slots across all resources, per side / จำนวนช่องรวมสูงสุดต่อฝั่ง |
| `Config.whileDead` | `false` | When `false`, the menu does not open while the player's ped is dead or ragdolling, and an open menu closes when that happens / เมื่อเป็น `false` จะเปิดเมนูไม่ได้ขณะตายหรือล้ม และเมนูที่เปิดอยู่จะปิดเอง |

Shared convars read via `aeterna_core`: `aeterna_locale` (`en` or `th`), `aeterna_theme`, `aeterna_theme_preset` (all set with `setr`).

## Slots / ช่องคำสั่ง

```lua
{
    id     = 'trunk',            -- ≤ 32, ^[%w_%-]+$, unique per resource and side
    label  = 'Trunk',            -- ≤ 20 characters (Thai counts per character)
    icon   = 'car',              -- optional, a name from html/icons.js (the aeterna_uikit icon map)
    order  = 10,                 -- optional, 0–1000, default 100
    parent = 'vehicle',          -- optional, id of a root slot of the same resource (makes it a group)
    when   = {                   -- optional; every present condition must hold
        vehicle = 'in',          -- 'in' | 'out' | 'driver'
        jobs    = { 'mechanic' },-- ≤ 8 names, needs qbx_core
        grade   = 2,             -- 0–100, needs jobs
        ace     = 'aeterna.garage.trunk', -- server slots only
        flags   = { 'near_car' },-- ≤ 4 names set with setFlag; all must be true
    },
}
```

- A slot whose `parent` is itself a child, names a slot of another resource, or that already has children, is refused (`parent: depth` / `parent: unknown`). A group with no visible children is hidden; a slot whose children are all removed is an ordinary slot again.
- A server pick of a child must also pass its group's `vehicle`, `jobs`/`grade` and `ace`.
- Custom conditions are flags: the owning resource evaluates its own check and calls `setFlag(name, value)` when the result changes. The server does **not** re-check flags; the owner re-checks its own state in its handler. Flags reset when the owner stops.

## Exports & Events / การเรียกใช้งาน

### Client exports

| Export | Returns | Description |
|---|---|---|
| `exports.aeterna_radial:addSlot(slot)` | `true` or `false, err` | Adds or replaces (same resource and `id`) a client slot owned by the calling resource |
| `exports.aeterna_radial:removeSlot(id)` | `boolean` | Removes the slot and, for a group, its children |
| `exports.aeterna_radial:setFlag(name, value)` | `nil` | `name` ≤ 32 `^[%w_%-]+$`, `value` boolean, scoped to the calling resource; ≤ 32 flags per resource |
| `exports.aeterna_radial:isOpen()` | `boolean` | Whether the menu is open |
| `exports.aeterna_radial:close()` | `nil` | Closes the menu with no pick |

### Server exports

| Export | Returns | Description |
|---|---|---|
| `exports.aeterna_radial:addSlot(slot)` | `true` or `false, err` | Adds or replaces a server slot owned by the calling resource; sent to every player who passes its `ace`, now and on join |
| `exports.aeterna_radial:removeSlot(id)` | `boolean` | Removes the slot and, for a group, its children |

### What comes back

Filter on the owner, so a restarted resource never reacts to another one's slots:

```lua
-- client: a client slot was picked
AddEventHandler('aeterna_radial:select', function(owner, id)
    if owner ~= GetCurrentResourceName() then return end
end)

-- server: a server slot was picked and passed vehicle, jobs/grade and ace
AddEventHandler('aeterna_radial:select', function(src, pick)
    if pick.owner ~= GetCurrentResourceName() then return end
end)
```

A server pick that fails a check is dropped with a `debug` log. When a slot's conditions no longer hold at the moment of the pick (for example the player left the car), the client shows `radial.denied` in the centre for 1 s instead of sending it.

## Input / การควบคุม

| Action | Mouse and keyboard | Gamepad |
|---|---|---|
| Open | The bound key | The bound button |
| Hover | Pointer angle from the centre, or ← → | Left stick, or d-pad ← → |
| Pick | Release the key (`hold`), left click, or Enter | Release the button (`hold`) or A |
| Back (child ring) | Right click, Backspace, or click the centre | B |
| Close | Esc, or click the centre / release with nothing hovered in the root ring | B in the root ring |

While the menu is open the player keeps walking and driving; camera look and weapon fire are disabled. Another resource taking focus closes the menu with no pick; an overlay (for example the test kit's eye card) pauses it until focus returns. With `prefers-reduced-motion: reduce` nothing moves.

## Self-tests / การทดสอบตัวเอง

radial registers these tests with `aeterna_core` on start (`aeterna_testkit` lists and runs them). A ped or eye test
with nobody to run it is GAP.

Self-test events are accepted only from `aeterna_core` (the invoking resource), so no other resource can start a test or its server preparation. When `aeterna_core` stops mid-test, the server drops its temporary slot.

| Test | Kind | Runs | What it checks |
|---|---|---|---|
| `aeterna_radial.registry` | headless | server | A private registry: add, replace, `maxPerOwner`, `maxTotal`, a child of a child and a cross-owner parent refused, owner stop removes only its slots and flags |
| `aeterna_radial.conditions` | headless | server | `vehicle` in/out/driver, `jobs` + `grade`, `jobs` false without `qbx_core`, `flags` all-true |
| `aeterna_radial.server_recheck` | ped | presser | On core's `aeterna_core:selftestStarted` the server registers a server slot with `when.vehicle = 'in'` and sends it to the presser alone. The client, on foot, sends a pick for it straight to the server; the server must drop it. An accepted pick makes the server take the slot back, which the client sees as FAIL. The slot is removed on core's server-side `aeterna_core:selftestEnd`. SKIP while the presser is in a vehicle |
| `aeterna_radial.open_pick` | eye | presser | Adds six slots "Test 1" … "Test 6" and opens the ring, hovers each test slot (400 ms per step) and picks "Test 3" (a feed line says "picked Test 3"); then the card asks for the look |
| `aeterna_radial.child_ring` | eye | presser | Adds a group with three children and opens the ring; the test picks the group, hovers the children (400 ms per step) and goes back; then the card asks for the look |
| `aeterna_radial.gamepad` | eye | presser | Adds six slots and opens the ring; after the person closes it with the pad (pick or cancel), the card asks. A close with mouse or keyboard does not count. With no pad input after 3000 ms the row SKIPs with `no gamepad input` |

The eye tests act before the card because the card takes focus and pauses the ring. Their slots belong to
`aeterna_radial` and are removed, and the ring closed, when the test ends. The ring also shows the root slots of other
resources that are visible at the time.

## Commands and keys / คำสั่งและปุ่มลัด

- `aeterna_radial_open` — chat or F8: opens the menu in `toggle` mode (runs again to close)
- `+aeterna_radial_open` / `-aeterna_radial_open` — key mapping for keyboard (default `F3`) and gamepad (no default key)

## Support scope / ขอบเขตการรองรับ

- **Tested on / ทดสอบบน:** busted specs only so far; the kit-test FXServer smoke steps in the spec have not been run yet. / ยังทดสอบด้วย busted เท่านั้น ยังไม่ได้ทดสอบบนเซิร์ฟเวอร์จริง
- **Supported / รองรับ:** standalone FiveM servers running `aeterna_core` and `aeterna_uikit`; `jobs` conditions with `qbx_core`; custom CSS via `setr aeterna_theme`; Thai and English.
- **Not supported / ไม่รองรับ:** passing functions between resources, a third ring level, `jobs` without `qbx_core` (such slots never show and log one `warn` each).

## Capabilities

What this resource is allowed to do to your server, from [`oss.json`](oss.json). Keep this table in sync with `oss.json`; widening a capability needs maintainer review.

| Capability | Declared |
|---|---|
| HTTP requests | none |
| `ExecuteCommand` | none |
| Registered commands | `aeterna_radial_open`, `+aeterna_radial_open`, `-aeterna_radial_open` |
| Convars read | none |
| Convars written | none |
| Server net events (accepted from clients) | `aeterna_radial:sv:hello`, `aeterna_radial:sv:select` |
| Client net events (accepted from the server) | `aeterna_radial:cl:slots`, `aeterna_radial:cl:slot` |
| NUI | yes |
| Database tables | none (no DDL) |
| Files written | none |

## Verify before you install

Every release zip is built in CI and carries a build-provenance attestation. Check both the attestation and the checksum before you put it on your server:

```sh
gh attestation verify aeterna_radial-<version>.zip --repo aeterna/nakara-oss --signer-workflow aeterna/nakara-oss/.github/workflows/release.yml
sha256sum -c SHA256SUMS --ignore-missing
```

Then read the capability table above (or `oss.json` inside the zip).

## Tests

From the repository root:

```sh
busted --config-file=.busted packages/radial/spec
```

## License

MIT. See [LICENSE](../../LICENSE). Bundled Lucide icon SVGs are ISC-licensed and the IBM Plex Sans Thai font is OFL-1.1; see [NOTICE](NOTICE).
