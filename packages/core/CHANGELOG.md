# Changelog

All notable changes to `aeterna_core` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

### Fixed

- `busy().since` and the `busy: <phase> since <n> s` detail now count whole seconds; the server passed milliseconds.

### Added

- Self-test fields `kind`, `side`, `players`, `destructive`, `expect`, `ask`, `timeout`, `skipWhen`, and the result
  states SKIP, GAP, MOCK and MISSING ([spec 0.2](../../docs/specs/aeterna_core.md#02-additions), ADR 0005).
- Runs: `startRun`, `runStatus`, `cancelRun`, `busy`, `listSelftests`, `declareNoSelftests`; one run at a time; phases;
  per-test timeouts; `runProgress` / `runDone` events.
- Client-side and two-player tests (`aeterna_core:cl:selftest`, `:sv:selftestResult`, `:sv:eyeAnswer`), eye checks
  answered through `answerEye`.
- Destructive gate (`aeterna_core_allow_destructive`, refused on a server listed publicly).
- Server-local and client-local registration events for resources with an optional edge, and `aeterna_core:hello`.
- Focus overlay: `requestFocus({ overlay = true })`, `focusPaused` / `focusResumed`, `focusPausedOwner()`.
- Theme presets: `themePreset()` (`aeterna_theme_preset`) and `AeternaCore.themeMessage()`.
- Client test started (server): before a `ped`, `eye`, `side = 'client'` or two-player test goes out, core fires the
  server-local `aeterna_core:selftestStarted` → `(runId, name, ctx)`, and it fires the server-local
  `aeterna_core:selftestEnd` → `(runId, name)` for every test that ends (pass, timeout, owner stopped, player left).
- Write guard: server export `selftestMayWrite(runId, name)` and `AeternaCore.selftest.mayWrite(runId, name)`; a test
  not declared destructive that calls it is FAIL `undeclared destructive`.
- `ped` and client-side `headless`/`mock` tests may carry `expect` (what the presser must do); core sends it to the
  client for every client test that sets it and passes it as `ctx.expect` in the client-local `aeterna_core:selftest`.
  It stays optional for those kinds and required for `eye`.

### Changed

- `aeterna_core_selftest` runs only from the server console (source 0). Upgrade: run it from the console or txAdmin;
  the `aeterna.core.selftest` ACE is no longer read.

## [0.1.0] - 2026-11-18

### Added

- Shared `@aeterna_core/import.lua` API (`log`, `on`/`off`/`emit`, Thai-aware `text`, `t`/`lang`, `time`, `validate`, `rateLimit`, `can`, `kvp`, and `key`).
- Client NUI focus coordinator (`requestFocus`, `releaseFocus`, `focusOwner`, and `aeterna_core:focusLost`) and `themeHref` export.
- Server self-test registry and runner (`addSelftest`, `reportSelftest`, `runSelftests`, and `aeterna_core_selftest`).
- English and Thai locale tables (`locales/en.lua`, `locales/th.lua`) and busted test suite (`spec/core_spec.lua`).
