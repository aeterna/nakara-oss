# Handoff — Rongroi easy plug-in and release 0.2

Status: **closed** 2026-11-22. Plan and status table: Claude artifact `1DX1TpQ6EXf2vixS6dbB26` (v1.3, owner's account).
Written by Claude Code - Claude Opus 5.5.

## Now

| Piece | Where | Version |
|---|---|---|
| Server Kit `nakara_rongroi` (relay client, `rr2.` codes, envelope v2, server.cfg settings, `rongroi doctor`, A0) | `packages/rongroi` | [`nakara_rongroi@0.2.0`](https://github.com/aeterna/nakara-oss/releases/tag/nakara_rongroi%400.2.0) |
| Rongroi Relay (self-hosted HTTPS drop box, Dockerfile + Caddy compose + `keygen`) | `relay/` | source on `main` (no image) |
| SDK `@aeterna_game/rongroi-envelope` (MIT, shared vectors) | `sdk/rongroi-envelope` | 0.1.0, private, not on npm |
| Launcher (hands `rr2.` codes to Connect, exit 17, ships `launcher-sign`) | `launcher/` | [`launcher-v0.2.0`](https://github.com/aeterna/nakara-oss/releases/tag/launcher-v0.2.0), stable, manifest expires **2027-02-20** |
| Rongroi Connect | aeterna/aeterna-rongroi-connect | [v0.2.0](https://github.com/aeterna/aeterna-rongroi-connect/releases/tag/v0.2.0) |
| Launcher template | aeterna/aeterna-launcher-template | `LAUNCHER_REF` = `a0debac5` (launcher-v0.2.0) |
| Owner quickstart (TH/EN) | aeterna/aeterna-rongroi `docs/server-quickstart*.md` | on `dev` |
| `nakara_tickets` bridge over `https.request` (same FXServer bug) | `packages/tickets` | [`nakara-tickets@0.1.1`](https://github.com/aeterna/nakara-oss/releases/tag/nakara-tickets%400.1.1) |

Decisions behind it: aeterna-rongroi ADR 0097, Connect ADR 0003, Kit ADR 0001 §14 (amended 2026-11-22 for
`rongroi_server_name`). AETERNA runs no Relay; Nakara City stays direct and still vendors Kit 0.1.

## Rules for other sessions

- A Kit with no relay convars issues `rr1.` codes, so Connect 0.1.x keeps working. Relay mode needs Connect ≥ 0.2.0.
- Server-side HTTP from FXServer JS goes through Node `https.request`, never `fetch()`: every `fetch()` POST with a
  body logs `Unhandled promise rejection … Reader released` on b177 (6/6 measured; GET and `https.request` 0/6;
  `PerformHttpRequest` is undefined in server JS). Reuse `packages/rongroi/server/js/relay-http.js`
  (or `packages/tickets/server/js/http-request.js`). Write `const https = require('https')` plainly: a guarded
  require hides the destination from `fivem-devkit safety`.
- Opening a case needs a public origin and a server name. The name comes from the Policy screen, else
  `rongroi_server_name`, else `sv_projectName`; staff need the ACE `nakara_rongroi.staff`.
- Test with the automated live E2E before asking the owner to click: scripts and README in
  `nakara-oss/.claude/kit-test-server/rongroi-e2e/` (outside git). It drives the Connect **test** build
  (`CONNECT_TEST_CODE` auto-consents, real sidecar); a release build has no test hook.
- Release order: Connect published first (launcher-release downloads its zip, SHA256SUMS and attestation) → nakara-oss
  promotion dev→main → `release.yml` package=rongroi → `launcher-release` (`connect_tag`) → template `LAUNCHER_REF`.
  Connect's release.yml drafts as a pre-release; untick it when publishing a normal release.

## Waiting on the owner

- Discord post for 0.2 (the drafted text is in the session; #releases and #announcements are locked to the bot).
- Delete or keep: rejected delegate run `20261121-215311-9530e0` (worktree + branch; `closeout` has no merge proof)
  and the throwaway Connect branches `test/rr2-build` (remote) and `test/rr2-testbuild` (local + remote).
- Re-release the launcher before 2027-02-20 (manifest expiry).
- Deferred: winget, sidecar-bump CI, Rust SDK crate, rongroi site page, Discord bot, npm publish of the SDK, a ghcr
  image for the Relay, Nakara City vendor bump to Kit 0.2 (separate work in nakara-city).

## Way back

- Kit: install `nakara_rongroi@0.1.0` again; KVP keys are the same (the resource name never changed). Cases made by
  0.2 in relay mode cannot be finished by 0.1.
- Connect / launcher: the 0.1.x releases stay published; tags are immutable, a fix is a new patch version.

## Residue on test servers (pik-windows)

- kit-test and rongroi W2 Legacy hold `nakara_rongroi` KVP from test cases (`e2e-*`). A later Kit install there shows
  the "stored reports are missing" banner; remove the entries from the panel.
- `aeterna-kit-db` was started after a reboot on 2026-11-22 and left running for kit-test.

## Log

- 2026-11-21: plan; owner answered Q1–Q7 and R1–R6 as recommended; W0 ADRs merged (rongroi#312, connect#20, #96).
- 2026-11-21: A0 (#98, engineer runs 9f0006 + 8e3ee7); owner allowed self-write for the rest of the plan.
- 2026-11-22: combined live test. Automated E2E direct + relay passed on Enhanced (kit-test) and Legacy; launcher →
  Connect passed by hand. Found and fixed: `fetch()` POST rejection (6b4f5502), server name only on the Policy screen
  (6bcada33). Q3 by Sonnet, four rounds.
- 2026-11-22: merged #98 → #101, connect#21, rongroi#313; closeout.
- 2026-11-22: release 0.2 — #102, connect#24, promotion #103, Connect v0.2.0, `nakara_rongroi@0.2.0`, `launcher-v0.2.0`,
  template#1, catalog #104 + promotion #105.
- 2026-11-22: tickets fix #106 (separate session), `nakara-tickets@0.1.1` (#107, promotion #108), catalog #109 +
  promotion #110.
