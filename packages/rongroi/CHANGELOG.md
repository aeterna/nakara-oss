# Changelog

All notable changes to `nakara_rongroi` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- Envelope v1 crypto in `server/js/envelope.js` (X25519, HKDF-SHA256, AES-256-GCM; Node `crypto` only) and
  the shared test-vector file `test-vectors/envelope-v1.json`.
- Start-up self-test (`server/js/selftest.js`) that checks the vectors once and prints one line.
- `oss.json` capability manifest declaring no capabilities.

### Fixed

- Start-up self-test now loads `envelope.js` on FXServer, whose `require()` resolves against the resource root
  rather than the requiring file, and `envelope.js` no longer assumes a CommonJS `module` when loaded as a
  `server_script`.
