# Starter Kit v0.1 handoff

Status 2026-11-18: all seven `aeterna_*` packages are built on `feat/starter-kit-v0.1`. Local CI passes. Each package was
reviewed by a second model and its findings fixed. The one-click in-game run on the kit-test server (run 1795015386,
code `b46a157`, FXServer Enhanced build 3788, 1920x1080) gave 42 PASS, 0 FAIL, 4 checks left to the eye.
Nothing is on `dev` yet. Plan and status table: the owner's plan doc "nakara-oss — Starter Kit".

## Rules for other sessions

- Specs in `docs/specs/` are the contract. `docs/specs/theme.css` is the one source of every `html/theme.css`.
- `.github/scripts/check-kit-graph.mjs` enforces the package edges of ADR 0004 and the identical theme copies.
- Delegate engines cannot run commands here, so the Orchestrator runs busted and the scanners after each patch.
- busted on the Windows heavy host is Lua 5.1; CI and FiveM are 5.4, so a `|` parse error there is a false alarm.

## Open

- The owner passed the visual and hand checks on 2026-11-18. Next is the owner's merge of PR #69, which also carries #54 and #58.
- The F7 menu and FULL TEST live in `aeterna_kit_demo`, outside the repo in `.claude/kit-test-server`.
- Verified by the run: layout owner detection
  with every kit part, the phone animation on Enhanced, and opening a stash through `forceOpenInventory`.
- Not done: CI brand scan through the GitHub App, `kits/starter`, site and guides, release tags (wave W4).

## Way back

Nothing reaches `dev` until the owner merges. Dropping `feat/starter-kit-v0.1` removes the packages; PRs #54 and #58 stand alone.

## Log

- W0: ADR 0004, spikes S1 to S3, seven specs.
- W1 to W3 built in one run on the owner's order (2026-11-18), with per-package commits carrying `Delegated-Run` trailers.
- First in-game runs found two bugs the specs could not catch: NUI focus was set from `aeterna_core`, which has no page, and the client has no `os` library. Both are fixed.
