# aeterna_testkit

- Package: `packages/testkit` · resource `aeterna_testkit` · wave W1 (Starter Kit 0.2) · status specified, 0.1.0
- Depends on: `aeterna_core` (0.2 self-test registry and runner), `aeterna_uikit` (menu panel, invite prompt)
  ([ADR 0005](../adr/0005-starter-kit-0-2.md) decisions 2 and 7)
- Used by: nobody. Packages register their tests with `aeterna_core`, never with this package

## Purpose and limits

One button that tests a whole Starter Kit install. The menu reads every self-test registered with `aeterna_core`,
starts a run, shows progress per suite, walks the presser through each test that needs a person's eyes, can bring in a
second player for two-player tests, and writes a report (JSON and Markdown) that can be attached to an issue as it is.

`aeterna_testkit` runs no test itself and judges nothing: `aeterna_core` owns the registry, the run lock, the
destructive gate and every result state ([aeterna_core § 0.2 additions](aeterna_core.md#02-additions)). This package
is the person-facing layer: menu, eye card, player B invite, report.

Not in 0.1.0: saved run history beyond the last report, uploading a report anywhere, scheduled runs, running a single
eye test on its own from chat.

## Install

```cfg
ensure aeterna_core
ensure aeterna_uikit
ensure aeterna_testkit          # after every package whose tests you want in the run
add_ace group.admin aeterna.testkit.run allow
# optional, private test servers only (also needs: set sv_master1 "")
set aeterna_core_allow_destructive true
```

Player B needs no ACE; B accepts an invite on screen.

## Configuration

| Convar | Default | Meaning |
| --- | --- | --- |
| `aeterna_core_allow_destructive` | `false` | Read by `aeterna_core`, not by this package (see core § Configuration (0.2)). The menu only shows whether the gate is open |

`config.lua`:

| Key | Default | Meaning |
| --- | --- | --- |
| `Config.inviteSeconds` | `30` | How long an invite to player B waits for an answer (10–120) |
| `Config.menuEntry` | `true` | Adds an entry to the `aeterna_uikit` menu (ACE `aeterna.testkit.run`) besides the key mapping |
| `Config.printReport` | `'md'` | What a menu run prints to the server console when it ends: `'md'` · `'json'` · `'none'` |

## Opening the menu

- Key mapping `+aeterna_testkit_menu` with default key `F9` (ADR 0004 decision 10 amended 2026-11-22): Settings → Key Bindings → FiveM.
  When `Config.menuEntry` is true, the same menu also opens from the `aeterna_uikit` menu.
- The client sends `aeterna_testkit:sv:open`; the server checks ACE `aeterna.testkit.run` and only then opens the menu
  panel with `exports.aeterna_uikit:open`. A player without the ACE gets a small uikit panel (`sm`) with the line
  `testkit.denied` and a close button, and nothing else.
- There is no chat command for players. The console command (below) accepts only source 0.

## The menu (a uikit panel, size `lg`)

| Block id | Type | Content |
| --- | --- | --- |
| `head` | text | Kit versions line (`aeterna_core 0.2.0 · aeterna_uikit 0.2.0 · …`), destructive gate `on`/`off`, player B status |
| `progress` | progress | `done / total` of the current run; hidden (value 0, label `testkit.idle`) when idle |
| `counts` | text | `PASS n · FAIL n · SKIP n · GAP n · MOCK n · MISSING n` |
| `suites` | list | One item per suite (owner resource without `aeterna_`): label = suite, meta = `passed/total` or the worst state, icon by state. ≤ 50 items |
| `busy` | text | When `aeterna_core` is busy with another run: `testkit.busy` with the phase and seconds, never a name |
| `act` | buttons | `run` "Run all" (primary) · `invite` "Invite player B" · `cancel` "Cancel run" (danger, only while this menu's run is going) · `report` "Show report" (after a run) |

`passed/total` counts PASS, SKIP and MOCK as passed and every row as total. Picking a suite opens a second panel
(`md`) listing its tests (≤ 50) with state and detail; a FAIL row also shows `step` and `expected` when the test sent
them. The panel updates through `exports.aeterna_uikit:update` on every `aeterna_core:runProgress` event, at most 4
times a second.

**Run all** calls `exports.aeterna_core:startRun({ by = src, b = <accepted B or nil> })`. If core answers `nil, busy`,
the panel shows the busy line and nothing starts. A run started from the menu belongs to that presser: only they (or
the console) can cancel it, and only they get the eye cards for role A.

## Now-testing strip

While a client test other than `eye` runs on this client, testkit's client listens to the client-local `aeterna_core:selftest` event
and, when `ctx.kind ~= 'eye'` and `ctx.expect` is set, shows a one-line strip in the same lower-left spot as the eye
card: the test name and `ctx.expect` after `testkit.now_doing` ("Do this now:"). It hides on the client-local
`aeterna_core:selftestEnd` for that test. A test without `expect` shows nothing. The strip never takes focus or
the cursor, so the presser can play while reading it.

## Eye-check card

When `aeterna_core` fires the client-local event `aeterna_core:eyeAsk` → `(runId, name, { ask, expect, role })`,
testkit shows its own small NUI card in the lower left corner, 360 px wide, so the thing being checked stays visible.
It asks `aeterna_core` for focus in **overlay** mode (`{ overlay = true, cursor = true, keyboard = true }`,
[aeterna_core § Focus overlay](aeterna_core.md#focus-overlay)): the screen under test (an open phone, a panel) is paused,
not closed, and gets its focus back when the card releases after the answer.

```
 ┌──────────────────────────────────────────────┐
 │ Look 4 · phonekit                             │
 │ <ask>                                         │
 │ Normally you will see: <expect>               │
 │ [ Pass ]  [ Doesn't match ]  [ Skip ]         │
 └──────────────────────────────────────────────┘
```

- The header is `Look <n> · <suite>` (locale `testkit.eye.header`; `testkit.eye.role_b` adds `· as player B`). `n` is
  the count of cards this player has been shown in the current run, starting at 1. There is **no total** ("of 6"):
  `aeterna_core:eyeAsk` carries only `{ ask, expect, role }`, so the card cannot know how many looks are left. `suite`
  is the test name's part before the first `.`, without `aeterna_`.
- `ask` and `expect` come from the registering resource, already translated, and are rendered with `textContent`.
- Pass → `exports.aeterna_core:answerEye(runId, name, 'pass')`; Doesn't match → `'mismatch'`; Skip → `'skip'`.
  ESC = Skip. Core decides the state: Pass → PASS, Doesn't match → FAIL, Skip → GAP, and GAP after 120 s with no answer.
- The card closes on the answer, on `aeterna_core:selftestEnd` for that test, and on `aeterna_core:focusLost` for its
  own token (counted as no answer; core turns it into GAP after 120 s). Every exit releases the overlay token.
- Skip, ESC and no answer are never SKIP: a check a person did not confirm is GAP.
- Player B gets the same card for tests with `role = 'B'`, with the header `testkit.eye.role_b`.

## Two-player A/B flow

1. The presser (A) presses **Invite player B**. The server opens a small uikit panel (`sm`, block `target`: a number
   field for a server id, 1–65535, and a **Send** button). The id does not travel in a client event of this package:
   it comes back through uikit's own `aeterna_uikit:action` with `values.target`, which the server re-checks (ACE
   `aeterna.testkit.run`, rate limit 3 / 10000 ms) before it validates the id. There is no `aeterna_testkit:sv:invite`
   net event and no client input prompt. After Send (or Back) the menu opens again, with `testkit.invite.invalid` on the
   head line when the invite was refused.
2. The server checks: A has the ACE, the id is online, it is not A, no other invite or run is pending for either, and
   the rate limit. Otherwise A sees `testkit.invite.invalid`.
3. B gets `exports.aeterna_uikit:confirm` with `testkit.invite.body` ("Player A asks you to help test the server as
   player B. You will see a few checks and answer them."). No name is shown on either side: A sees "player B (id n)",
   B sees "player A".
4. B accepts within `Config.inviteSeconds` → the menu's `head` shows `B: ready`. Declined or no answer →
   `testkit.invite.declined`. B can leave the role at any time with the key mapping `+aeterna_testkit_leave` (no
   default key) or by disconnecting; tests in flight become GAP `player left` in core.
5. Run all passes `b` to `startRun`. B is released when the run ends.

Without B, every `players = 2` test is GAP `needs player B`; the run can still be green.

## Report

Built on the server from the rows of `aeterna_core:runProgress` and the summary of `aeterna_core:runDone`, plus an
environment block. Written to the console (Markdown or JSON) and saved with `SaveResourceFile` to two fixed paths in
this resource:

- `reports/latest.json`
- `reports/latest.md`

Each run overwrites both files (the scanner accepts only literal paths, so there is no per-run file name).
`SaveResourceFile` creates no folders, so the package ships `reports/README.md` (one line: "aeterna_testkit writes its
last test report here.") to keep the folder in place; the release zip must include it. The
Markdown file name shown to the presser is the suggested attachment name `kit-<core version>-<runId>.md`.

### What is in it, and what never is

| In | Source |
| --- | --- |
| Kit versions | `GetResourceMetadata(res, 'version', 0)` of each started resource whose name starts with `aeterna_` |
| FXServer build | The build number only (digits after `v1.0.0.`) parsed from the server's `version` convar; the rest of that string is dropped |
| Game build | `GetGameBuildNumber()` on player A's client, sent with `aeterna_testkit:sv:env`; `null` for console runs |
| Resolution | `GetActiveScreenResolution()` on player A's client as `<w>x<h>`; `null` for console runs |
| Run | run id, started (UTC ISO 8601), duration, `by = 'console' | 'menu'`, player B `true`/`false`, destructive gate `on`/`off`, cancelled |
| Rows | suite, name, kind, players, destructive, state, detail, ms, step, expected |

Never in it: player names, server ids, identifiers of any kind (every `<prefix>:<value>` form that
`GetPlayerIdentifiers` returns, such as `license`, `license2`, `steam`, `fivem`, `xbl`, `live`, `ip`), IP addresses, convar values (the gate is reported as `on`/`off`, never the convars behind it), file system paths, the
server name or the host.

Every `detail` and `expected` string is scrubbed before it is stored, printed or saved:

1. Occurrences of the current player A and B names → `A` / `B`, longest name first. Names shorter than 3 characters are
   skipped. An occurrence counts only when the byte before and after it is not an ASCII letter, digit or `_`. **Limit:**
   that test looks at ASCII only, so a Thai (or other non-ASCII) name is also replaced inside a longer word, because Thai
   is written without spaces; the match is weaker there than for a Latin-letter name, and an ordinary word that contains
   the name is also cut to `A` or `B`. It errs toward hiding.
2. `<prefix>:<value>` identifiers → `[id]`. The prefixes are a fixed list in `shared/logic/scrub.lua` covering every
   identifier type FXServer documents for `GetPlayerIdentifiers` (`license2`, `license`, `steam`, `fivem`, `discord`,
   `xbl`, `live`, `ip`) plus the kit's own character and license keys (`cid`, `lic`); a `<letters>:` followed by 15 or more digits is also `[id]`, which catches a Discord-style
   id under a prefix not in the list. Other `word:value` text is left alone.
3. IPv4 (`n.n.n.n`, optional `:port`) and IPv6 forms → `[ip]`.
4. Absolute paths (`X:\…`, `\\…`, and `/…` with two or more segments) → `[path]`.
5. Then `AeternaCore.text.clean` with max 300.

A test that needs a value to explain a failure reports what it expected and what it saw in game terms (`screen is
home`), not data about people or machines.

### JSON schema (`aeterna_testkit.report/1`)

```json
{
  "schema": "aeterna_testkit.report/1",
  "runId": "r1k-4f2a",
  "startedAt": "2026-11-21T14:02:11Z",
  "ms": 184230,
  "by": "menu",
  "playerB": true,
  "destructive": "off",
  "cancelled": false,
  "env": { "fxserver": "13068", "gameBuild": 3788, "resolution": "1920x1080" },
  "kit": { "aeterna_core": "0.2.0", "aeterna_uikit": "0.2.0", "aeterna_testkit": "0.1.0" },
  "counts": { "PASS": 41, "FAIL": 1, "SKIP": 2, "GAP": 3, "MOCK": 4, "MISSING": 0 },
  "ok": false,
  "rows": [
    { "suite": "phonekit", "name": "aeterna_phonekit.fold_keeps_screen", "kind": "ped", "players": 1,
      "destructive": false, "state": "FAIL", "detail": "step 3: screen is home", "ms": 2140,
      "step": 3, "expected": "contacts.detail" }
  ]
}
```

`rows` ≤ 500; past that the report keeps the first 500 and sets `"truncated": true`. Keys are fixed; a consumer can
reject unknown keys.

### Markdown layout

```markdown
# Starter Kit test report · r1k-4f2a
FXServer 13068 · game build 3788 · 1920x1080 · by menu · player B yes · destructive off
**FAIL** · PASS 41 · FAIL 1 · SKIP 2 · GAP 3 · MOCK 4 · MISSING 0 · 184 s

| Suite | Passed | Worst |
| --- | --- | --- |
| core | 5/5 | PASS |

## FAIL and MISSING
- phonekit.fold_keeps_screen (ped) · step 3 · expected contacts.detail · step 3: screen is home

## Left for a person (GAP)
- phonecall.call_ab · needs player B

## SKIP
- hudkit.voice_indicator · needs pma-voice

## Versions
aeterna_core 0.2.0 · aeterna_uikit 0.2.0 · aeterna_testkit 0.1.0
```

Test names drop the `aeterna_` prefix in Markdown only. The last line is always `testkit.report.footer` ("No player
names, identifiers, IPs, convar values or paths.").

## Console command

`aeterna_testkit_run [--json] [--only <name or prefix>]` — **source 0 only** (server console, txAdmin, rcon); from a
player it prints nothing to them and logs one `warn` without the player's name. It calls `startRun({ by = 0 })`, prints
one line per row as results arrive, then the Markdown report (or the JSON report with `--json`, one line, so log
tools can pick it up), and saves both files. Busy → prints `testkit.busy` and exits. Console runs have no player, so
`ped`, `eye` and two-player tests are GAP.

## Exports

| Export | Side | Returns | Notes |
| --- | --- | --- | --- |
| `lastReport()` | server | table or nil | The last report as the JSON table above (already scrubbed) |
| `isOpen()` | client | boolean | Whether the menu or an eye card is showing (other resources can avoid opening over it) |

No export starts a run: runs start from the ACE-checked menu, the console command, or `aeterna_core:startRun` directly.

## Events

| Event | Direction | Schema | Rate limit |
| --- | --- | --- | --- |
| `aeterna_testkit:sv:open` | client → server | none | 2 / 1000 ms |
| `aeterna_testkit:sv:inviteAnswer` | client → server | `{ accept: boolean }` | 3 / 10000 ms |
| `aeterna_testkit:sv:leave` | client → server | none | 2 / 5000 ms |
| `aeterna_testkit:sv:env` | client → server | `{ gameBuild: integer 1–99999, w: integer 320–15360, h: integer 240–8640 }` | 2 / 10000 ms |
| `aeterna_testkit:cl:invite` | server → client | `{ seconds: integer }` | — |
| `aeterna_testkit:cl:role` | server → client | `{ role: enum A/B/none }` | — |
| `aeterna_testkit:cl:askEnv` | server → client | none | — |

Every server handler calls `AeternaCore.rateLimit` first, then validates, then checks state: `open` needs
ACE `aeterna.testkit.run`; the invite is sent from the server panel and re-checks the ACE and a 3 / 10000 ms limit; `inviteAnswer` is accepted only from the invited player while the invite is open; `env`
only from player A of the current run, once per run. Menu buttons arrive through uikit's own
`aeterna_uikit:action` (server-local, filtered on `owner == 'aeterna_testkit'`) and are ACE-checked again.

Listened to (not net events): `aeterna_core:runProgress`, `aeterna_core:runDone` (server-local);
`aeterna_core:eyeAsk`, `aeterna_core:selftestEnd`, `aeterna_core:focusLost` (client-local);
`aeterna_core:hello` is not needed: testkit has a hard edge to core and restarts with it.
`aeterna_uikit:action`, `aeterna_uikit:menu` (server-local).

## NUI messages

The eye card is the only page of this package (`ui_page 'html/index.html'`).

Lua → NUI: `aeterna:theme` (with `preset`), `locale`, `eye:show {header, ask, expect, index, role}`,
`eye:hide`. NUI → Lua callbacks: `eyeAnswer {answer: enum pass/mismatch/skip}`, `escape {}`, both validated before use.

## Commands and keys

`aeterna_testkit_run` (console only), `+aeterna_testkit_menu` / `-aeterna_testkit_menu`, `+aeterna_testkit_leave` /
`-aeterna_testkit_leave` (each pair registered with literal names in the client) — `+aeterna_testkit_menu` defaults to `F9`, `+aeterna_testkit_leave` has no default key. These names
are permanent once released.

## Storage

No KVP and no database. Files: `reports/latest.json` and `reports/latest.md` in this resource, overwritten by each run;
`reports/README.md` ships with the package so the folder exists.

## Locale keys

`testkit.key.menu`, `testkit.key.leave`, `testkit.menu.title`, `testkit.menu.run`, `testkit.menu.invite`,
`testkit.menu.cancel`, `testkit.menu.report`, `testkit.idle`, `testkit.busy`, `testkit.denied`, `testkit.gate.on`,
`testkit.gate.off`, `testkit.b.none`, `testkit.b.ready`, `testkit.invite.prompt`, `testkit.invite.body`,
`testkit.invite.invalid`, `testkit.invite.declined`, `testkit.eye.header`, `testkit.eye.role_b`,
`testkit.eye.normally`, `testkit.eye.pass`, `testkit.eye.mismatch`, `testkit.eye.skip`, `testkit.report.saved`,
`testkit.report.footer`.

## `oss.json` capabilities

```json
{ "http": [], "commands": [], "registeredCommands": ["aeterna_testkit_run", "+aeterna_testkit_menu",
                                                    "-aeterna_testkit_menu", "+aeterna_testkit_leave",
                                                    "-aeterna_testkit_leave"],
  "convars": { "read": ["version"], "write": [] },
  "netEvents": { "server": ["aeterna_testkit:sv:open", "aeterna_testkit:sv:inviteAnswer",
                            "aeterna_testkit:sv:leave", "aeterna_testkit:sv:env"],
                 "client": ["aeterna_testkit:cl:invite", "aeterna_testkit:cl:role", "aeterna_testkit:cl:askEnv"] },
  "nui": true, "db": { "tables": [], "ddl": false },
  "files": { "write": ["reports/latest.json", "reports/latest.md"] } }
```

## Self-tests

Registered with `aeterna_core` like every package.

| Name | Kind | Players | Destructive | Expect | Skip-when |
| --- | --- | --- | --- | --- | --- |
| `aeterna_testkit.scrub` | headless | 1 | n | — (a detail with a name, a `license:` id, an IPv4, a `C:\` path comes out as `A`, `[id]`, `[ip]`, `[path]`) | — |
| `aeterna_testkit.report_schema` | headless | 1 | n | — (a sample run builds JSON with exactly the schema keys and Markdown with the footer) | — |
| `aeterna_testkit.save` | headless | 1 | n | — (`SaveResourceFile` of both report paths returns true and `LoadResourceFile` reads them back) | — |
| `aeterna_testkit.env` | headless (`side = 'client'`) | 1 | n | — (A's client answers `askEnv` with a game build and a resolution in range) | — |
| `aeterna_testkit.eye_card` | eye | 1 | n | A card in the lower left corner with a question and three buttons: Pass, Doesn't match, Skip. A uikit panel opened behind it stays open | — |
| `aeterna_testkit.eye_card_b` | eye | 2 | n | Player B sees the same card, headed "as player B" | — |

`save` writes only this resource's own report files, which is not player or world state, so it is not destructive.

## Tests

busted (pure modules `shared/logic/report.lua`, `shared/logic/scrub.lua`, `shared/logic/menu.lua`; no natives):

1. Scrub: `'player Somchai lost license:abc123 at 10.0.0.5:30120 C:\\srv\\x.lua'` with A = `Somchai` →
   `'player A lost [id] at [ip] [path]'`; `/home/u/a` → `[path]`; `steam:1100001…`, `license2:…`, `fivem:…`, `ip:…` →
   `[id]`; `::1` and `fe80::1` → `[ip]`; a plain `step 3: screen is home` is unchanged.
2. Report JSON has exactly the schema keys, `ok` = no FAIL and no MISSING, counts match the rows, `rows` past 500 are
   cut with `truncated = true`.
3. Markdown: header line, counts line, one table row per suite, sections only when non-empty, names without
   `aeterna_`, footer always last.
4. FXServer build parse: `FXServer-master SERVER v1.0.0.13068 win32` → `13068`; a string with no build → `null`; the
   rest of the string never appears in the report.
5. Suite rows: `passed/total` counts PASS, SKIP, MOCK; worst state order FAIL, MISSING, GAP, SKIP, MOCK, PASS.
6. Invite rules: inviting yourself, an offline id, an id already in a pending invite, or a second invite while one is
   open is refused; an answer from someone other than the invited player is dropped; expiry after
   `Config.inviteSeconds` (fake clock).
7. Menu progress updates are throttled to 4 per second; the last update after `runDone` is never dropped.
8. Console guard: the command handler with `source ~= 0` starts nothing; `--json` prints one line.
9. Eye card state (pure): it requests focus with `overlay = true`; answer, `selftestEnd` and `focusLost` each close it
   and release the overlay token exactly once; ESC sends `'skip'`.

Smoke (clean qbx server, two clients):

1. Without the ACE, the key mapping opens only the refusal panel; with it, the menu lists every started kit package as a suite.
2. Run all with no B: headless rows fill in, the presser gets each eye card in turn, two-player rows end as GAP
   `needs player B`, the report prints and both files exist under `reports/`.
3. Open the phone, then reach an eye test that checks it: the card sits over the phone, the phone stays open, and after
   the answer the phone has focus again.
4. Invite B by server id, B accepts; a two-player eye test shows the card to both; B disconnects mid-test → GAP
   `player left`.
5. A second admin presses Run all during a run: the menu shows the busy line with phase and seconds, no name.
6. `aeterna_testkit_run --json` from the server console prints one JSON line; the same command typed in F8 does
   nothing.
7. Read both report files in full: no player name, server id, identifier, IP, convar value or path appears.
8. Screenshots of the menu and the eye card in all three presets for the owner's visual gate.

## Done when

All busted cases pass in `npm run test:lua`, `fivem-devkit safety` reports 0 errors and 0 over-declared items, the smoke
steps pass on the test server with every 0.2 kit package installed, the owner has passed the screenshots, and the
README (TH and EN) documents the ACE, the destructive gate, the report fields and the console command.
