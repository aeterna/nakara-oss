# Tickets W1 · L4 · game bridge: resource `nakara_tickets` and `/bridge/v1`

**Route:** agy:B · **Gate:** G1 ✅ Pik 2026-11-14 · also read `tickets-w1-common.md` · ADR 0003 decisions 8–10 ·
spike evidence `tickets/spike/README.md` on branch `spike/tickets-bridge` (not in this tree; facts are in ADR decision 8)

## Goal
A game server pairs once from its console, then polls the API for actions over signed outbound `fetch` and runs
`player.info` and `player.teleport`; other resources add actions through an export.

### API (`tickets/apps/server/src`)
1. `bridge/auth.ts`: `installBridgeAuth(app, { db, dataKey })` decorates `app.requireBridge` preHandler. Reads the
   five `X-Tickets-*` headers, loads the `game_servers` row (not revoked), opens `secret_enc` with `openBytes`,
   calls `verifyBridge` from `@nakara-tickets/core` over the **raw body bytes**; inserts the nonce into
   `bridge_nonces` (expires now+120 s) with `ON CONFLICT DO NOTHING` and refuses when nothing was inserted
   (`replay`). 401 `{ code: 'unauthorized' }` for every failure (no detail leak); sets `req.gameServer`.
   Deletes expired nonces at most once a minute. Raw body: a JSON content-type parser with `parseAs: 'buffer'`
   registered inside the bridge route plugin only.
2. `routes/bridge.ts` (replace stubs, ops postBridgePair, postBridgeHeartbeat, getBridgeActions, postBridgeActionsResult):
   - pair: no HMAC; in-memory limit 10 requests / minute / address → 429. Looks up `pair_codes` by
     `sha256(code)`, unused and unexpired, sets `used_at`, creates `game_servers` (confirmed false, secret = 32
     random bytes sealed with `sealBytes`, name, edition, resource_version, protocol); returns PairResponse.
     A used or expired code → 400 `invalid` (same message for both).
   - heartbeat: updates `last_seen_at`, `players_online`, `edition`; keeps the player list in memory per server
     (`getOnlinePlayers(serverId)` exported for later use).
   - actions: `wait` 0–25 s. Loop every 1 s until the deadline: one `UPDATE … WHERE id = (SELECT … FOR UPDATE SKIP LOCKED)`
     that leases the oldest action for this server that is `queued`, or `leased` with `lease_until < now()`, and
     not past `expires_at` (lease 30 s). Actions past `expires_at` become `expired`. Return `{ action: null }` at
     the deadline. Only a `confirmed` server receives actions.
   - result: first result sets `done` (ok) or `failed` and `result`; the same result again → 200; a different
     one → 409 `conflict`. Write an `audit_log` row; posting a line into the ticket is W2.
3. `routes/game-servers.ts` and `routes/actions.ts` (replace stubs): use `app.requireStaff` (L3 decorator; in tests
   install a fake that sets `req.guildId` and `req.user`). Pair code = 10 chars Crockford base32 (50 bits),
   stored as hash, 10 min, returned once. patch → rename / confirm; delete → revoked = true. postTicketAction
   queues a `game_actions` row (expires now+60 s) for the server linked to the ticket's category; 422 when the
   category has no game server. getTicketActions lists them.

### Resource (`packages/tickets`, resource name `nakara_tickets`)
4. `fxmanifest.lua` (server JS only, `server/js/main.js`), `oss.json`, `README.md`, `CHANGELOG.md`, `config.json`
   (`enabledActions: ["player.info","player.teleport"]`, `teleportSpots: { "hospital": {x,y,z} ... }`, `logPrefix`),
   `package.json` (`@aeterna_game/nakara-tickets`, private, commonjs, `"test": "node --test \"spec/**/*.test.js\""`,
   no dependencies) and `spec/`.
5. `server/js/` (commonjs, `require('node:crypto')` only):
   - `signer.js`: same canonical string and HMAC as `tickets/packages/core/src/hmac.ts` (copy the logic; the
     resource cannot import from `tickets/`), headers incl. `X-Tickets-Protocol: 1`.
   - `api.js`: `const API = GetConvar('nakara_tickets_api', '')` read once into a `const`, every URL built as
     `API + '/bridge/v1/…'` (no template literal, no `new URL`, no `.replace`, no options object for the URL —
     `packages/devkit/src/safety/jsscan.js` folds only that form). Uses global `fetch`, never `PerformHttpRequest`.
     Judges success by a body that parses and has the expected fields, never by status alone.
   - `store.js`: server id and secret in `SetResourceKvp` / `GetResourceKvpString`; executed action ids with their
     results in memory plus a KVP list trimmed to the last 120 s.
   - `pairing.js`: `RegisterCommand('nakara_tickets', handler, true)`; subcommands `pair <code>`, `status`,
     `unpair`; refuses unless `source === 0` (console). Never prints the secret.
   - `actions.js`: built-ins `player.info` (name, ping, coords, `qbx_core` job if `GetResourceState('qbx_core') === 'started'`)
     and `player.teleport` (`params.spot` must be a key of `teleportSpots`; else `not_allowed`). Player found by the
     `discord:` identifier; none → `player_offline`. An action not in `enabledActions` → `not_allowed`.
     `exports('registerAction', (name, schema, fn) => …)` adds custom actions (name pattern as ActionRequest).
     A repeated action id returns the stored result without running again.
   - `main.js`: heartbeat every 30 s; poll loop `GET actions?wait=25` → run → `POST result` retried with backoff
     (1, 2, 4 … 30 s) until accepted; on network error wait 5 s; stops when unpaired.
6. Root `package.json`: add `"packages/tickets"` to `workspaces` (the reviewer regenerates the lockfile and CI step).

## Acceptance tests — write first
API (Fastify inject + pglite): b1 pair with a valid code → serverId + secret, code unusable after; b2 expired code →
400; b3 signed heartbeat ok; wrong signature → 401; same nonce twice → second 401; skew 61 s → 401; b4 actions:
queued action leased once, second poll gets null, after lease expiry the same id comes back; unconfirmed server gets
null; b5 result idempotent: same twice 200, different 409; b6 staff creates pair code, response has 10 chars, DB has
only the hash.
Resource (`packages/tickets/spec/`, node --test, FiveM natives stubbed on `globalThis`): r1 signer output equals a
literal vector also used in `tickets/packages/core/test/hmac.test.ts` (h1 input); r2 pair refused when source ≠ 0;
r3 teleport to an unknown spot → not_allowed, natives not called; r4 action not enabled → not_allowed; r5 repeated id
returns stored result, handler called once; r6 non-JSON 200 body counts as failure.

## Scope
`tickets/apps/server/src/bridge/*` · `tickets/apps/server/src/routes/{bridge,game-servers,actions}.ts` ·
`tickets/apps/server/test/{bridge,game-servers}.test.ts` · `packages/tickets/**` · `package.json` (root, workspaces line only)

## Out of scope
`player.revive`, `player.give_item`, the repeat-confirm rule (W2); posting results into Discord (W2); `.github/`.
