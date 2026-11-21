# aeterna_core

- Package: `packages/core` · resource `aeterna_core` · wave W1 · status released in 0.1.0 · 0.2.0 specified below
  ([0.2 additions](#02-additions), [ADR 0005](../adr/0005-starter-kit-0-2.md) decisions 7 and 9)
- Depends on: nothing (`ox_lib` optional, never required)
- Used by: every other `aeterna_*` package ([ADR 0004](../adr/0004-aeterna-starter-kit.md) decision 2)

## Purpose and limits

The small shared base of the Starter Kit: logging, a local event bus, Thai-aware text helpers, locale lookup, time in
the server's timezone, payload validation, a rate limit, ACE checks, versioned client storage, key mappings with no
default key, the NUI focus lock, the theme path, and a self-test runner.

It has no UI, no database, no HTTP and no game logic. It never reads framework data (jobs, money, items).

## Install

```cfg
ensure aeterna_core        # before every other aeterna_* resource
```

Other packages load the Lua half with `shared_script '@aeterna_core/import.lua'`, which defines the global table
`AeternaCore` inside that resource. The focus lock, self-test registry and theme path live in the `aeterna_core`
resource itself and are reached through exports.

## Configuration

| Convar | Default | Meaning |
| --- | --- | --- |
| `aeterna_locale` | `en` | Language for every kit package (`th` or `en`) |
| `aeterna_timezone` | `+00:00` | Offset used by `AeternaCore.time`, format `±HH:MM` |
| `aeterna_theme` | empty | `nui://<resource>/<path>.css` of the owner's theme; empty = the package's own `theme.css` |
| `aeterna_core_log_level` | `info` | `debug` · `info` · `warn` · `error` |

Convars are read with `GetConvar`; a value that does not parse falls back to the default and logs one `warn`.
Set `aeterna_locale`, `aeterna_timezone` and `aeterna_theme` with `setr` so clients see them, for example
`setr aeterna_locale th`.

## API — `AeternaCore` (from `import.lua`, both sides)

### Logging

| Call | Returns | Notes |
| --- | --- | --- |
| `log.debug/info/warn/error(msg, fields?)` | nil | Prints `[aeterna_<res>] LEVEL msg key=value …`. `fields` is a flat table; values are stringified and cut to 200 chars. Below `aeterna_core_log_level` = no output. |

### Event bus (local to one side of one resource set)

| Call | Returns | Notes |
| --- | --- | --- |
| `on(name, fn)` | handle | Wraps `AddEventHandler` on `aeterna_core:bus:<name>`. |
| `off(handle)` | nil | |
| `emit(name, ...)` | nil | `TriggerEvent('aeterna_core:bus:' .. name, ...)`. Never crosses the network. |

### Text

| Call | Returns | Notes |
| --- | --- | --- |
| `text.len(s)` | integer | Visible characters: Thai combining marks (U+0E31, U+0E34–U+0E3A, U+0E47–U+0E4E) count as 0. |
| `text.cut(s, n)` | string | At most `n` visible characters; never splits a UTF-8 sequence or leaves a lone combining mark. |
| `text.clean(s, maxLen)` | string | Removes control characters (U+0000–U+001F, U+007F, U+200B–U+200F, U+202A–U+202E), trims, then `cut`. |

### Locale

| Call | Returns | Notes |
| --- | --- | --- |
| `t(key, vars?)` | string | Looks up `key` in the calling resource's `Locales[lang]`, then `Locales.en`, then returns `key`. `{name}` in the string is replaced by `vars.name` (stringified). |
| `lang()` | `'th'`/`'en'` | Current `aeterna_locale`. |

### Time

| Call | Returns | Notes |
| --- | --- | --- |
| `time.now()` | integer | Unix seconds (UTC) |
| `time.parts(ts?)` | table | `{year, month, day, hour, min, sec, wday}` in `aeterna_timezone`; `wday` 1 = Sunday … 7 = Saturday |
| `time.format(ts, pattern)` | string | Tokens `YYYY MM DD HH mm ss`; month and weekday names come from locale keys `core.month.1…12`, `core.wday.1…7` |

### Validation

`AeternaCore.validate(value, schema) -> ok:boolean, err:string|nil, clean:any`. On success `clean` is a copy with every
string passed through `text.clean` and `maxLen`; callers use `clean`, never the raw value. Schemas are plain tables:

```lua
{ type = 'table', fields = {
    id     = { type = 'string', maxLen = 32, pattern = '^[%w_%-]+$' },
    amount = { type = 'number', integer = true, min = 1, max = 1000 },
    mode   = { type = 'string', enum = { 'a', 'b' } },
    note   = { type = 'string', maxLen = 120, optional = true },
}, extra = false }
```

- Types: `string` · `number` · `boolean` · `table` (with `fields`) · `array` (with `items`, `maxItems`).
- `extra = false` (the default) rejects keys not in `fields`. `pattern` is a Lua pattern applied after `text.clean`.
- `err` names the path and the rule, for example `amount: max 1000`. Pure Lua, no natives.

### Rate limit (server)

`AeternaCore.rateLimit(src, key, max, windowMs) -> boolean`: a sliding window per `(src, key)`. Returns `false` when
more than `max` calls arrived in the last `windowMs`; the caller drops the event. Buckets are freed on `playerDropped`.
`fivem-devkit safety` already counts it: its default list holds `rateLimit`, and a call path ending in `.rateLimit`
matches (`packages/devkit/src/safety/rules/util.js` `fnMatches`).

### ACE (server)

`AeternaCore.can(src, action) -> boolean` = `IsPlayerAceAllowed(src, action)` with `action` required to start with
`aeterna.`. Console (`src == 0`) is always allowed.

### Client storage (client)

| Call | Returns | Notes |
| --- | --- | --- |
| `kvp.get(name, version, default)` | any | Reads `aeterna_<pkg>:<name>:v<version>` as JSON; bad JSON = `default` and one `warn`. `<pkg>` is the calling resource without `aeterna_`. |
| `kvp.set(name, version, value)` | nil | JSON-encodes; refuses values over 16 KB. |
| `kvp.migrate(name, from, to, fn)` | nil | If `v<from>` exists and `v<to>` does not: `set(to, fn(old))`, then delete `v<from>`. |

### Keys (client)

`AeternaCore.key(command, description)` calls `RegisterKeyMapping(command, t(description), 'keyboard', '')`. The empty
default means no key until the player binds one in Settings → Key Bindings → FiveM. The caller registers the command
pair itself with literal names, because the scanner counts only literal `RegisterCommand` names:

```lua
RegisterCommand('+aeterna_uikit_menu', function() showMenu() end, false)
RegisterCommand('-aeterna_uikit_menu', function() end, false)
AeternaCore.key('+aeterna_uikit_menu', 'uikit.key.menu')
```

`command` must start with `+aeterna_`.

## Exports of the `aeterna_core` resource

### Focus

Client exports. One owner holds NUI focus at a time; the last request wins.

| Export | Returns | Notes |
| --- | --- | --- |
| `requestFocus(opts)` | token (string) | The owner is `GetInvokingResource()`, never a name the caller passes. `opts = { cursor = true, keyboard = true, keepGameInput = false }`. Decides ownership only; see the helpers below. |
| `releaseFocus(token)` | boolean | Only the current token releases; a stale token returns `false` and changes nothing. Focus is cleared when nobody holds it. |
| `focusOwner()` | string or nil | |

Local client event `aeterna_core:focusLost` → `(owner, token, reason)` with reason `preempted` · `owner_stopped` (the
owner's resource stopped) · `released_by_core` (`aeterna_core` restarted). Each package closes its own panel when it
receives it for its own token.

`SetNuiFocus` acts on the NUI frame of the resource that calls it, and `aeterna_core` has no page, so core never calls
it: the exports only decide who owns focus. Packages use the helpers from `import.lua`, which run in their own resource:

| Helper (client) | Does |
| --- | --- |
| `AeternaCore.requestFocus(opts)` | Calls the `requestFocus` export, then `SetNuiFocus(keyboard, cursor)` and `SetNuiFocusKeepInput(keepGameInput)`. Returns the token or nil |
| `AeternaCore.releaseFocus(token)` | Calls the `releaseFocus` export; when it returns true, clears both natives |

`import.lua` also clears both natives when `aeterna_core:focusLost` names the current resource as owner.

### Theme

Client export `themeHref() -> string|nil`: the `aeterna_theme` value when it starts with `nui://` and ends with
`.css`, else nil. Each package sends `{ type = 'aeterna:theme', href = … }` to its own NUI, which adds a `<link>` after
its `theme.css`. (Spike S2 confirms that a stylesheet from another resource loads; if it does not, this export stays
and the theming guide tells owners to copy their file into each package instead.)

### Self-tests

| Export (server) | Notes |
| --- | --- |
| `addSelftest(name)` | Registers a test named `<resource>.<name>`. When tests run, `aeterna_core` fires the server-local event `aeterna_core:selftest` → `(runId, '<resource>.<name>')`; the owner answers with export `reportSelftest(runId, name, ok, detail)` within 5 s or the test counts as failed (no function crosses resources). |
| `runSelftests() -> results` | `{ {name, ok, detail, ms}, … }` |

Command `aeterna_core_selftest` (server console, or players with ACE `aeterna.core.selftest`) runs them and prints one
line per test plus a total.

## Events

None over the network. `aeterna_core:focusLost` (client) and `aeterna_core:selftest` (server) are local.

## NUI messages

None. `aeterna_core` has no `ui_page`, but it calls `SetNuiFocus` for the focus lock, which the scanner counts as NUI
use, so `oss.json` declares `"nui": true`.

## Storage

Only the helpers above; `aeterna_core` itself stores nothing.

## Locale keys

`core.month.1`…`core.month.12`, `core.wday.1`…`core.wday.7`, `core.selftest.pass`, `core.selftest.fail`,
`core.selftest.total`.

## `oss.json` capabilities

```json
{ "http": [], "commands": [], "registeredCommands": ["aeterna_core_selftest"],
  "convars": { "read": ["aeterna_locale", "aeterna_timezone", "aeterna_theme", "aeterna_core_log_level"], "write": [] },
  "netEvents": { "server": [], "client": [] }, "nui": true,
  "db": { "tables": [], "ddl": false }, "files": { "write": [] } }
```

## Tests

busted (pure modules under `shared/logic/`):

1. `text.len('สวัสดี')` = 4; `text.len('ก้')` = 1; `text.len('abc')` = 3.
2. `text.cut('สวัสดีครับ', 3)` = `'สวัส'` (the mark on ว counts 0); `text.cut('ดี', 1)` = `'ดี'`, keeping the mark
   with its base; never breaks a UTF-8 sequence.
3. `text.clean` removes U+200B and newlines, trims, and respects `maxLen`.
4. `validate` passes a good payload; fails with `amount: max 1000`, `id: pattern`, `extra: not allowed`, `note: type`
   on the matching bad payloads; arrays over `maxItems` fail.
5. Rate limit: 5 calls allowed with `max = 5` in a window, the 6th returns false, a call after the window passes.
6. `time.parts` with `+07:00` turns `1700000000` into `2023-11-15 05:13:20`; with `-03:30` the day changes where it
   should.
7. `t()` falls back `th` → `en` → key; `{name}` replaced; missing var leaves `{name}`.
8. Focus logic (pure state machine): request A → owner A; request B → A gets `preempted`, owner B; release with A's
   token returns false; release with B's token clears focus; owner stop clears and notifies.
9. `kvp.migrate` converts once and deletes the old key (fake KVP store).

Smoke (clean qbx server):

1. `ensure aeterna_core` starts with no warning; `aeterna_core_selftest` prints all pass.
2. Set `setr aeterna_timezone "+07:00"` and restart: `time.format(time.now(), 'HH:mm')` matches the local clock.
3. Two test resources request focus in turn: the cursor follows the newest owner, ESC in the first does nothing after
   it lost focus.

## Done when

All busted cases pass in `npm run test:lua`, `fivem-devkit safety` reports 0 errors and 0 over-declared items, the
smoke steps pass on the test server, and the README documents every convar, export and the focus rules.

---

## 0.2 additions

Everything above stays valid for 0.2.0. This part adds to it: richer self-tests (kinds, players, destructive flag,
per-test timeout, skip conditions, six result states), a client-side protocol so tests that need a ped or a person's
eyes run on the presser's client, a run lock, a destructive-test gate, and the theme preset loader
([ADR 0005](../adr/0005-starter-kit-0-2.md) decisions 7 and 9). One change to a 0.1 behaviour is marked
**Changed in 0.2** with its reason and upgrade note.

`aeterna_core` holds the registry, runs the tests and judges every result. `aeterna_testkit` is only a menu and a
report on top of these exports ([aeterna_testkit](aeterna_testkit.md)); no package depends on it.

### Configuration (0.2)

| Convar | Side | Default | Meaning |
| --- | --- | --- | --- |
| `aeterna_theme_preset` | client (`setr`) | `asphalt` | `asphalt` · `paper` · `night-market`. Any other value = `asphalt` and one `warn` |
| `aeterna_core_allow_destructive` | server (`set`) | `false` | `true` lets destructive tests run, only when the server is not listed publicly (below) |
| `sv_master1` | server | (FXServer's) | Read only to decide whether the server is listed publicly. Its value is never logged, printed or reported |

The gate belongs to `aeterna_core` because tests run there, so a console run and a menu run obey the same rule.

**Listed publicly** means: `GetConvar('sv_master1', '<unset>')` returns anything other than the empty string. An unset
`sv_master1` returns the sentinel and counts as listed, because FXServer then uses its default master list. Only an
explicit `set sv_master1 ""` counts as private.

### Self-test fields

`addSelftest(name, meta?)`. A 0.1 call with only `name` is still valid and gets the defaults below.

| Field | Type | Default | Rule |
| --- | --- | --- | --- |
| `kind` | `'headless'` · `'ped'` · `'eye'` · `'mock'` | `'headless'` | `headless` checks with no person and no spawned character; `ped` needs a spawned character and runs on a client; `eye` runs on a client and a person answers; `mock` changes state with made-up data and must put it back |
| `side` | `'server'` · `'client'` | `'server'` | `headless` and `mock` only. `'client'` runs the test on the presser's client through the client-side protocol below; a run with no presser makes it GAP `needs a person`. `ped` and `eye` always run on a client and refuse `side = 'server'` |
| `players` | `1` · `2` | `1` | `2` = needs player A (the presser) and player B (invited) |
| `destructive` | boolean | `false` | `true` = the test gives a real player items, or writes a real player's stored data (server KVP, item metadata, files) |
| `expect` | string ≤ 240 | nil | What a person should see; required for `eye` (empty = FAIL, below). Shown after "Normally you will see" |
| `ask` | string ≤ 160 | nil | The question on the eye card (`eye` only). nil = the test name |
| `timeout` | integer ms | `5000` | Clamped to 500–60000; a value outside logs one `warn` |
| `skipWhen` | table | nil | `{ resources = { 'pma-voice', … } }` (≤ 8 names ≤ 64): SKIP when any listed resource is not `started`, reason `needs <name>` |

`expect` and `ask` are plain text the owner resource already translated with its own `t()`; core cleans them with
`text.clean` and never parses them as HTML. A bad `meta` (wrong type, unknown field, unknown `kind`) makes
`addSelftest` return `nil, '<field>: <rule>'`, registers nothing and logs one `warn`.

New server export `declareNoSelftests(reason)` (reason ≤ 120): a started `aeterna_*` resource that has no tests on
purpose (for example a server owner's own resource with that prefix) says so, and appears as one SKIP row instead of
MISSING.

**Registering without an export (optional edge).** A resource that has only an optional edge to core
(`aeterna_loading`, ADR 0005 decision 7) cannot call exports of core, so the same calls exist as local events. Each
carries `owner` first, and core accepts it only when `owner` equals `GetInvokingResource()` inside the handler and,
for results, when `owner` owns the test:

| Local event | Side | Same as |
| --- | --- | --- |
| `aeterna_core:selftest:add` → `(owner, name, meta)` | server | export `addSelftest(name, meta)` |
| `aeterna_core:selftest:none` → `(owner, reason)` | server | export `declareNoSelftests(reason)` |
| `aeterna_core:selftest:report` → `(owner, runId, name, ok, detail, extra)` | server and client | export `reportSelftest` on that side |
| `aeterna_core:selftest:answer` → `(owner, runId, name, answer)` | client | client export `answerEye` |

Core fires `aeterna_core:hello` (server-local and client-local, no arguments) once it has started and its registry is
empty and ready. A resource with an optional edge registers on its own start when core is already `started`, and again
on every `hello`, because a restart of core drops the registry. Resources with a hard edge are restarted with core and
need no `hello`.

### Result states

| State | `ok` | When |
| --- | --- | --- |
| `PASS` | true | The owner reported a pass, or the person answered "Pass" on the eye card |
| `FAIL` | false | The owner reported a fail; timeout; owner resource stopped mid-test; person answered "Doesn't match"; an undeclared destructive write; SKIP with no reason; MOCK not restored; `eye` with empty `expect` |
| `SKIP` | true | `skipWhen` matched, the owner reported a skip with a non-empty reason, or a destructive test met a closed gate. Always carries a reason |
| `GAP` | true | Needs a person (`ped`/`eye` in a run with no presser), needs player B (`players = 2`, none invited or B left), the person did not answer in 120 s, or the person pressed "Skip" on the eye card |
| `MOCK` | true | A `mock` test passed and reported `restored = true` |
| `MISSING` | false | A started resource whose name starts with `aeterna_` registered no test and did not call `declareNoSelftests` |

A run is green when no row is FAIL or MISSING. GAP rows are listed as work left for a person; they never turn a run
red. `ok` keeps its 0.1 meaning for callers that read only `ok`.

Judging rules, applied by core whatever the owner reports:

1. A SKIP without a reason (empty or whitespace `detail`) becomes FAIL `skip needs a reason`.
2. A `mock` result without `restored = true` becomes FAIL `state not restored`. A `mock` test that times out is FAIL
   `timeout, state may not be restored`.
3. A test not declared `destructive` that reports `wrote = true`, or that calls the write guard (below), becomes FAIL
   `undeclared destructive`.
4. An `eye` test with an empty `expect` becomes FAIL `expect is empty` without being sent to a client.
5. A result for a test that is not in flight, from a resource that does not own it, from a client the test was not
   sent to, or after the test already ended, is dropped (logged at `debug`).

### Reporting a result (server)

`reportSelftest(runId, name, ok, detail)` from 0.1 keeps working: `ok = true` → PASS, `false` → FAIL. In 0.2 `ok` may
also be a state string and a fifth argument carries extras:

```lua
exports.aeterna_core:reportSelftest(runId, name, 'skip', 'needs pma-voice')
exports.aeterna_core:reportSelftest(runId, name, 'mock', 'stack merged 3 toasts', { restored = true })
exports.aeterna_core:reportSelftest(runId, name, false, 'step 3: screen is home', { step = 3, expected = 'contacts.detail' })
```

| Arg | Rule |
| --- | --- |
| `ok` | `true` · `false` · `'pass'` · `'fail'` · `'skip'` · `'mock'`; the client export also takes `'ready'` (eye tests only). `'gap'` is set by core only |
| `detail` | string ≤ 300, cleaned |
| `extra` | `{ restored?: boolean, wrote?: boolean, step?: integer 1–99, expected?: string ≤ 80 }`; other keys dropped |

Server-local event `aeterna_core:selftest` → `(runId, name, ctx)`. The third argument is new and 0.1 handlers ignore
it: `ctx = { kind, side = 'server', a = src|nil, b = src|nil, destructive = boolean }`. Only `headless` and `mock`
tests with `side = 'server'` are fired on the server; `side = 'client'`, `ped` and `eye` tests go to clients.

**Write guard.** `AeternaCore.selftest.mayWrite(runId, name) -> boolean` (server, from `import.lua`) calls the export
`selftestMayWrite`. It returns `true` only for a test declared `destructive` in a run whose gate is open. Called by a
test that is not declared destructive, it returns `false` and marks that test FAIL `undeclared destructive`. Kit
packages call it before any persistent write made inside a test.

### Client-side protocol (`ped`, `eye`, and `side = 'client'`)

The server stays the judge: a client can only report on a test core sent to that client in the current run, once,
before its timeout, and every report passes the judging rules above.

1. Server → client `aeterna_core:cl:selftest` to player A (and to B for `players = 2`).
2. Core's client fires the client-local event `aeterna_core:selftest` → `(runId, name, ctx)` with
   `ctx = { kind, side = 'client', role = 'A' | 'B', destructive }`. The owner's client script filters on the name
   prefix of its own resource.
3. `ped`, client-side `headless` and client-side `mock`: the owner does its work and calls client export
   `reportSelftest(runId, name, ok, detail, extra)` (same arguments as the server export, plus `'ready'` below). Core's
   client sends `aeterna_core:sv:selftestResult`. The judging rules apply unchanged (a client `mock` must report
   `restored = true`).
4. `eye`: the owner sets up what the person must look at, then calls the client `reportSelftest` with `ok = 'ready'`
   (accepted only by the client export and only for `eye` tests; the server export refuses it). Core's client fires client-local
   `aeterna_core:eyeAsk` → `(runId, name, { ask, expect, role })`, which `aeterna_testkit` shows as a card. The answer
   comes back through client export `answerEye(runId, name, answer)` with `answer = 'pass' | 'mismatch' | 'skip'`,
   sent as `aeterna_core:sv:eyeAnswer`. `pass` → PASS, `mismatch` → FAIL `tester saw something else`, `skip` → GAP
   `skipped by the tester`, no answer in 120 s → GAP `no answer`. Without `aeterna_testkit` nobody listens to
   `eyeAsk`, so eye tests end as GAP.
5. When a test ends for any reason, server → client `aeterna_core:cl:selftestEnd` and client-local
   `aeterna_core:selftestEnd` → `(runId, name)` let the owner tear down what it opened (close the phone, delete the
   prop). Owners must tear down on this event even when they never reported.

For `players = 2` both roles report; the merged state is the worst of the two in the order FAIL, GAP, SKIP, MOCK,
PASS. If a player drops while a test is in flight, that test is GAP `player left`.

### Runs

| Export (server) | Returns | Notes |
| --- | --- | --- |
| `startRun(opts)` | runId or `nil, busy` | `opts = { by = src (0 = console), b = src?, only = { '<name or resource prefix>', … }? }` (≤ 32 entries). Returns at once; progress comes by event. The calling resource checks its own ACE before calling; core records `GetInvokingResource()` as the run's starter |
| `runStatus(runId)` | table or nil | `{ runId, phase, done, total, counts = { PASS, FAIL, SKIP, GAP, MOCK, MISSING }, rows }` |
| `cancelRun(runId)` | boolean | Only the starting resource or console. Tests not yet started become GAP `run cancelled`; a `mock` in flight keeps its timeout so it can restore |
| `busy()` | table or nil | `{ by = 'console' | 'resource', starter = '<resource>', since = seconds, phase, done, total }`. Never a player name |
| `listSelftests()` | array | `{ name, owner, kind, side, players, destructive, expect, ask, timeout, skipWhen }` per test, plus `{ name, owner, noTests = reason }` rows from `declareNoSelftests` |

`runId` = `r` + a base-36 counter + `-` + four random base-36 characters (≤ 24).

**One run at a time.** While a run holds the lock, `startRun` returns `nil, busy()` and `runSelftests` returns the busy
row (below). The lock is freed when the run ends, when it is cancelled and its last mock has ended, or when the
starting resource stops (the run is cancelled). A run that exceeds the sum of its timeouts plus 120 s per eye test is
cancelled by core.

**Order.** Phase `headless`: every server-side headless test that does not need B fires at once, each with its own
timeout. Phase `mock`: server-side mocks one at a time. Phase `client`: client-side headless, client-side mock, `ped`
then `eye` tests one at a time on A, then every `players = 2` test with A and B. Phase `missing`: started `aeterna_*` resources with no tests become MISSING rows. Inside each phase, tests run
in registration order.

**Destructive gate.** Before a destructive test starts, core checks `aeterna_core_allow_destructive == 'true'` and
"not listed publicly". If either fails, the test is SKIP `destructive tests are off` or SKIP
`server is listed publicly`; it never runs.

Server-local events:

| Event | Args | Notes |
| --- | --- | --- |
| `aeterna_core:runProgress` | `(runId, row)` | After every row is final. `row = { name, suite, kind, players, destructive, state, ok, detail, ms, step?, expected? }`; `suite` = owner resource |
| `aeterna_core:runDone` | `(runId, summary)` | `summary = { counts, ok, cancelled, ms, destructive = 'on' | 'off' }` |

**`runSelftests()`** (0.1 export) keeps its synchronous shape: it starts a console-style run (no players, so `ped`,
`eye` and `players = 2` tests are GAP), waits for it, and returns the rows with the 0.1 fields `name, ok, detail, ms`
plus the 0.2 fields. While another run holds the lock it returns one row
`{ name = 'aeterna_core.lock', ok = false, state = 'FAIL', detail = 'busy: <phase> since <n> s' }`.

### Commands (0.2)

**Changed in 0.2 — `aeterna_core_selftest` accepts only source 0** (server console, txAdmin, rcon). In 0.1 players
with ACE `aeterna.core.selftest` could run it from chat or F8. Reason: a run now opens a lock and may run mocks and
destructive tests, and players get a button menu (`aeterna_testkit`) with its own ACE, rate limits and consent for
player B. Upgrade note: replace `add_ace … aeterna.core.selftest allow` with `add_ace … aeterna.testkit.run allow` and
install `aeterna_testkit`; a player who types the command gets the locale line `core.selftest.console_only`.

Output: one line per row `<STATE> <name> <ms> ms <detail>`, then `core.selftest.total` with every count.

### Focus overlay

0.1 focus has one holder and the last request wins (the old holder gets `focusLost` `preempted` and closes). 0.2 adds
an **overlay** request for a small card that must sit on top of an open screen without closing it (the testkit eye
card looks at the very screen it covers). 0.1 requests behave as before.

`requestFocus(opts)` accepts `overlay = true` (export and `AeternaCore.requestFocus` helper):

1. If someone holds focus, that holder is **paused**, not preempted: it keeps its token and gets the client-local
   event `aeterna_core:focusPaused` → `(owner, token)`. The `import.lua` helper in the paused resource clears its own
   `SetNuiFocus` / `SetNuiFocusKeepInput` (the page stays visible) and remembers its options.
2. The overlay owner gets a new token and focus. `focusOwner()` returns the overlay owner; new client export
   `focusPausedOwner() -> string|nil` returns the paused one.
3. When the overlay owner releases its token, or its resource stops, the paused holder gets
   `aeterna_core:focusResumed` → `(owner, token)` and the helper re-applies the remembered options. Focus is back
   where it was, with the same token.
4. While paused, a package keeps its screen open and in the same state, ignores input from its page, and does **not**
   close. Only `focusLost` closes a panel. A paused holder may still release its own token; then nothing resumes when
   the overlay ends.
5. One overlay at a time: a second overlay request preempts the first overlay (`focusLost` `preempted`), and the
   paused holder stays paused. A normal (non-overlay) request while an overlay is up preempts both the overlay owner
   and the paused holder (`focusLost` `preempted` to each), as the 0.1 last-request-wins rule says.
6. An overlay request with nobody holding focus behaves like a normal request.

Every kit package that closes on `focusLost` (uikit prompts and panels, phonekit, radial, the camera gallery) handles
`focusPaused` / `focusResumed` as in rule 4.

### Theme preset

Client export `themePreset() -> 'asphalt' | 'paper' | 'night-market'` reads `aeterna_theme_preset`. The theme message
every package already sends gains one field:

```lua
SendNUIMessage({ type = 'aeterna:theme', href = exports.aeterna_core:themeHref(), preset = exports.aeterna_core:themePreset() })
```

`import.lua` adds `AeternaCore.themeMessage()` returning that table. The page sets `data-preset="<preset>"` on its
`<html>` element only when `href` is empty; the presets in `theme.css` select on it. When `aeterna_theme` is set the
page sets no `data-preset`, so the owner's `:root` rules win (a `:root[data-preset=…]` rule would otherwise beat
them on specificity) and the preset convar is ignored. A page that ignores `preset` stays on Asphalt, as in 0.1. A changed preset
applies after the package restarts or the player reconnects.

### Events (0.2)

| Event | Direction | Schema | Rate limit |
| --- | --- | --- | --- |
| `aeterna_core:cl:selftest` | server → client | `{ runId: string ≤ 24, name: string ≤ 96, kind: enum headless/mock/ped/eye, role: enum A/B, timeout: integer, destructive: boolean, expect?: string ≤ 240 (eye only), ask?: string ≤ 240 (eye only) }` | — |
| `aeterna_core:cl:selftestEnd` | server → client | `{ runId, name }` | — |
| `aeterna_core:sv:selftestResult` | client → server | `{ runId: string ≤ 24, name: string ≤ 96, state: enum pass/fail/skip/mock/ready, detail: string ≤ 300 optional, restored: boolean optional, wrote: boolean optional, step: integer 1–99 optional, expected: string ≤ 80 optional }` | 20 / 10000 ms |
| `aeterna_core:sv:eyeAnswer` | client → server | `{ runId: string ≤ 24, name: string ≤ 96, answer: enum pass/mismatch/skip }` | 5 / 5000 ms |
| `aeterna_core:selftest` | server-local and client-local | `(runId, name, ctx)` | — |
| `aeterna_core:eyeAsk` | client-local | `(runId, name, { ask, expect, role })` | — |
| `aeterna_core:selftestEnd` | client-local | `(runId, name)` | — |
| `aeterna_core:selftest:add` · `:none` | server-local | above | — |
| `aeterna_core:selftest:report` | server-local and client-local | above | — |
| `aeterna_core:selftest:answer` | client-local | above | — |
| `aeterna_core:hello` | server-local and client-local | none | — |
| `aeterna_core:focusPaused` · `aeterna_core:focusResumed` | client-local | `(owner, token)` | — |
| `aeterna_core:runProgress` · `aeterna_core:runDone` | server-local | above | — |

Both server handlers check the rate limit first, then the schema, then that `source` is the player the test was sent
to in the current run.

### Locale keys (0.2)

`core.selftest.total` gains `{skip}`, `{gap}`, `{mock}`, `{missing}`. New: `core.selftest.console_only`,
`core.selftest.busy`, `core.selftest.gap.no_person`, `core.selftest.gap.no_b`, `core.selftest.gap.no_answer`,
`core.selftest.gap.tester_skip`, `core.selftest.gap.player_left`, `core.selftest.gap.cancelled`,
`core.selftest.skip.needs`, `core.selftest.skip.destructive_off`, `core.selftest.skip.public`,
`core.selftest.fail.timeout`, `core.selftest.fail.owner_stopped`, `core.selftest.fail.not_restored`,
`core.selftest.fail.undeclared_destructive`, `core.selftest.fail.no_reason`, `core.selftest.fail.no_expect`,
`core.selftest.fail.mismatch`, `core.selftest.missing`.

### `oss.json` capabilities (0.2)

```json
{ "http": [], "commands": [], "registeredCommands": ["aeterna_core_selftest"],
  "convars": { "read": ["aeterna_locale", "aeterna_timezone", "aeterna_theme", "aeterna_core_log_level",
                        "aeterna_theme_preset", "aeterna_core_allow_destructive", "sv_master1"], "write": [] },
  "netEvents": { "server": ["aeterna_core:sv:selftestResult", "aeterna_core:sv:eyeAnswer"],
                 "client": ["aeterna_core:cl:selftest", "aeterna_core:cl:selftestEnd"] },
  "nui": true, "db": { "tables": [], "ddl": false }, "files": { "write": [] } }
```

### Self-tests (0.2)

| Name | Kind | Players | Destructive | Expect | Skip-when |
| --- | --- | --- | --- | --- | --- |
| `aeterna_core.core` | headless | 1 | n | — | — |
| `aeterna_core.meta` | headless | 1 | n | — (a bad `meta` is refused with the field name; defaults applied) | — |
| `aeterna_core.run_lock` | headless | 1 | n | — (`busy()` is set during this run and `startRun` returns `nil, busy`) | — |
| `aeterna_core.client_echo` | ped | 1 | n | — (a client round trip reports PASS within the timeout) | — |
| `aeterna_core.focus_overlay` | headless (`side = 'client'`) | 1 | n | — (a holder gets `focusPaused` on an overlay request, keeps its token, and `focusResumed` on release) | — |
| `aeterna_core.theme_preset` | headless | 1 | n | — (`themePreset` returns one of the three names) | — |

### Tests (0.2)

busted (pure module `shared/logic/selftest.lua`: registry, judging rules, merge and gate; no natives):

1. `addSelftest('x')` gets `kind = 'headless'`, `players = 1`, `destructive = false`, `timeout = 5000`; `timeout = 90000`
   clamps to 60000 with one `warn`; `kind = 'video'` is refused with `kind: enum`.
2. Judging: SKIP with `detail = '  '` → FAIL `skip needs a reason`; `mock` without `restored` → FAIL; `wrote = true` on a
   non-destructive test → FAIL `undeclared destructive`; `eye` with empty `expect` → FAIL and never dispatched.
3. GAP: a run with `by = 0` turns `ped` and `eye` tests into GAP `needs a person`; `players = 2` without `b` → GAP
   `needs player B`; an eye answer `skip` → GAP; no answer after 120 s (fake clock) → GAP.
4. Merge for `players = 2`: (PASS, GAP) → GAP; (MOCK, FAIL) → FAIL; (PASS, PASS) → PASS.
5. `skipWhen = { resources = { 'pma-voice' } }` with a fake `GetResourceState` returning `missing` → SKIP
   `needs pma-voice`; `started` → the test runs.
6. Gate: `allow_destructive = 'true'` and `sv_master1 = ''` → open; `sv_master1` unset (sentinel) → SKIP
   `server is listed publicly`; `allow_destructive = 'false'` → SKIP `destructive tests are off`.
7. MISSING: a started `aeterna_demo` with no test → MISSING; after `declareNoSelftests('owner tool')` → SKIP with that
   reason; `aeterna_core` itself is never MISSING.
8. Lock: a second `startRun` while one runs returns `nil, busy` with `starter` and no player name; `runSelftests`
   returns the single `aeterna_core.lock` FAIL row; the lock frees after `runDone` and after the starter stops.
9. Results are dropped when the run id is stale, the test is not in flight, the test already ended, the source is not
   the assigned player, or the reporting resource is not the owner.
10. Order: headless rows fire together, mock rows one at a time, client rows in registration order, two-player rows
    last.
11. Run id matches `^r[%da-z]+%-[%da-z][%da-z][%da-z][%da-z]$` and is ≤ 24 characters.
12. `themePreset` returns `asphalt` for `''`, `'Paper'` and `'neon'` (one `warn` each), and the value for the three
    valid names.

13. `side`: a `headless` test with `side = 'client'` is sent to A and its client report is judged like a server
    one; in a run with no presser it is GAP `needs a person`; `side = 'server'` on `ped` is refused with `side: enum`.
14. `'ready'`: accepted from the client `reportSelftest` for an `eye` test (fires `eyeAsk`); refused by the server
    export and for every other kind.
15. Local-event registration: `aeterna_core:selftest:add` with `owner` ≠ the invoking resource is ignored; with the
    right owner it registers like the export; after a fake core restart `hello` fires on both sides and the test is
    registered again.
16. Focus overlay (pure state machine): holder H, overlay O → H gets `focusPaused`, keeps its token, owner = O; O
    releases → H gets `focusResumed`, owner = H; overlay O2 while O is up → O gets `focusLost`, H stays paused; normal
    request N while O is up → O and H get `focusLost`; O's resource stops → H resumes.

Smoke (clean qbx server):

1. `aeterna_core_selftest` from the console prints every row with a state and the total; typed by a player in F8 it
   prints `core.selftest.console_only` and starts nothing.
2. With `aeterna_testkit` installed, a menu run sends the `ped` test to the presser and it reports PASS; stopping the
   owner resource mid-test gives FAIL `owner stopped` and frees the lock.
3. `set aeterna_core_allow_destructive true` with `sv_master1` unset: destructive tests show SKIP
   `server is listed publicly`; with `set sv_master1 ""` and a restart they run.
4. `setr aeterna_theme_preset paper` and reconnect: every kit page that sends `preset` shows the light preset; with
   `aeterna_theme` set as well, the owner's file wins.
5. Open a uikit panel, then let a test resource request an overlay: the panel stays open and ignores clicks, the
   overlay takes the cursor, and after it releases the panel has the cursor again.
6. Spam `aeterna_core:sv:selftestResult` from a test client: past 20 in 10 s the events are dropped and nothing
   changes state.

### Done when (0.2)

All 0.1 and 0.2 busted cases pass in `npm run test:lua`, `fivem-devkit safety` reports 0 errors and 0 over-declared
items with the 0.2 `oss.json`, the 0.2 smoke steps pass on the test server, and the README documents the new fields,
states, convars, the source 0 change and its upgrade note.
