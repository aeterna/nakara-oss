# Changelog

All notable changes to `nakara_tickets` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

## 0.1.1 - 2026-11-22

### Fixed

- Bridge calls (pair, heartbeat, action result, actions poll) use Node `https.request` / `http.request` instead of
  `fetch()`, with a 35 s whole-request timeout and a 1 MiB answer cap. On FXServer every `fetch()` POST with a body logged
  `Unhandled promise rejection ... Invalid state: Reader released` although it succeeded (26 of 26 POSTs on a test
  server, 2026-11-22; 0 after the change). Redirects are no longer followed.

## 0.1.0 - 2026-11-21

### Added

- Initial release of `nakara_tickets` game bridge resource.
- Outbound signed HTTP client (`signer.js`, `api.js`) using global `fetch` and HMAC-SHA256 authentication.
- Credential and action execution deduplication storage (`store.js`) using KVP.
- Console pairing command (`pairing.js`) with `nakara_tickets pair <code>`, `status`, and `unpair`.
- Built-in action execution handlers (`actions.js`) for `player.info` and `player.teleport`.
- Built-in action execution handlers for `player.revive` (via `qbx_medical`) and `player.give_item` (via `ox_inventory`) with allowlist and quantity caps.
- Custom action registration export `exports('registerAction', ...)`.
- Long-poll worker and periodic heartbeat loop (`main.js`).

### Fixed

- Action execution player validation, loader dependency resolution, and long-poll reader cleanup.

- Validate give_item allowlist using Object.hasOwn and enforce positive integer caps.
- Base64url secret decoding in `signer.js` to match bridge API HMAC key representation.
- Global export function resolution in CommonJS module `actions.js` using `globalThis.exports`.
- Teleport error reporting when player ped cannot be located or is 0.
- Outbound HTTP folding in `api.js` and capability declaration in `oss.json`.
- In-memory execution cache pruning in `store.js`.
- Polling error resilience and result retry capping in `main.js`.

### Known issues

- FXServer's embedded Node (v26.3.0 on Enhanced) logs `Uncaught TypeError: Invalid state: Reader released` for every
  `fetch` that sends a request body, so the console shows it at pairing and on each heartbeat (every 30 s). The request
  and its response complete normally; requests without a body do not log it. Measured on a live server 2026-11-21.
