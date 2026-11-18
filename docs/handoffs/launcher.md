# Handoff · AETERNA Game Launcher (`launcher/`) and Rongroi Connect

Written by: Claude Code - Claude Opus 5.5 · 2026-11-15 · updated 2026-11-18 (0.1.0 released; only the template repository is left)
Decision record: [ADR 0002](../adr/0002-aeterna-game-launcher.md) · Connect: aeterna/aeterna-rongroi-connect ADR 0001 + 0002
Plan and live status table (owner's doc): https://claude.ai/artifact/RFJoHRcP1JQGxqYDSXUuJ3

## Status now

| Piece | State | Evidence |
|---|---|---|
| Launcher core, Thai line breaks, Dusk/Classic Home (W1) | merged | #31 `914af45` |
| Network gate + feed, signed updates, join targets, Connect handoff (W1b) | merged | #32 `1cf6489` |
| Code to Connect over a named pipe (K4) | merged | #37 `1ac91a7` · Connect #10 #11 |
| HTTP client (`launcher-http`), real Home data, working buttons (W1c) | merged | #38 `8ad2fbf` |
| Dusk news, Rongroi Connect button, Connect bundled at `<launcher>/rongroi-connect/` (W1d) | merged | #42 `57e8720` |
| Release workflow `launcher-release.yml`, `launcher-sign`, `update_keys` (L6) | merged | #43 `38cf9f8` |
| Text review G1–G8: no dead controls or sample data (L7, owner approved) | merged | #44 `9a83b5e` |
| AETERNA profile trusts its update key (`fcbcbdd4…db8a58`) | merged | #45 `dfdf669` |
| Launcher release looks for Connect's zip by its released name, attested by Connect's release workflow | merged | #49 `5c7c868` |
| Nakara feed `/api/launcher/v1` (status, hours, players; news empty in v1) | live on Nakara's site | — |
| Connect: release zip + `SHA256SUMS` + attestation; CI uses the released `rongroi-scan` 0.15.0 (K5) | merged in Connect | Connect #14 `4855b3e` |
| Connect: IPv6 measured on Windows with a test route, 0 packets (M3); owner accepted it for 0.1.0 | merged in Connect | Connect #13 `0ac0a71` |
| Connect goes public (K7); its first published release is `v0.1.1` (`v0.1.0` stayed an unpublished draft and was deleted; the tag remains) | done | Connect #15 `8a8c021` · org-standards#138 `732e576` |
| Update check wired into the UI: notify only, link to the release page (U1) | merged | #52 `1b16577` |
| Server-owner kit: profile checker, guide (L8) | merged | #57 `f185a8b` · #56 `5261966` |
| Privacy note G3, rollback plan G4 | merged | #56 `5261966` |
| `time` 0.3.47 (Dependabot alerts 1, 2, 4, 5) | merged | #55 `b5f6502` |
| SmartScreen/Defender test G5: no warning on the owner's PC; CI artifact keeps the exe | done | #59 `6f917d0` |
| Wordmark G6 (AETERNA chibi, owner picked A2) | merged | org-standards#150 `391270d` |
| e2e launcher → Connect → Kit on the test server | passed 2026-11-17 | server log `report received 7eb76b1f…` at 03:59:26Z |
| Connect 0.1.1: the opened "See what will be sent" stays open across the countdown redraw (owner re-tested) | released, pre-release | Connect #19 `79875e6` · run 44061304358 |
| Kit `nakara_rongroi@0.1.0` | released | #60 `11770ea` · #62 `6a67f15` on `dev` · run 44095977445 |
| Launcher `launcher-v0.1.0`, bundles Connect v0.1.1; assets, attestations and manifest signature checked | released | run 44095983570 |
| Test files on the Windows PC | removed, except the old Kit copy (owner decides) | `C:\rongroi-w2-enh\nakara_rongroi.moved-20261117-104302` |
| Owner template repository (L8) | not created | draft on the maintainer's external drive |

## Short rules for other sessions

- Build with `cargo +1.98.1`; keep `CARGO_TARGET_DIR` off the repository (the maintainer uses an external drive).
  Windows checks: `cargo xwin clippy --target x86_64-pc-windows-msvc`. Pushing `feat/launcher-*` runs `launcher.yml`.
- `launcher/assets/**` is the only place binaries may live (AGENTS rule 4). Every player-visible string goes through
  the owner's text review (L7) before merge.
- The update signing key's private half never touches an agent or a log. It lives offline with the owner and in the
  GitHub environment secret `LAUNCHER_SIGNING_KEY` (environment `launcher-release`, owner as reviewer, `main` only).
  `launcher-sign` reads the key from the environment only and prints only the public key. Rotating it = new key from
  the owner + a PR that changes `update_keys` in `profiles/aeterna/server.toml` (up to 4 keys).
- A launcher release needs a **public, attested** Connect release (`rongroi-connect-<version>-windows-x64.zip`):
  `launcher-release.yml` refuses a Connect zip without Connect's attestation for that tag. So K7 comes before any
  launcher release.
- Connect's sidecar is pinned in Connect's `sidecar.lock.json` (rongroi `v2026.11.13-0.15.0`). A new rongroi
  release = change the lock (tag, asset, SHA-256, commit) in a Connect PR; CI checks it against the release's
  `SHA256SUMS` and attestation.

## Owner's queue

1. Decide whether to keep `C:\rongroi-w2-enh\nakara_rongroi.moved-20261117-104302` on the Windows PC.
2. Go-ahead to create the public owner template repository from the draft, pinned to `launcher-v0.1.0`.

## Next, in order

1. Create the template repository (needs the external drive mounted and item 2 above).

## Rollback

- Launcher: released, so `docs/maintainers/launcher-release.md` §When something goes wrong applies. Releases are
  immutable and tags are protected: a bad version is replaced by a newer one.
- Connect public: visibility can be set back to private, but anything already cloned or cached stays public.
- Update key: if the private key leaks, remove its line from `update_keys` and ship a launcher with a new key;
  launchers that only trust the old key must be replaced by hand (the launcher only notifies; it does not install).

## Log

- 2026-11-13: plan, Rust + iced chosen after the GPUI/iced spike, ADR 0002, W1 (#31).
- 2026-11-14: W1b (#32), K4 named-pipe handoff (#37, Connect #10 #11), W1c (#38).
- 2026-11-15: Nakara feed live; W1d (#42); L6 (#43); L7 text fixes (#44); owner created the update key, profile
  trusts it (#45); Connect M3 (Connect #13); K5 (Connect #14, #49); K7 prepared (Connect #15, org-standards#138);
  paused by the owner.
- 2026-11-16: K7 done, Connect public, `v0.1.0` attested draft (Connect #15, org-standards#138); U1 opened (#52).
- 2026-11-17: U1 merged (#52 `1b16577`); W2 lanes in parallel: `time` 0.3.47 (#55), profile-check (L8), docs G3/G4/L8.
- 2026-11-17: W2 merged (#55 #56 #57 #59, org-standards#150); W3 e2e passed; Connect details fix + 0.1.1 (Connect #19);
  Kit 0.1.0 (#60, back on `dev` by #62).
- 2026-11-18: released Connect v0.1.1, Kit `nakara_rongroi@0.1.0`, `launcher-v0.1.0`; test files removed from the PC.
