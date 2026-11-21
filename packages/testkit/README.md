# aeterna_testkit

One button that tests a whole Starter Kit install: a menu that runs every self-test registered with `aeterna_core`, an eye-check card for tests that need a person, a player B invite for two-player tests, and a report you can attach to an issue as it is ([ADR 0005](../../docs/adr/0005-starter-kit-0-2.md) · [spec](../../docs/specs/aeterna_testkit.md)).

ปุ่มเดียวสำหรับทดสอบ Starter Kit ทั้งชุด: เมนูที่สั่งรัน self-test ทุกตัวที่ลงทะเบียนไว้กับ `aeterna_core` การ์ดให้คนดูและตอบในข้อที่ต้องใช้สายตา การชวนผู้เล่น B สำหรับข้อที่ต้องใช้สองคน และรายงานที่แนบกับ issue ได้ทันที

---

## What it does / การทำงาน

- **It judges nothing (ไม่ตัดสินผลเอง):** `aeterna_core` owns the registry, the run lock, the destructive gate and every result state. This package is the menu, the eye card, the player B invite and the report.
- **Menu (เมนู):** a `lg` `aeterna_uikit` panel with the kit versions, the destructive gate of the last run, player B status, progress, counts, one row per suite (`passed/total`, PASS · SKIP · MOCK count as passed), and the buttons Run all · Invite player B · Cancel run (your own run only) · Show report. Picking a suite opens its tests. While another run holds `aeterna_core`, the menu shows the phase and seconds of that run and never a name.
- **Eye card (การ์ดตรวจด้วยตา):** a small card in the lower left corner (360 px) with the question, "Normally you will see: …" and Pass · Doesn't match · Skip. It takes focus as an `aeterna_core` overlay, so an open phone or panel stays open and gets its focus back after the answer. ESC = Skip. Skip, ESC and no answer are GAP, never SKIP.
- **Player B (ผู้เล่น B):** type a server id in the invite panel the server opens; that player sees a confirm with no names on either side, and can leave the role at any time with the key mapping `+aeterna_testkit_leave` or by disconnecting. Without B, every two-player test is GAP `needs player B`.
- **Report (รายงาน):** JSON (`aeterna_testkit.report/1`, [schema](schema/report-1.schema.json)) and Markdown, printed to the server console and saved to `reports/latest.json` and `reports/latest.md` (each run overwrites both). The name to attach it under is `kit-<core version>-<runId>.md`.
- **Deliberate limits (ขอบเขตที่จำกัดไว้):** no run history beyond the last report, no upload, no scheduled runs, no single eye test from chat. It registers no self-tests of its own in 0.1.0.

## Install / การติดตั้ง

1. Download `aeterna_testkit-<version>.zip` from the [Releases](https://github.com/aeterna/nakara-oss/releases) page and verify it (see below). Keep the `reports/` folder: `SaveResourceFile` creates no folders.
2. Extract it into your `resources/` folder so you have `resources/aeterna_testkit/fxmanifest.lua`.
3. In `server.cfg`, start it after every package whose tests you want in the run, and give the menu ACE to admins:

   ```cfg
   ensure aeterna_core
   ensure aeterna_uikit
   ensure aeterna_testkit          # after every package whose tests you want in the run
   add_ace group.admin aeterna.testkit.run allow
   # optional, private test servers only (also needs: set sv_master1 "")
   set aeterna_core_allow_destructive true
   ```

Player B needs no ACE. / ผู้เล่น B ไม่ต้องมี ACE แค่กดยอมรับบนหน้าจอ

### Destructive gate / ด่านการทดสอบที่แก้ข้อมูลจริง

Tests that give a real player items or write a real player's stored data run only when `aeterna_core_allow_destructive` is `true` **and** the server is not listed publicly (`sv_master1` set to the empty string). `aeterna_core` reads both convars; this package never does and shows only `on`/`off` from the last run. Otherwise those tests are SKIP.

การทดสอบที่ให้ไอเทมหรือเขียนข้อมูลของผู้เล่นจริงจะรันเฉพาะเมื่อ `aeterna_core_allow_destructive` เป็น `true` และเซิร์ฟเวอร์ไม่ได้ลงรายชื่อสาธารณะ (`set sv_master1 ""`) เท่านั้น ไม่เช่นนั้นจะเป็น SKIP

## Config / การตั้งค่า

### `config.lua`

| Key | Default | Meaning / ความหมาย |
|---|---|---|
| `Config.inviteSeconds` | `30` | Seconds an invite to player B waits for an answer (`10–120`) / เวลารอคำตอบจากผู้เล่น B (วินาที) |
| `Config.menuEntry` | `true` | Adds an entry to the `aeterna_uikit` menu (ACE `aeterna.testkit.run`) besides the key mapping / เพิ่มรายการในเมนูของ `aeterna_uikit` |
| `Config.printReport` | `'md'` | What a menu run prints to the server console when it ends: `'md'` · `'json'` · `'none'` / สิ่งที่พิมพ์ลงคอนโซลเมื่อรันจากเมนูจบ |

Shared convars read through `aeterna_core`: `aeterna_locale` (`en` or `th`), `aeterna_theme`, `aeterna_theme_preset` (set with `setr`).

## Opening the menu / การเปิดเมนู

- Key mapping `+aeterna_testkit_menu` with **no default key**: Settings → Key Bindings → FiveM. When `Config.menuEntry` is true, it also opens from the `aeterna_uikit` menu.
- The server checks ACE `aeterna.testkit.run` before it opens the menu. A player without it sees only a small refusal panel.
- There is no chat command for players.

## Console command / คำสั่งคอนโซล

`aeterna_testkit_run [--json] [--only <name or prefix>]` — server console, txAdmin or rcon only (source 0). From a player it does nothing and logs one `warn` without the player's name. It prints one line per row as results arrive, then the Markdown report (or the JSON report as one line with `--json`), and saves both files. When another run is going it prints the busy line and exits. Console runs have no player, so `ped`, `eye` and two-player tests are GAP, and there are no player names to scrub (identifier, IP and path scrubbing still applies). The command is registered restricted, and the handler also refuses any source other than 0.

```text
aeterna_testkit_run
aeterna_testkit_run --json
aeterna_testkit_run --only aeterna_phonekit
```

## Report fields / ข้อมูลในรายงาน

| In | Source |
|---|---|
| Kit versions | `version` metadata of each started resource whose name starts with `aeterna_` |
| FXServer build | The build number only, parsed from the `version` convar; the rest of that string is dropped |
| Game build, resolution | Player A's client (`GetGameBuildNumber`, `GetActiveScreenResolution`); `null` for console runs |
| Run | run id, start time (UTC), duration, `by = console | menu`, player B yes/no, destructive gate `on`/`off`, cancelled |
| Rows | suite, name, kind, players, destructive, state, detail, ms, step, expected (at most 500; more sets `truncated`) |

**Never in it / ไม่มีในรายงาน:** player names, server ids, identifiers of any kind, IP addresses, convar values, file system paths, the server name or the host. Every `detail` and `expected` is scrubbed before it is stored, printed or saved: player A and B names (whole words, 3 characters or more) → `A` / `B`; `license:`, `license2:`, `steam:`, `fivem:`, `discord:`, `xbl:`, `live:`, `ip:` identifiers, and any other `<letters>:` followed by 15 or more digits → `[id]`; IPv4 (with port) and IPv6 → `[ip]`; absolute paths, also after `(`, `=` or `@` and in stack frames such as `@res/server/main.lua:12` → `[path]`; then cleaned to 300 characters.

## Exports / การเรียกใช้งาน

| Export | Side | Returns | Notes |
|---|---|---|---|
| `exports.aeterna_testkit:lastReport()` | server | table or nil | The last report as the JSON table (already scrubbed; unknown values are absent) |
| `exports.aeterna_testkit:isOpen()` | client | boolean | Whether the eye card is showing |

No export starts a run: runs start from the ACE-checked menu, the console command, or `exports.aeterna_core:startRun` directly.

## Commands and keys / คำสั่งและปุ่มลัด

- `aeterna_testkit_run` — console only (above).
- `+aeterna_testkit_menu` / `-aeterna_testkit_menu` — opens the menu; no default key.
- `+aeterna_testkit_leave` / `-aeterna_testkit_leave` — player B leaves the role; no default key.
- ESC on the eye card = Skip.

## Capabilities

What this resource is allowed to do to your server, from [`oss.json`](oss.json). Keep this table in sync with `oss.json`; widening a capability needs maintainer review.

| Capability | Declared |
|---|---|
| HTTP requests | none |
| `ExecuteCommand` | none |
| Registered commands | `aeterna_testkit_run`, `+aeterna_testkit_menu`, `-aeterna_testkit_menu`, `+aeterna_testkit_leave`, `-aeterna_testkit_leave` |
| Convars read | `version` |
| Convars written | none |
| Server net events (accepted from clients) | `aeterna_testkit:sv:open`, `aeterna_testkit:sv:inviteAnswer`, `aeterna_testkit:sv:leave`, `aeterna_testkit:sv:env` |
| Client net events (accepted from the server) | `aeterna_testkit:cl:invite`, `aeterna_testkit:cl:role`, `aeterna_testkit:cl:askEnv` |
| NUI | yes (the eye card) |
| Database tables | none (no DDL) |
| Files written | `reports/latest.json`, `reports/latest.md` |

## Verify before you install

Every release zip is built in CI and carries a build-provenance attestation. Check both the attestation and the checksum before you put it on your server:

```sh
gh attestation verify aeterna_testkit-<version>.zip --repo aeterna/nakara-oss --signer-workflow aeterna/nakara-oss/.github/workflows/release.yml
sha256sum -c SHA256SUMS --ignore-missing
```

Then read the capability table above (or `oss.json` inside the zip).

## Self-tests / การทดสอบตัวเอง

Registered with `aeterna_core` on start like every kit package, and run from this menu ([spec § Self-tests](../../docs/specs/aeterna_testkit.md#self-tests)).
ลงทะเบียนกับ `aeterna_core` ตอนเริ่ม resource และกดทดสอบได้จากเมนูนี้เอง

| Name | Kind | Players | Checks |
|---|---|---|---|
| `aeterna_testkit.scrub` | headless | 1 | A detail with a name, a `license:` id, an IPv4 and a `C:\` path comes out as `A`, `[id]`, `[ip]`, `[path]` |
| `aeterna_testkit.report_schema` | headless | 1 | A sample run builds JSON with exactly the keys of `schema/report-1.schema.json` (top level, `env`, `counts`, each row) and Markdown that ends with the footer |
| `aeterna_testkit.save` | headless | 1 | `SaveResourceFile` of `reports/latest.json` and `reports/latest.md` returns true and `LoadResourceFile` reads the same content back |
| `aeterna_testkit.env` | headless, `side = 'client'` | 1 | Player A's askEnv reply (game build and resolution) passes the schema the server checks `aeterna_testkit:sv:env` with |
| `aeterna_testkit.eye_card` | eye | 1 | The person sees the card in the lower left corner with a question and Pass, Doesn't match, Skip, over the menu panel that stays open |
| `aeterna_testkit.eye_card_b` | eye | 2 | Player B sees the same card, headed "as player B" |

`save` writes each report file back with the content it already holds, so a test run never loses or replaces the last report; before the first finished run it is SKIP `no report yet` and writes nothing. It writes only this resource's own report files, so it is not destructive.

## Tests

From the repository root:

```sh
busted --config-file=.busted packages/testkit/spec
```

## License

MIT. See [LICENSE](../../LICENSE). The bundled IBM Plex Sans Thai font is under the SIL Open Font License 1.1; see [NOTICE](NOTICE).
