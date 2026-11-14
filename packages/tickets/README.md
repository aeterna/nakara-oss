# nakara_tickets

FiveM game bridge for Nakara Tickets. Connects an FXServer instance to a Nakara Tickets Discord bot / API instance over outbound HTTP.

See [ADR 0003](../../docs/adr/0003-nakara-tickets.md) for architecture and protocol design.

## Features

- Outbound-only HTTP long-polling over global `fetch` (no open server ports, works behind proxies).
- One-time console pairing via `nakara_tickets pair <code>` (`source == 0` enforced).
- HMAC-SHA256 request signing with nonce replay prevention and timestamp skew protection.
- Built-in actions: `player.info` and `player.teleport`.
- Action extensibility via `exports.nakara_tickets:registerAction(name, schema, fn)`.
- In-memory and KVP action deduplication (repeated actions return previous result without re-execution).

## Configuration

`config.json`:
- `enabledActions`: list of allowed action names (`player.info`, `player.teleport`).
- `teleportSpots`: map of named locations `{ "hospital": { "x": ..., "y": ..., "z": ... } }`.
- `logPrefix`: prefix for console messages.

Convars:
- `nakara_tickets_api`: Base URL of the Nakara Tickets API server (e.g. `https://tickets.example.com`).
