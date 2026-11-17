# ADR 0004 — AETERNA Starter Kit (`aeterna_*` packages): generic templates for running your own FiveM server

- Status: proposed — owner accepted the plan's recommendations Q1–Q6, chose one release of seven and picked the
  Asphalt theme on 2026-11-17; waiting for the owner to accept this ADR by merging it (gate G0)
- Date: 2026-11-17
- Related: ADR 0001 (KVP settings, measured spikes before decisions); ADR 0003 decision 10 (a package that names the
  optional resource it calls); this repo's `AGENTS.md` hard rules 3, 4, 5, 7 and 8; plan "nakara-oss — Starter Kit"
  (owner's doc, review findings B1–B4, M1–M7, P1–P5, N1–N6)
- Written by: Claude Code - Claude Opus 5.5

## Context

People who start a FiveM server rebuild the same basics: a UI kit, notifications and announcements, a HUD whose parts
players can move, a phone, and helpers around the inventory. The Nakara City team has built all of these for its own
server. The owner wants a first set released here as templates other servers can use, under the team's studio name
(`aeterna_*`), with two hard limits: none of Nakara City's look (colours, logos, fonts, brand copy) and none of its
server-side internals (anti-cheat, economy, admin tooling, telemetry, identifiers).

A review of the plan against this repo (`1b16577`) found facts that shape the decisions below:

- The `nakara_` prefix is enforced in `oss.schema.json` (`resource` pattern), `.github/scripts/oss-manifest.mjs`
  (used by `build-release.mjs`), `templates/resource/oss.json`, `packages/devkit/docs/safety.md`, `CONTRIBUTING.md`,
  rule 5 of `AGENTS.md` and the project site.
- Rule 5 forbids any dependency between packages, but nothing in code checks it.
- `net-event-rate-limit` recognises only `NakaraCore.rateLimit`, `lib.callback` and `rateLimit`
  (`packages/devkit/src/safety/index.js:25`).
- The scanner skips files whose extension it does not know (`packages/devkit/src/safety/model.js:47`), so fonts,
  images and `.svg` files pass with no finding at all; `opaque-file` knows only a fixed list of binaries.
- `release.yml` and `build-release.mjs` release one package per run.
- Every FiveM resource with a `ui_page` draws in its own NUI frame. A resource cannot measure or drag elements that
  another resource draws, and several resources that call `SetNuiFocus` will take focus from each other.
- Upstream `ox_inventory` is GPL-3.0. Calling its exports does not make a package GPL (as `nakara_tickets` already
  does); copying or modifying its web files would.
- The repo is public: every commit, brief and spec stays in history for good, so anything that could leak has to be
  stopped before a push, not after.

## Decision

1. **Names.** Starter Kit resources are named `aeterna_<name>`. Existing packages keep `nakara_*`. The schema pattern
   becomes `^(nakara|aeterna)_[a-z0-9_]+$`. The schema, rule 5, `CONTRIBUTING.md`, the engineer contract and the
   site change with this ADR; the scanner needs no change for `AeternaCore.rateLimit` (decision 5). Names are
   chosen so they never equal a resource name the team runs privately; the maintainer checks this before a name is
   added, from a list kept outside this repo.
2. **Rule 5, rewritten.** A package may depend on another package of this repo only along an edge listed in the
   table below, and never on a resource that is not published here. `qbx_core` and `ox_lib` stay optional defaults.
   Any other optional resource is touched only under rule 5's existing conditions and only by a package whose ADR
   names it.

   | Package | May depend on |
   | --- | --- |
   | `aeterna_core` | — (`ox_lib` optional) |
   | `aeterna_notify` | `aeterna_core` |
   | `aeterna_uikit` | `aeterna_core` |
   | `aeterna_layout` | `aeterna_core`, `aeterna_uikit` |
   | `aeterna_hudkit` | `aeterna_core`, `aeterna_uikit`, `aeterna_layout` |
   | `aeterna_phonekit` | `aeterna_core`, `aeterna_uikit`, `aeterna_notify` |
   | `aeterna_invkit` | `aeterna_core`, `aeterna_uikit` (+ `ox_inventory`, decision 15) |

   A new check in `.github/scripts` reads each package's `fxmanifest.lua` `dependencies`, `exports.<resource>`,
   `nui://<resource>/` and `@<resource>/` references and fails on any edge not in this table.
3. **One release, built in waves.** All seven packages ship together as v0.1.0 (owner, 2026-11-17: "7 in one
   release"). They are built in dependency order — W1 `aeterna_core`, `aeterna_uikit` and the scanner changes; W2
   `aeterna_layout`, `aeterna_notify`, `aeterna_invkit`; W3 `aeterna_hudkit`, `aeterna_phonekit` — and nothing is
   tagged until all seven pass the smoke test and the owner's gate. Each package gets its own tag
   (`aeterna_core@0.1.0` …) through the existing release workflow; a combined zip needs a release workflow change
   and is added only if the owner accepts that change.
4. **Contracts, not ports.** Each package starts with a spec in `docs/specs/<package>.md`: exports, events, payload
   schemas, KVP keys, and test cases. A spec describes behaviour a server owner can see. It never retells how the
   team's private code works. Specs pass the leak review (decision 9) before they are committed. Code is written
   from the spec and the owner-approved mockups.
5. **`aeterna_core` owns NUI focus.** Packages ask `aeterna_core` for focus and release it; a package that loses focus
   cancels its own mode. `aeterna_core` also provides `AeternaCore.rateLimit`, which the scanner already accepts (a call path ending in
   `.rateLimit` matches its default `rateLimit` entry).
6. **Theme.** Every package ships its own copy of `html/theme.css`; CI checks that all copies are identical, so no
   package loads files across resources. Colours, type and spacing are CSS custom properties with neutral names
   (`--accent`, `--surface-*`, `--text-*`). A server owner overrides the theme with the convar `aeterna_theme`: a
   `nui://` path in their own resource, which Lua hands to each NUI page. Loading across resources is settled by
   spike S2 before v0.1's spec is frozen; if it fails, the override is a copy step in the theming guide.
   The default theme is **Asphalt** (owner, 2026-11-17, picked from three mockups): solid graphite surfaces, one
   road-sign blue accent used only for the primary action and the health bar, radii 6 / 10 / 14 px, inner padding
   14 px. Starting tokens:

   | Token | Value | Token | Value |
   | --- | --- | --- | --- |
   | `--surface` | `#1d2024` | `--accent` | `#2f6feb` |
   | `--raised` | `#262a2f` | `--on-accent` | `#ffffff` (4.57 : 1) |
   | `--text` | `#eceff2` | `--good` | `#3fae6e` |
   | `--text-2` | `#aab1b9` | `--warn` | `#d9a03a` |
   | `--text-3` | `#8a929b` (5.19 : 1 on surface) | `--bad` | `#e0574f` |
   | `--line` | `rgba(232,236,240,.09)` | `--track` | `rgba(232,236,240,.12)` |
7. **Font.** One OFL-licensed Thai and Latin family (default: IBM Plex Sans Thai), `.woff2` only, may live in
   `packages/*/html/fonts/`, at most 1 MB per package, with its `OFL.txt` beside it. A new scanner rule enforces the
   path, the size and the licence file, and refuses `.svg` files; icons are inline SVG inside JavaScript from a named
   permissively licensed set (Lucide, ISC), listed in the package's `NOTICE`.
8. **Settings stay on the player's machine.** Layout, toggles and preferences are client KVP under keys that carry a
   version (`aeterna_<pkg>:<name>:v1`). v0.1–v0.3 create no database tables (`db.ddl = false`).
9. **Leak gate before every push.** The maintainer's side keeps a deny list (brand terms, hosts, identifier patterns,
   private resource names) outside this repo. The scan runs on the maintainer's machine before each push, including
   documentation commits, and in CI through the GitHub App the provenance check already uses. CI reports only
   "term #k at file:line", never the term. A pull request from a fork that cannot run the scan waits for a
   maintainer to run it. Each release is also read in full by a second model before the owner's gate.
10. **No default keys.** Packages register commands with `RegisterKeyMapping` and no default key, so they never clash
    with `ox_inventory` (TAB, 1–5) or the `qbx`/`ox_lib` menus. Command names are permanent once released, because
    players' bindings stick to them. Two inputs work without binding: ESC closes any open panel, and Space answers a
    skill check while one runs (jumping is disabled during it), because a check nobody can answer is useless.
11. **Every NUI callback and net event** validates its payload against a schema in the spec, is rate limited on the
    server, and checks ACE on the server for anything that reaches other players (announcements).
12. **Layout across resources is a coordinate protocol.** Each resource reports its movable boxes (id, size, anchor);
    `aeterna_layout` draws stand-ins in its own frame for the player to drag, then sends back
    `{id, x, y, ax, ay, scale}` for each resource to apply. Spike S1 proves this in game before v0.2's spec.
13. **Accessibility.** Text meets WCAG AA contrast on the default theme, motion respects a reduced-motion setting, and
    every panel closes with ESC and a visible button.
14. **Support scope.** Each package README states the `qbx_core`, `ox_lib` and FXServer versions it was tested on and
    what the team does and does not support.
15. **`aeterna_invkit` and `ox_inventory`.** `aeterna_invkit` may call `ox_inventory` exports (stashes, item use)
    under rule 5's conditions: only when `GetResourceState` says it is started, never listed as a dependency. It ships
    no hotbar (ox_inventory has one) and no file copied or adapted from ox_inventory, which is GPL-3.0; its theming
    guide for ox_inventory is prose and CSS selectors only.

## Per-package checklist

`fxmanifest.lua`, `oss.json` (maintainer-owned, rule 7), `README.md` (TH/EN), `CHANGELOG.md`, `NOTICE` when assets are
bundled, `spec/` with busted tests, an entry in `.fivem-devkit.json` `specRoots`, coverage in `.busted`, locale files
`locales/th.lua` and `locales/en.lua`, and a spec in `docs/specs/`.

## Consequences

- Rule 5, the schema and the release script change once; later `aeterna_*` packages need only a table row.
- The scanner grows two rules (fonts/assets, dependency edges). These paths are maintainer-owned (rule 7), so the
  owner reviews them.
- Copies of `theme.css` cost a few KB per package and remove a whole class of cross-origin failures.
- The private server does not vendor these packages for now; if it does later, its vendoring check must accept the
  `aeterna_` prefix and refuse names that collide with its own resources.
- A smoke test needs a clean FXServer with its own licence key, which only the owner can set.
