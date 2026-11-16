# Handoff · AETERNA Game Launcher (`launcher/`) and Rongroi Connect 0.1.0

Written by: Claude Code - Claude Opus 5.5 · 2026-11-15 · **Paused by the owner** (resume from "Next, in order")
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
| Connect goes public (K7) | **prepared, owner decides** | Connect #15 (README, SECURITY) · org-standards#138 (draft) |
| Update check wired into the UI (U1) | not started | — |
| Server-owner kit: template repo, profile checker, guide (L8) | not started | — |
| Privacy note G3, rollback plan G4, SmartScreen/Defender test G5, wordmark G6 | not started | — |
| e2e launcher → Connect → Kit, then 0.1.0 of all three together (W3) | not started | — |

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

1. Merge Connect #15 (public text: README, SECURITY).
2. Decide on Connect branch `debug/elevated-stall-trace` (closed PR #5, never merged; delete or keep).
3. Make aeterna/aeterna-rongroi-connect public. Then the Orchestrator sets: a `main` ruleset (PR, the three CI
   checks, no force-push or deletion), a `v*` tag ruleset (no update or delete), immutable releases, secret scanning
   with push protection, private vulnerability reporting, Dependabot security updates, squash-only merges, wiki and
   projects off; then org-standards#138 is merged (not before: tier C engines must not see a private repository).
4. Go-ahead for U1, L8, G3–G6, then W3.

## Next, in order

1. K7 settings after the owner flips visibility (list above), then Connect tag `v0.1.0` → its `release.yml` builds,
   attests and opens a draft pre-release (first real run of the attest and publish jobs).
2. U1: call the signed update check (`launcher-update` + `update_keys`) from the UI.
3. W3: e2e on a Windows PC (launcher → Connect → Kit on a test server); bump `nakara_rongroi` to 0.1.0 with its
   CHANGELOG dated that day; release Kit, Connect and launcher together; remove test files from the PC.
4. G7: close this handoff.

## Rollback

- Launcher: nothing is released yet, so a revert PR on `main` is enough.
- Connect public: visibility can be set back to private, but anything already cloned or cached stays public.
- Update key: if the private key leaks, remove its line from `update_keys` and ship a launcher with a new key;
  launchers that only trust the old key must be replaced by hand (no auto-update has shipped).

## Log

- 2026-11-13: plan, Rust + iced chosen after the GPUI/iced spike, ADR 0002, W1 (#31).
- 2026-11-14: W1b (#32), K4 named-pipe handoff (#37, Connect #10 #11), W1c (#38).
- 2026-11-15: Nakara feed live; W1d (#42); L6 (#43); L7 text fixes (#44); owner created the update key, profile
  trusts it (#45); Connect M3 (Connect #13); K5 (Connect #14, #49); K7 prepared (Connect #15, org-standards#138);
  paused by the owner.
