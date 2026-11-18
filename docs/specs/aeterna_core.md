# aeterna_core

- Package: `packages/core` · resource `aeterna_core` · wave W1 · status released in 0.1.0
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
