# aeterna_uikit

Server-owned UI panels, client prompts (`confirm`, `input`, `progress`, `skillCheck`, `keyHints`), and a shared entry-point menu for the AETERNA Starter Kit ([ADR 0004](../../docs/adr/0004-aeterna-starter-kit.md) · [spec](../../docs/specs/aeterna_uikit.md)).

ชุดเครื่องมือ UI สำหรับเซิร์ฟเวอร์ FiveM ในชุด AETERNA Starter Kit ประกอบด้วยแผงเมนูที่ฝั่งเซิร์ฟเวอร์ควบคุมทั้งหมด (Panels), กล่องโต้ตอบฝั่งไคลเอนต์ (`confirm`, `input`, `progress`, `skillCheck`, `keyHints`) และระบบเมนูรวมสำหรับเชื่อมทรัพยากรอื่น

---

## What it does / การทำงาน

- **Server-owned panels (แผงข้อมูลฝั่งเซิร์ฟเวอร์):** The server sends a validated spec (`sm` / `md` / `lg`, up to 40 blocks: `text`, `list`, `field`, `toggle`, `select`, `progress`, `divider`, `buttons`, and since 0.2 `tabs`, `slider`, `table`, `empty`). The client renders it in the active theme and returns only button/list actions and validated field values from that spec via the server-local event `aeterna_uikit:action`.
- **0.2 blocks (บล็อกใหม่ใน 0.2):** `tabs` (2–6 tabs, one per spec; any block may carry `tab = '<tab id>'`; with `report = true` a switch fires an action with the tab id), `slider` (`min`, `max`, `step`, `value`, `unit?`; arrows one step, Page Up / Page Down ten steps, Home / End), `table` (≤ 6 columns, ≤ 50 rows, `selectable = true` turns row ids into actions), `empty` (icon, label, body, one optional action button). `list` accepts `search = true | { placeholder }` (up to 200 items with search, 50 without) and `list`/`table` accept `empty = { icon?, label, body? }`. Top-level `detailOf` / `detailItem` mark a screen as the detail of a list item; uikit's own window ignores them. Panels and prompts fade in and out, with no movement under reduced motion; text sizes follow the theme type tokens.
- **Client prompts (หน้าต่างโต้ตอบฝั่งผู้เล่น):** `confirm`, `input`, `progress`, `skillCheck`, and `keyHints` / `clearKeyHints`. Focus is acquired and released through `aeterna_core`; losing focus automatically cancels the active panel or prompt. Since 0.2, a focus overlay from another resource only pauses them: the panel or prompt stays on screen and ignores input until the overlay releases (a progress bar keeps running, a skill check's marker stops).
- **Shared menu (เมนูรวม):** Other resources register menu entries with optional ACE permission filters via `addMenuEntry`. Entries are automatically removed if the owning resource stops.
- **Deliberate limits (ขอบเขตที่จำกัดไว้):** No drag-and-drop layout editor (handled by `aeterna_layout`), no toast notifications (`aeterna_notify`), and no world markers or 3D text.

## Install / การติดตั้ง

1. Download `aeterna_uikit-<version>.zip` from the [Releases](https://github.com/aeterna/nakara-oss/releases) page and verify it (see below).
2. Extract it into your `resources/` folder so you have `resources/aeterna_uikit/fxmanifest.lua`.
3. Ensure `aeterna_core` starts before `aeterna_uikit` in `server.cfg`:

   ```cfg
   ensure aeterna_core
   ensure aeterna_uikit
   ```

## Config / การตั้งค่า

| Convar | Default | Meaning / ความหมาย |
|---|---|---|
| `aeterna_uikit_menu_title` | empty | Title of the shared menu; empty falls back to locale `uikit.menu.title` / ชื่อหัวข้อเมนูรวม (หากว่างจะใช้ค่าจากไฟล์ภาษา `uikit.menu.title`) |

Shared convars read via `aeterna_core`: `aeterna_locale` (`en` or `th`, set with `setr`), `aeterna_theme` (`nui://<resource>/<path>.css`, set with `setr`).

## Exports & Events / การเรียกใช้งาน

### Server exports

| Export | Returns | Description |
|---|---|---|
| `exports.aeterna_uikit:open(src, spec)` | `panelId` or `nil, err` | Validates `spec` and opens a panel for player `src` (replacing any open panel with reason `replaced`). |
| `exports.aeterna_uikit:update(src, panelId, patch)` | `boolean` | Updates `label`, `value`, `items`, or `disabled` on blocks of an open panel; since 0.2 also `rows` (table), `value` of `tabs` and `slider` (refused out of range or off the step grid), and `empty` (list, table). |
| `exports.aeterna_uikit:close(src, panelId?)` | `boolean` | Closes the open panel for `src`. |
| `exports.aeterna_uikit:isOpen(src)` | `panelId` or `nil` | Returns the currently open `panelId` for `src`. |
| `exports.aeterna_uikit:addMenuEntry(entry)` | `boolean` | Registers `{ id, label, icon?, order?, group?, ace? }` for the calling resource. |
| `exports.aeterna_uikit:removeMenuEntry(id)` | `boolean` | Removes a menu entry owned by the calling resource. |
| `exports.aeterna_uikit:showMenu(src)` | `boolean` | Opens the shared menu for player `src`. |

Server-local events (filter on `data.owner == GetCurrentResourceName()`):

- `aeterna_uikit:action` → `(src, { owner, panelId, action, values })`
- `aeterna_uikit:menu` → `(src, { owner, id })`

### Client exports

| Export | Returns | Description |
|---|---|---|
| `exports.aeterna_uikit:confirm(opts)` | `boolean` | Modal confirmation dialog (`{ title, body?, confirm?, cancel?, danger? }`). |
| `exports.aeterna_uikit:input(opts)` | `table` or `nil` | Modal form with up to 6 fields (`{ title, fields }`). |
| `exports.aeterna_uikit:progress(opts)` | `boolean` | Timed progress bar (`300–60000` ms) with optional control disabling and cancel support. |
| `exports.aeterna_uikit:skillCheck(opts)` | `boolean` | Moving marker skill check (`difficulty = 'easy'|'medium'|'hard'`, `rounds = 1..5`). |
| `exports.aeterna_uikit:keyHints(list)` | `nil` | Displays up to 4 command key-binding hints (`{ { key, label } }`). |
| `exports.aeterna_uikit:clearKeyHints()` | `nil` | Hides the key hints overlay. |

## Commands and keys / คำสั่งและปุ่มลัด

All key mappings ship with **no default key** (ADR 0004 decision 10) so they never conflict with existing bindings. Players bind them in **Settings → Key Bindings → FiveM**:

- `aeterna_uikit_menu` / `+aeterna_uikit_menu` — Open the shared menu
- `+aeterna_uikit_cancel` — Cancel an active progress bar
- `+aeterna_uikit_skill` — Trigger skill check (Space also works while a skill check is active)

## Support scope / ขอบเขตการรองรับ

- **Tested on / ทดสอบบน:** FXServer Enhanced & Legacy (cerulean, Lua 5.4), standalone with `aeterna_core`, and alongside `qbx_core` 1.23 and `ox_lib` 3.x.
- **Supported / รองรับ:** Standalone FiveM servers and Qbox/QBCore/ESX servers running `aeterna_core`, custom CSS theme overrides via `setr aeterna_theme`, and Thai/English locales.
- **Not supported / ไม่รองรับ:** Passing cross-resource function references into exports, rendering raw HTML in labels/text, or running without `aeterna_core`.

## Capabilities

What this resource is allowed to do to your server, from [`oss.json`](oss.json). Keep this table in sync with `oss.json`; widening a capability needs maintainer review.

| Capability | Declared |
|---|---|
| HTTP requests | none |
| `ExecuteCommand` | none |
| Registered commands | `aeterna_uikit_menu`, `+aeterna_uikit_menu`, `-aeterna_uikit_menu`, `+aeterna_uikit_cancel`, `-aeterna_uikit_cancel`, `+aeterna_uikit_skill`, `-aeterna_uikit_skill` |
| Convars read | `aeterna_uikit_menu_title` |
| Convars written | none |
| Server net events (accepted from clients) | `aeterna_uikit:sv:action`, `aeterna_uikit:sv:menu`, `aeterna_uikit:sv:showMenu` |
| Client net events (accepted from the server) | `aeterna_uikit:cl:open`, `aeterna_uikit:cl:update`, `aeterna_uikit:cl:close` |
| NUI | yes |
| Database tables | none (no DDL) |
| Files written | none |

## Verify before you install

Every release zip is built in CI and carries a build-provenance attestation. Check both the attestation and the checksum before you put it on your server:

```sh
gh attestation verify aeterna_uikit-<version>.zip --repo aeterna/nakara-oss --signer-workflow aeterna/nakara-oss/.github/workflows/release.yml
sha256sum -c SHA256SUMS --ignore-missing
```

Then read the capability table above (or `oss.json` inside the zip).

## Self-tests (0.2)

Registered with `aeterna_core` as `aeterna_uikit.<name>` and run from `aeterna_testkit` (or the core console command,
where ped and eye tests are GAP). Spec: `docs/specs/aeterna_uikit.md` § Self-tests (0.2).

| Name | Kind | What it checks |
| --- | --- | --- |
| `spec_limits` | headless | `open` refuses every spec over a limit (41 blocks, two `tabs`, 1 or 7 tabs, 7 columns, 51 rows, 1001 slider steps, 51 items without search, 201 with search, a 61-character Thai title) and accepts the largest inside it |
| `values_recheck` | headless | Values coming back with an action are checked again: a slider off the grid, out of range or as a string, an unknown tab and an unknown key are dropped; a hidden tab's field still comes back |
| `forged_action` | headless | An action the spec does not offer (unknown id, tab id without `report`, row of a non-selectable table, disabled button, wrong `panelId`, no panel) is dropped |
| `panel_every_block` | eye | An `md` panel with tabs, a searchable list, a slider, a table and an empty state |
| `tabs_switch` | ped | The page clicks the second tab; the owner receives its id and the right blocks show |
| `slider_keyboard` | ped | The page presses ArrowRight on the slider and OK; the owner receives one step more and the page shows the same number |
| `motion_reduced` | eye | The test panel leaves and enters every 2 s, so the person sees whether it fades and rises |
| `focus_lost_closes` | ped | A focus loss closes the panel and the owner receives `__close` |
| `overlay_pauses` | eye | The panel stays open and ignores clicks behind the eye card; after the answer its button counts presses |

Client tests open a test panel on the presser's client only. Its actions go to a client-side panel manager that runs
the server's validation, never to the server; an open panel is replaced as if the server had opened a new one.
`focus_lost_closes` fires core's `aeterna_core:focusLost` event itself, because one resource cannot be a second one.

Core's local events (`aeterna_core:selftest`, `selftestEnd` and the focus events) count only when `aeterna_core`
fired them, and open test state is torn down when `aeterna_core` stops.

## Tests

From the repository root:

```sh
busted --lpath='./packages/devkit/busted/?.lua;./?.lua;./?/init.lua' --pattern=_spec packages/uikit/spec
node --test packages/uikit/spec/   # slider grid math of the page (html/slider-math.js)
```

## License

MIT. See [LICENSE](../../LICENSE). Bundled Lucide icon SVGs are ISC-licensed; see [NOTICE](NOTICE).
