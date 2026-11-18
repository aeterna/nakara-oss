# Starter Kit v0.1 handoff

Status 2026-11-18: all seven `aeterna_*` packages are built on `feat/starter-kit-v0.1`. Local CI passes. Each package was
reviewed by a second model and its findings fixed. The owner's in-game test on the kit-test server is the next step.
Nothing is on `dev` yet. Plan and status table: the owner's plan doc "nakara-oss — Starter Kit".

## Rules for other sessions

- Specs in `docs/specs/` are the contract. `docs/specs/theme.css` is the one source of every `html/theme.css`.
- `.github/scripts/check-kit-graph.mjs` enforces the package edges of ADR 0004 and the identical theme copies.
- Delegate engines cannot run commands here, so the Orchestrator runs busted and the scanners after each patch.
- busted on the Windows heavy host is Lua 5.1; CI and FiveM are 5.4, so a `|` parse error there is a false alarm.

## Open

- In-game smoke of every spec, from the F7 test menu (`aeterna_kit_demo`, kept outside the repo in `.claude/kit-test-server`).
- Not verified in game: `GetInvokingResource` for local events, `SETUP_HEALTH_ARMOUR`, minimap scale range, phone anim
  and prop names, opening an owner stash through `forceOpenInventory`.
- Not done: CI brand scan through the GitHub App, `kits/starter`, site and guides, release tags (wave W4).

## Way back

Nothing reaches `dev` until the owner merges. Dropping `feat/starter-kit-v0.1` removes the packages; PRs #54 and #58 stand alone.

## Log

- W0: ADR 0004, spikes S1 to S3, seven specs.
- W1 to W3 built in one run on the owner's order (2026-11-18), with per-package commits carrying `Delegated-Run` trailers.
