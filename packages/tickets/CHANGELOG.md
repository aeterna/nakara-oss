# Changelog

All notable changes to `nakara_tickets` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

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

- Base64url secret decoding in `signer.js` to match bridge API HMAC key representation.
- Global export function resolution in CommonJS module `actions.js` using `globalThis.exports`.
- Teleport error reporting when player ped cannot be located or is 0.
- Outbound HTTP folding in `api.js` and capability declaration in `oss.json`.
- In-memory execution cache pruning in `store.js`.
- Polling error resilience and result retry capping in `main.js`.
