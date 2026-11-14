# nakara_tickets

FiveM game bridge for Nakara Tickets. Connects an FXServer instance to a Nakara Tickets Discord bot / API instance over outbound HTTP.

See [ADR 0003](../../docs/adr/0003-nakara-tickets.md) for architecture and protocol design.

## Features

- Outbound-only HTTP long-polling over global `fetch` (no open server ports, works behind proxies).
- One-time console pairing via `nakara_tickets pair <code>` (`source == 0` enforced).
- HMAC-SHA256 request signing with nonce replay prevention and timestamp skew protection.
- Built-in actions: `player.info`, `player.teleport`, `player.revive`, and `player.give_item`.
- Action extensibility via `exports.nakara_tickets:registerAction(name, schema, fn)`.
- In-memory and KVP action deduplication (repeated actions return previous result without re-execution).

## Built-in Actions

| Action | Required Resource | Exact Framework Call | Description |
|---|---|---|---|
| `player.info` | Standalone (`qbx_core` optional) | `exports.qbx_core.GetPlayer(playerId)` (optional) | Retrieves online player info (name, ping, coords, job). |
| `player.teleport` | Standalone | `SetEntityCoords(ped, x, y, z, ...)` | Teleports player to configured spot from `teleportSpots`. |
| `player.revive` | `qbx_medical` | `exports.qbx_medical.Revive(playerSrc)` | Revives player when downed or dead. Off by default. |
| `player.give_item` | `ox_inventory` | `exports.ox_inventory.CanCarryItem` then `exports.ox_inventory.AddItem` | Gives an allowed item up to configured max count. Off by default. |

Under repo hard rule 5, `qbx_medical` and `ox_inventory` are touched only when `GetResourceState` returns `'started'` and the action is enabled in `config.json`. Neither is listed as a resource dependency.

## Configuration

`config.json`:
- `enabledActions`: list of allowed action names (e.g. `["player.info", "player.teleport"]`). `player.revive` and `player.give_item` are off by default.
- `teleportSpots`: map of named locations `{ "hospital": { "x": ..., "y": ..., "z": ... } }`.
- `giveItem`:
  - `allow`: map of allowed item names to their maximum allowable count per action, e.g. `{ "bandage": 5, "water": 10 }`. Empty `{}` by default.
- `logPrefix`: prefix for console messages.

Convars:
- `nakara_tickets_api`: Base URL of the Nakara Tickets API server (e.g. `https://tickets.example.com`).
