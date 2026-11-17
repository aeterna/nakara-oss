# Starter Kit specs

Contracts for the `aeterna_*` Starter Kit packages ([ADR 0004](../adr/0004-aeterna-starter-kit.md)). A spec says what a
server owner, a player and another resource can see and call. It is written before the code; the code and its tests
follow it. A change to a released contract is a new major version of that package.

| Spec | Package | Wave | Status |
| --- | --- | --- | --- |
| [aeterna_core](aeterna_core.md) | `packages/core` | W1 | draft |
| [aeterna_uikit](aeterna_uikit.md) | `packages/uikit` | W1 | draft |
| [aeterna_notify](aeterna_notify.md) | `packages/notify` | W2 | draft |
| [aeterna_invkit](aeterna_invkit.md) | `packages/invkit` | W2 | draft |
| [aeterna_layout](aeterna_layout.md) | `packages/layout` | W2 | draft |
| [aeterna_hudkit](aeterna_hudkit.md) | `packages/hudkit` | W3 | draft |
| `aeterna_phonekit` | `packages/phonekit` | W3 | after uikit and notify |

## Conventions every spec follows

These hold for every package unless its spec says otherwise.

### Names

- Resource `aeterna_<pkg>`. Exports are camelCase verbs (`openStash`, `notify`).
- Net events: `aeterna_<pkg>:sv:<name>` (client → server) and `aeterna_<pkg>:cl:<name>` (server → client).
  Local events inside one side: `aeterna_<pkg>:<name>`. Ids inside payloads (panel, block, item, entry) are
  ≤ 32 characters matching `^[%w_%-]+$`.
- Resources never pass functions to each other through exports. A package that needs an answer from another resource
  fires a server-local event carrying `owner` (the resource that registered), and the owner filters on
  `owner == GetCurrentResourceName()`. A restarted resource therefore never leaves a stale callback behind.
- Commands: `aeterna_<pkg>_<name>` or `aeterna_<name>` for console and chat commands; key mappings use
  `+aeterna_<pkg>_<name>` / `-aeterna_<pkg>_<name>`. Each package calls `RegisterCommand` for its own `+`/`-` pair with
  literal names (the scanner only counts literal names), then `AeternaCore.key` maps them with no default key. Command
  names never change after release (players' bindings stick to them).
- ACE permissions: `aeterna.<pkg>.<action>` (for example `aeterna.notify.announce`). The kit never grants ACE; the
  server owner adds `add_ace group.admin aeterna.notify.announce allow` in `server.cfg`.
- Convars: `aeterna_<pkg>_<name>`, plus the shared `aeterna_locale`, `aeterna_timezone`, `aeterna_theme` and
  `aeterna_core_log_level` read through `aeterna_core`. A convar the client reads must be set with `setr` (replicated);
  `set` leaves the client on the default.
- Client KVP keys: `aeterna_<pkg>:<name>:v<n>`. A new shape gets a new `v<n>`; the old key is read once, converted,
  then deleted.

### Payloads

- Every net event and NUI callback has a schema in its spec, written in the format `aeterna_core` validates
  (see [aeterna_core § Validation](aeterna_core.md#validation)). Anything that fails the schema is dropped and logged
  at `warn` with the event name and the first failing field. It is never partly applied.
- Every server net-event handler calls `AeternaCore.rateLimit(source, key, max, windowMs)` first. The limit is written
  in the spec's event table.
- The server never trusts a client for identity, money, items, position or permission. It reads them itself.
  Results the client reports (a finished progress bar, a passed skill check) never decide a reward on their own; the
  server re-checks time and state.
- Strings shown to other players are cut to their schema `maxLen` and stripped of control characters by
  `AeternaCore.text.clean`. NUI renders text with `textContent` only.

### NUI

- Plain HTML, CSS and JavaScript in `html/`, no build step, no minified files.
- `html/theme.css` is the same file in every package (CI checks it). The Asphalt values are in ADR 0004 decision 6.
- `html/fonts/` holds the OFL font with its `OFL.txt` (ADR 0004 decision 7). Icons are inline SVG from the package's
  own icon map, drawn from Lucide (ISC), listed in `NOTICE`.
- A package that takes keyboard or mouse input asks `aeterna_core` for focus and gives it back (see
  [aeterna_core § Focus](aeterna_core.md#focus)). Every panel closes with ESC and with a visible close or cancel button.
- Motion: one easing (`cubic-bezier(.3,.8,.4,1)`), 140 ms for feedback, 200 ms for things that enter. With
  `prefers-reduced-motion: reduce` nothing moves; elements appear and disappear.

### Text and locale

- Every string a player sees is a locale key in `locales/th.lua` and `locales/en.lua`. The language comes from the
  convar `aeterna_locale` (default `en`); a missing key falls back to `en`, then to the key itself.
- No exclamation marks. Short labels end without a period.

### Files every package ships

`fxmanifest.lua`, `oss.json`, `README.md` (TH and EN), `CHANGELOG.md`, `NOTICE` when assets are bundled, `locales/`,
`spec/` (busted tests), and an entry in `.fivem-devkit.json` `specRoots`. Pure logic lives in natives-free modules
under `shared/logic/` so stock Lua can test it.

### Each spec has these sections

Purpose and limits · Install · Configuration (convars, config file) · Exports · Events · NUI messages · Commands and
keys · Storage · Locale keys · `oss.json` capabilities · Tests (busted cases and smoke steps) · Done when.
