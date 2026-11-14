# Tickets W2 · rework 2 · regressions after rework-1 (runs fa3061 8544d4 3d3ff1 708402 627db8 a3cc9b)

Evidence: vitest 189/216 (27 failed) · `tsc -b` 11 errors · web tsc 0 · safety 0/0 · resource specs pass.
Diagnosed by the reviewer (AGENTS §5.6):
- **24 of the 27** are one cause: R-A changed CSRF to `deriveCsrfToken(dataKey, sessionId)` (HKDF subkey,
  `apps/server/src/session.ts:77`) but the route tests still compute the old token → every write is 403.
- r1/r2: `/metrics` is now 404 without `METRICS_TOKEN` by design.
- `packages/discord/test/archive.test.ts:33` uses `afterEach` without importing it (suite fails to load).
- `close-hooks.test.ts` expects `handleClose` to throw on a missing key; R-D moved that check to startup.
Do not run shell commands; file tools only. Never print connection strings, passwords, tokens or keys.

## RT1 · server tests (owner: tickets/apps/server/test/**)
1. New `test/helpers/session.ts`: `createTestSession(db, config, { userId, username }) → { cookie, csrf }` inserting a
   `sessions` row (token hash as `session.ts` does) and `csrf = deriveCsrfToken(config.TICKETS_DATA_KEY, sessionId)`.
2. Use it in `blocks`, `categories`, `data`, `panels`, `tags`, `tickets`, `transcript`, `privacy`, `session`, `auth`
   tests wherever they build a session/CSRF by hand. No test may recompute CSRF itself.
3. `routes.test.ts` r1/r2: build the app with `METRICS_TOKEN` set (config/env) and send the bearer for `/metrics`; add
   one assertion that without the token `/metrics` is 404.
4. `auto-close.test.ts`: job contexts include `storage: null` (TS2741 ×5). `discord-rest.test.ts:158`: no optional call
   once `getChannel` is required (RT2).

## RT2 · source typing (owner: apps/server/src/{routes/panels.ts,storage.ts,discord-rest.ts,types.ts} and packages/discord/src/storage-client.ts)
1. `routes/panels.ts:9` TS2386 overloads: replace the overload set with one signature.
2. `storage.ts:113` and `packages/discord/src/storage-client.ts:88`: fetch body type — pass
   `new Blob([new Uint8Array(bytes)])` (or an `ArrayBuffer` sliced to the view) so it is `BodyInit`.
3. `DiscordRest.getChannel` is required in the exported type (not optional).
Behavior unchanged.

## RT3 · Discord tests (owner: tickets/packages/discord/test/**)
1. `archive.test.ts`: import `afterEach` from vitest.
2. `close-hooks.test.ts`: assert `startGateway` (or the function that now checks it) rejects when `dataKey` is missing;
   drop the expectation that `handleClose` throws.

## Acceptance
vitest 0 failed (3 runs in a row) · `tsc -b` 0 · web tsc 0.
