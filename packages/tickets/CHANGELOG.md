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
- Custom action registration export `exports('registerAction', ...)`.
- Long-poll worker and periodic heartbeat loop (`main.js`).
