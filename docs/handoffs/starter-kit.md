# Starter Kit v0.1 handoff

Status 2026-11-18: **released.** All seven `aeterna_*` packages are published as `0.1.0` from `main`, with checksums and
build attestations verified after publishing. The published zips were then installed on the clean kit-test server and
passed the in-game full test. There is no open work on this release.

## Rules for other sessions

- Specs in `docs/specs/` are the contract. A breaking change to a released contract is a new major version.
- `docs/specs/theme.css` is the one source of every `html/theme.css`; `.github/scripts/check-kit-graph.mjs` enforces that
  and the package edges of ADR 0004.
- The `brand scan` CI job reads a hashed list from a private repo. Rebuild that list when a private resource is added.
- Delegate engines cannot run commands here, so the Orchestrator runs busted and the scanners after each patch.
- busted on the Windows heavy host is Lua 5.1; CI and FiveM are 5.4, so a `|` parse error there is a false alarm.
- FiveM client Lua has no `os`, and `SetNuiFocus` acts on the calling resource. Both caused real bugs that specs missed.
  Run the kit in game before a release.

## Evidence

- In-game full test on the published zips: 42 passed, 0 failed, 4 checks by eye (run 1795019605, FXServer Enhanced game
  build 3788, 1920x1080). The owner passed the visual and hand checks on the same code before release.
- The test menu is not part of the kit. It and the run results stay with the maintainer, outside the repo.
  Changed for 0.2 (owner, 2026-11-21; ADR 0005 decision 7): the menu becomes the public package `aeterna_testkit`.
  The maintainer's run scripts for the kit-test server and the run results still stay outside the repo.
- Releases: `aeterna_core`, `aeterna_uikit`, `aeterna_layout`, `aeterna_notify`, `aeterna_invkit`, `aeterna_hudkit` and
  `aeterna_phonekit`, each `@0.1.0`.

## For the next version

- Not proven in game: hiding the base health and armour bars by every route, and the edges of the minimap scale range.
  The owner saw no problem; measure them before changing that code.
- Follow-up ideas stay out of 0.1: phone calls and messages, voice indicators, a round minimap.

## Way back

Withdraw a bad package by marking its GitHub release as withdrawn and publishing a fixed patch version. Tags stay.

## Log

- W0: ADR 0004, spikes S1 to S3, seven specs.
- W1 to W3: built in one run, reviewed per package by a second model (#69).
- W4: brand scan, `kits/starter`, guides, site, promotion and releases (#70, #71).
- Closeout: docs marked released (#72, #73); published zips passed the full test.
