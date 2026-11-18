# aeterna_layout

Coordinate-based HUD layout editor and client-side layout persistence for the AETERNA Starter Kit ([ADR 0004](../../docs/adr/0004-aeterna-starter-kit.md) · [spec](../../docs/specs/aeterna_layout.md)).

ระบบจัดวางตำแหน่งและปรับขนาดองค์ประกอบ HUD สำหรับเซิร์ฟเวอร์ FiveM ในชุด AETERNA Starter Kit ให้ผู้เล่นแต่ละคนลากย้าย ปรับขนาด หรือซ่อนชิ้นส่วน HUD ที่ทรัพยากรอื่นวาดขึ้น และบันทึกไว้ในเครื่องของผู้เล่นเอง

---

## What it does / การทำงาน

- **Cross-resource coordinate protocol (โปรโตคอลพิกัดข้ามทรัพยากร):** Every FiveM NUI page runs in its own frame, so resources cannot drag each other's DOM directly. Owner resources describe their movable boxes (`id`, `w`, `h`, default `x`, `y`, `ax`, `ay`); `aeterna_layout` draws dashed stand-in boxes in its own frame while the editor is open and emits `aeterna_layout:apply` with `{ x, y, ax, ay, scale, hidden }` so each owner moves its own NUI or game-drawn element.
- **Resolution-independent anchoring (การยึดตำแหน่งตามสัดส่วนหน้าจอ):** Positions are stored as screen fractions (`0–1`) relative to an anchor (`0`, `0.5`, `1` chosen from the nearest screen third on drop), clamped so the whole scaled element stays on screen across resolution changes.
- **Client KVP persistence (บันทึกในเครื่องผู้เล่น):** Saved under `aeterna_layout:places:v1` via `AeternaCore.kvp` on **Done**, and only for elements moved from their default. Places of temporarily stopped resources are preserved.
- **Deliberate limits (ขอบเขตที่จำกัดไว้):** No element rotation, no separate width/height stretching, no server-side database or cross-machine sync, and no moving of base-game HUD components other than those managed by an owner resource (such as the minimap in `aeterna_hudkit`).

## Install / การติดตั้ง

1. Download `aeterna_layout-<version>.zip` from the [Releases](https://github.com/aeterna/nakara-oss/releases) page and verify it (see below).
2. Extract it into your `resources/` folder so you have `resources/aeterna_layout/fxmanifest.lua`.
3. Ensure `aeterna_core` and `aeterna_uikit` start before `aeterna_layout` in `server.cfg`:

   ```cfg
   ensure aeterna_core
   ensure aeterna_uikit
   ensure aeterna_layout
   ```

Startup order among element owners does not matter: owners that start before `aeterna_layout` re-register when `aeterna_layout` fires `aeterna_layout:hello`.

## Config / การตั้งค่า

Configured in `config.lua` (no convars):

| Key | Default | Meaning / ความหมาย |
|---|---|---|
| `Config.snap` | `8` | Grid step in px while dragging (`0` disables snapping; holding Shift drags without snap) / ระยะเส้นตารางขณะลาก (px) กด Shift ค้างเพื่อลากอย่างอิสระ |
| `Config.scale.min` / `.max` / `.step` | `0.5` / `2.0` / `0.05` | Allowed scale range and increment in the editor / ช่วงขนาดต่ำสุด สูงสุด และขั้นการปรับขนาด |
| `Config.maxElements` | `64` | Maximum registered elements before refusing with a `warn` / จำนวนองค์ประกอบสูงสุดที่ลงทะเบียนได้ |
| `Config.menu` | `true` | Adds the "Edit HUD layout" entry to the `aeterna_uikit` menu / เพิ่มรายการแก้ไขเลย์เอาต์ในเมนู `aeterna_uikit` |

Shared convars read via `aeterna_core`: `aeterna_locale` (`en` or `th`, set with `setr`), `aeterna_theme` (`nui://<resource>/<path>.css`, set with `setr`).

## Owner protocol / การเชื่อมโยงจากทรัพยากรอื่น

Element owners communicate with `aeterna_layout` using **client-local events** only (no exports or cross-resource function references), so owners work with or without `aeterna_layout` running:

| Event | Fired by | Payload | Description |
|---|---|---|---|
| `aeterna_layout:add` | owner | `def` | Registers or replaces one element and triggers an immediate `aeterna_layout:apply`. |
| `aeterna_layout:remove` | owner | `id` | Removes one element from the active registry (saved KVP place is kept). |
| `aeterna_layout:hello` | `aeterna_layout` | — | Fired once when `aeterna_layout` starts on the client; owners re-send their `aeterna_layout:add`. |
| `aeterna_layout:apply` | `aeterna_layout` | `owner, id, place` | `place = { x, y, ax, ay, scale, hidden }`. Owners act only when `owner == GetCurrentResourceName()`. |

### `def` schema

| Field | Type | Rule |
|---|---|---|
| `id` | `string` | `1–32` chars matching `^[%w_%-]+$`, unique per owner |
| `label` | `string` | Plain text or translated label (`1–32` visible chars) shown on the stand-in box |
| `w`, `h` | `number` | Base size in CSS px at scale `1.0` (`8–2000`) |
| `x`, `y` | `number` | Default anchor screen fraction (`0–1`) |
| `ax`, `ay` | `number` | Default anchor point on the element (`0`, `0.5`, or `1`) |
| `scalable` | `boolean` | Optional (default `true`); `false` hides the scale control for this element |
| `hideable` | `boolean` | Optional (default `false`); `true` allows the player to hide/show the element |
| `owner` | `string` | Optional fallback owner resource name (`1–64` chars, see note below) |

**Owner detection note:** Inside `aeterna_layout:add` and `aeterna_layout:remove`, `aeterna_layout` checks `GetInvokingResource()` first. When the runtime does not populate `GetInvokingResource()` for a local `TriggerEvent`, `def.owner` is required and must equal a started resource (`GetResourceState(def.owner)` is `'started'` or `'starting'`). That fallback means another client script installed by the server owner on that client could pass a started resource's name in `def.owner` to move its element on that client only.

### Placement formula for owners

```lua
local left = place.x * screenWidth - place.ax * width * place.scale
local top  = place.y * screenHeight - place.ay * height * place.scale
```

## Commands and keys / คำสั่งและปุ่มลัด

All key mappings ship with **no default key** (ADR 0004 decision 10). Players bind them in **Settings → Key Bindings → FiveM**:

- `aeterna_layout` — Open the HUD layout editor (console / chat)
- `+aeterna_layout_edit` / `-aeterna_layout_edit` — Open the HUD layout editor (key binding)

Inside the editor:
- **Mouse drag** moves an element live (updates sent at most every 100 ms and on drop); hold **Shift** to bypass grid snapping.
- **Tab / Shift+Tab** cycles between elements; **Arrow keys** nudge by 1 px (**Shift + Arrow** by 10 px); **`+` / `-`** adjusts scale.
- **Enter** confirms **Done** when no toolbar button has focus.
- **ESC** or **Cancel** restores all elements to where they were when the editor opened.

## Support scope / ขอบเขตการรองรับ

- **Tested on / ทดสอบบน:** FXServer Enhanced & Legacy (cerulean, Lua 5.4), standalone with `aeterna_core` + `aeterna_uikit`, and alongside `qbx_core` 1.23 and `ox_lib` 3.x.
- **Supported / รองรับ:** Standalone FiveM servers and Qbox/QBCore/ESX servers running `aeterna_core` and `aeterna_uikit`, custom CSS theme overrides via `setr aeterna_theme`, and Thai/English locales.
- **Not supported / ไม่รองรับ:** Passing cross-resource function references, rotating or non-uniformly stretching elements, or running without `aeterna_core`.

## Capabilities

What this resource is allowed to do to your server, from [`oss.json`](oss.json). Keep this table in sync with `oss.json`; widening a capability needs maintainer review.

| Capability | Declared |
|---|---|
| HTTP requests | none |
| `ExecuteCommand` | none |
| Registered commands | `aeterna_layout`, `+aeterna_layout_edit`, `-aeterna_layout_edit` |
| Convars read | none |
| Convars written | none |
| Server net events (accepted from clients) | none |
| Client net events (accepted from the server) | `aeterna_layout:cl:open` |
| NUI | yes |
| Database tables | none (no DDL) |
| Files written | none |

## Verify before you install

Every release zip is built in CI and carries a build-provenance attestation. Check both the attestation and the checksum before you put it on your server:

```sh
gh attestation verify aeterna_layout-<version>.zip --repo aeterna/nakara-oss --signer-workflow aeterna/nakara-oss/.github/workflows/release.yml
sha256sum -c SHA256SUMS --ignore-missing
```

Then read the capability table above (or `oss.json` inside the zip).

## Tests

From the repository root:

```sh
busted --lpath='./packages/devkit/busted/?.lua;./?.lua;./?/init.lua' --pattern=_spec packages/layout/spec
```

## License

MIT. See [LICENSE](../../LICENSE). Bundled Lucide icon SVGs are ISC-licensed; see [NOTICE](NOTICE).
