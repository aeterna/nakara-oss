# AGENTS.md — instructions for AI coding agents (and humans)

This is the single source of agent instructions for this repository. `CLAUDE.md` only points here.
When working inside the AETERNA workspace (`freelance/aeterna/fivem/nakara-oss`), also follow the workspace standard (`../AGENTS.md`) and the org standard (`../../AGENTS.md`: worktree-always in `.claude/worktrees/<slug>`, heavy files on `/Volumes/WD1TB/`, multi-session FREEZE protocol, evidence rules, and `aeterna-delegate`).

## What this project is

`aeterna/nakara-oss` is the public, MIT-licensed monorepo of FiveM resources (`nakara_*`) and developer tooling (`@aeterna_game/fivem-devkit`) maintained by the **Nakara City** dev team.

Every resource declares its capabilities in `oss.json` (validated against [`oss.schema.json`](oss.schema.json)), every PR is scanned for dangerous code and undeclared capabilities by `fivem-devkit safety`, and every release is built in CI with a provenance attestation.

Read before changing code: [`CONTRIBUTING.md`](CONTRIBUTING.md) · [`packages/devkit/docs/safety.md`](packages/devkit/docs/safety.md) · [`docs/maintainers/SETUP.md`](docs/maintainers/SETUP.md) · [`SECURITY.md`](SECURITY.md).

## Hard rules (CI enforces them)

1. **DCO sign-off on every commit (`git commit -s`).** Every commit MUST carry a `Signed-off-by: Name <email>` trailer whose name and email match the commit author (`.github/scripts/check-dco.mjs` in CI job `DCO sign-off`).
2. **Agent and model attribution on every change.** Every AI agent or tool that modifies files, creates commits, opens PRs, or writes handoff/changelog notes MUST record its tool and model identity in the form `<Tool> - <Model>` (for example `Agent: AGY App - Gemini 4 Argon (Medium)`, `Agent: Claude Code - Claude Opus 4.6`, or when incorporating delegated output via `aeterna-delegate`, `AGY CLI - gemini-3.8-flash-medium` / `OpenCode CLI - deepseek-v4.1-flash-free` / `Claude CLI - claude-haiku-5-5`). In commits, include an `Agent: <Tool> - <Model>` trailer alongside `Signed-off-by:`.
3. **Every capability must be declared in `oss.json` — no more, no less.**
   - Every resource package under `packages/` (and [`templates/resource`](templates/resource)) ships `fxmanifest.lua`, `oss.json` (matching [`oss.schema.json`](oss.schema.json)), `README.md`, `CHANGELOG.md`, and `spec/`.
   - Any HTTP host/prefix, `ExecuteCommand`, registered command, convar read/write, net event (`server`/`client`), NUI usage, DB table/DDL, or `SaveResourceFile` write not declared in `oss.json` fails `fivem-devkit safety`. Unused declarations produce `over-declared` warnings.
4. **Hard-deny safety rules (`packages/devkit/docs/safety.md`).**
   - Never use `load`, `loadstring`, `dofile`, `loadfile`, `package.loadlib`, `os.execute`, `io.popen`, `os.remove`, `os.rename`, `os.getenv`, `debug.*`, `getfenv`/`setfenv`, `string.dump`, computed `_G[x]`, server-side `Citizen.InvokeNative`/`_in`, `eval`, `new Function`, `child_process`, `fs`, or raw sockets.
   - `secret-convar` (reading `rcon_password`, `sv_licenseKey`, `steam_webApiKey`, `mysql_connection_string`, or any `*token*`/`*secret*`/`*password*`/`*apikey*`/`*webhook*` convar) and `ace-command` (`ExecuteCommand` with `add_ace`, `add_principal`, `exec`, `set*`, `rcon`, `ensure`, `restart`, `stop`, `start`, `quit`, …) are **never allowlistable**.
   - Never commit binaries, archives, Lua bytecode, minified/bundled JS (`*.min.js`), obfuscated strings, or streamed GTA assets.
   - Server net-event handlers should call a recognized rate-limit helper (`NakaraCore.rateLimit`, `lib.callback`, `rateLimit`). NUI code must use `textContent`, never non-static `innerHTML`/`outerHTML`.
5. **Package boundaries & naming.**
   - Resource names use the `nakara_` prefix (`nakara_cargen_fix`, `nakara_core`, …).
   - Resource packages may depend only on the shared core package (`nakara_core` when present) and optional `ox_lib`/`qbx_core` defaults — **never** on each other, and **never** on any private `aeterna_*` resource or identifier.
   - Optional framework resources `qb-core` and `es_extended` (read only: names and identifiers) and `oxmysql` (a package's own storage) may be touched only when `GetResourceState` says they are started, never listed as a dependency, and only by a package whose ADR names them (owner, 2026-11-01; `docs/adr/0001-rongroi-server-kit.md` §11).
6. **Upstream-first.** This repository is the single upstream source for all `[oss]/` packages vendored into `nakara-city`. Never hand-edit vendored copies downstream; land the change here via PR, release with CI attestation, and bump downstream via `oss-vendor.mjs`.
7. **Protected paths require a Proposal issue from external contributors.** Changes touching `.github/`, `oss.schema.json`, any `oss.json` capability, or `packages/devkit/src/safety/` are maintainer-controlled (`CODEOWNERS`).
8. **Workflow hygiene.** Every GitHub Action in `.github/workflows/*.yml` must be pinned to a full commit SHA, use `persist-credentials: false` on `actions/checkout`, keep default `permissions: contents: read`, and pass `actionlint` + `zizmor`.

## Commands (run locally before pushing)

```bash
npm ci --ignore-scripts
npm run ci                                        # runs: npm test && npm run check && npm run safety
npm test --workspace packages/devkit              # devkit unit + safety scanner tests (node --test)
npm run test:lua                                  # Lua specs via busted (--config-file=.busted)
node packages/devkit/bin/fivem-devkit.js check    # static checks (dogfood)
node packages/devkit/bin/fivem-devkit.js safety   # safety + oss.json capability verification
node .github/scripts/capability-report.mjs origin/main
node .github/scripts/check-dco.mjs origin/main HEAD
```
