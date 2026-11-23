# Changelog

All notable changes to `nakara_rongroi` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

## [0.2.0] - 2026-11-22

Easy adoption (aeterna-rongroi ADR 0097, Kit ADR 0001 section 14). A Kit with no relay convars still issues `rr1.`
codes, so players on Rongroi Connect 0.1.x keep working; the relay transport needs Connect 0.2.0 or later.

### Added

- Settings from `server.cfg`, all server-only (`set`, never `setr`): `rongroi_public_origin`, `rongroi_relay_url`,
  `rongroi_relay_id`, `rongroi_relay_key` and `rongroi_server_name` (else `sv_projectName`). The panel shows a value
  that comes from `server.cfg` read-only; the relay key shows only "set".
- Relay transport: with the three relay convars set the Kit issues `rr2.` codes bound to the Relay, registers each
  ticket with its exact policy bytes, pulls the encrypted envelopes Connect stored there, verifies them itself and
  posts a result per envelope. Lost requests, a restarted Relay and an unreachable Relay are retried; deleting a case
  also deletes what the Relay holds for it. The Kit needs no inbound port in this mode.
- Envelope v2 (`"v":2`), bound to the pairing code through the AEAD's associated data (base path, policy hash, server
  origin, ticket, transport); `rr1.` codes accept only v1 and `rr2.` codes only v2. Shared vectors in
  `test-vectors/envelope-v2.json`.
- `rongroi doctor` (server console): edition and storage, public origin, server name, relay reachability and key,
  stored-report check. It never prints the relay key.
- Enhanced keeps a stored-report count in KVP (`rongroi:filestore:entries`). At start-up the Kit logs one line when
  reports are missing, for example after the folder was replaced without `cache/`, and the staff panel shows a
  banner with a button that removes the missing entries (`nakara_rongroi:panel:forgetMissing`).

### Fixed

- A fresh install can open a case with no panel step: the server name comes from the Policy screen, else
  `rongroi_server_name`, else `sv_projectName`. The "set the server name" message now says where (the Policy screen;
  the Settings screen has no such field), and `rongroi doctor` checks it.
- Relay requests go through Node's `https.request`, not `fetch()`: on FXServer every `fetch()` POST with a body logged
  `Unhandled promise rejection ... Reader released` although it succeeded (measured on a test server, 2026-11-22).
- The missing-reports warning counts only lost index entries, not case files that read null. A later write keeps a
  start-up loss in the stored count until staff remove the missing entries.

## [0.1.0] - 2026-11-17

### Added

- Envelope v1 crypto in `server/js/envelope.js` (X25519, HKDF-SHA256, AES-256-GCM; Node `crypto` only) and
  the shared test-vector file `test-vectors/envelope-v1.json`.
- Start-up self-test (`server/js/selftest.js`) that checks the vectors once and prints one line.
- Single-use tickets, the Kit key pair and the `rr1.` pairing code.
- HTTP handler: policy read, direct and chunked report upload, rate limits, wired into FXServer.
- `exports.nakara_rongroi:api(1)`: `openCase`, `getCase`, `listCases`, `deleteCase`, `deletePlayerData` and
  `getPairingCode`.
- Report storage: KVP on Legacy, two-slot files in `cache/rongroi-reports/` on Enhanced.
- Retention sweep at start and hourly, 1 to 365 days, default 30.
- `oss.json` capabilities: `httpHandlers`, the `gamename` convar read, `files.write`, the `rongroi` command,
  the server/client net events and NUI.
- Staff panel and settings wiring in `server/js/main.js`: the `/rongroi` command, the eight client-to-server
  net events and the three server-to-client replies, with every handler going through `server/js/panel.js`.
- Client shell forwards the panel NUI callbacks (`openCase`, `selectCase`, `saveSettings`, `savePolicy`,
  `deleteCase`) to their server events; `fxmanifest.lua` declares the NUI page.

### Changed

- Retention deletes through the panel's `deleteCaseAndForget`, so a removed case's ticket is forgotten too.
- Key rotation is wired to the resource KVP adapter.

### Fixed

- Start-up self-test now loads `envelope.js` on FXServer, whose `require()` resolves against the resource root
  rather than the requiring file, and `envelope.js` no longer assumes a CommonJS `module` when loaded as a
  `server_script`.
