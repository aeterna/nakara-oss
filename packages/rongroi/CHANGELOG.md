# Changelog

All notable changes to `nakara_rongroi` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

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
