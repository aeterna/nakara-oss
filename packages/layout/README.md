# aeterna_layout

Coordinate-based HUD layout editor and client-side layout persistence for the AETERNA Starter Kit ([ADR 0004](../../docs/adr/0004-aeterna-starter-kit.md) · [spec](../../docs/specs/aeterna_layout.md)).

ระบบจัดวางตำแหน่งและปรับขนาดองค์ประกอบ HUD สำหรับเซิร์ฟเวอร์ FiveM ในชุด AETERNA Starter Kit ให้ผู้เล่นแต่ละคนลากย้าย ปรับขนาด หรือซ่อนชิ้นส่วน HUD ที่ทรัพยากรอื่นวาดขึ้น และบันทึกไว้ในเครื่องของผู้เล่นเอง

---

## What it does / การทำงาน

- **Cross-resource coordinate protocol (โปรโตคอลพิกัดข้ามทรัพยากร):** Every FiveM NUI page runs in its own frame, so resources cannot drag each other's DOM directly. Owner resources describe their movable boxes (`id`, `w`, `h`, default `x`, `y`, `ax`, `ay`); `aeterna_layout` draws dashed stand-in boxes in its own frame while the editor is open and emits `aeterna_layout:apply` with `{ x, y, ax, ay, scale, hidden }` so each owner moves its own NUI or game-drawn element.
- **Resolution-independent anchoring (การยึดตำแหน่งตามสัดส่วนหน้าจอ):** Positions are stored as screen fractions (`0–1`) relative to an anchor (`0`, `0.5`, `1` chosen from the nearest screen third on drop), clamped so the whole scaled element stays on screen across resolution changes.
- **Client KVP persistence (บันทึกในเครื่องผู้เล่น):** Saved under `aeterna_layout:places:v1` via `AeternaCore.kvp` on **Done**, and only for elements moved from their default. Places of temporarily stopped resources are preserved. The snap step pick is kept in `aeterna_layout:prefs:v1`.
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
| `Config.menuPanel` | `true` | The menu entry opens a panel with Edit, Reset all and Export / import; `false` = the 0.1 behaviour (opens the editor) / เปิดแผงเมนู แก้ไข · รีเซ็ตทั้งหมด · ส่งออก/นำเข้า |
| `Config.snapSteps` | `{ 8, 16, 32 }` | Snap steps offered in the editor; `Config.snap` stays the default until the player picks / ระยะเส้นตารางที่เลือกได้ |
| `Config.presets` | `default`, `compact`, `centered` | Preset layouts (up to 8): name (≤ 24, `^[%w_%-]+$`) → `{ ["<owner>/<id>"] = { x, y, ax, ay, scale } }`. Unnamed elements go to their default; a preset never sets `hidden`. Label: locale key `layout.preset.<name>` or the name / ชุดจัดวางสำเร็จรูป |

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
- **Preset** select applies a preset to the session; **Grid snap** select picks Off / 8 / 16 / 32 px (kept on the player's machine); the grid shows while dragging unless snap is off or Shift is held.
- **Export / import** shows the saved places of the elements registered now as one line of text (`aeterna-layout:1:…`, select it and press Ctrl+C) and takes such a line back; an import moves the stand-ins, **Done** saves and **Cancel** undoes. The text never leaves the player's machine through this resource.

The `aeterna_uikit` menu entry opens a small panel (**Edit**, **Reset all** after a confirm, saved at once, and **Export / import**). Pressing Reset all arms the client with a one-time token; the reset runs only when the confirm sends that token back within 30 s, so a local event or a replayed message cannot clear a layout. The command and the key mapping still open the editor directly.

### Keeping elements on screen (0.2)

The page reports its size; when an element grows (a new `w`/`h`, a bigger scale or a smaller screen) layout moves its anchor point just far enough to keep the whole box on screen and sends `aeterna_layout:apply` with that place. The clamped place is not saved, so the element returns to the saved place when it shrinks again. A box larger than the screen starts at its top-left corner.

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
| Client net events (accepted from the server) | `aeterna_layout:cl:open` (optional `{ mode = 'editor' \| 'share' }`, or `{ mode = 'arm' \| 'reset', token }` for Reset all from the panel) |
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
busted --config-file=.busted packages/layout/spec
```

## License

MIT. See [LICENSE](../../LICENSE). Bundled Lucide icon SVGs are ISC-licensed; see [NOTICE](NOTICE).
