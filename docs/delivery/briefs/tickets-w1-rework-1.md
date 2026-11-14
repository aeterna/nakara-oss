# Tickets W1 · rework 1 · every failure found after merging L1 L2 L4 L5

**Route:** agy:B · one brief, one run per lane (each run fixes only its own section, inside its own Scope).
Evidence: reviewer merged runs afc8d0 (L1), 3253d2 (L2), 96e599 (L4), dda536 (L5) on `feat/tickets-w1`, ran
`npx vitest run` in `tickets/` (77 tests, 14 failed), `npx tsc -b` (11 errors), `fivem-devkit safety` (8 errors), and a
Q3 review by another model. Read `tickets-w1-common.md` again. Do not run shell commands; file tools only. Never print
connection strings, passwords, tokens or keys.

## Shared root causes (diagnosed by the reviewer)
- **bytea comes back as `Uint8Array` from pglite** (and may from other drivers), so `openBytes` (requires `Buffer`)
  throws → bridge auth returns 401 on every request (instrumented: the `openBytes` catch branch fires).
  Fix in L1: `packages/db/src/schema.ts` `bytea` customType gets `fromDriver: (v) => Buffer.from(v as Uint8Array)`
  and `toDriver: (v) => v`. No migration change.
- **`eq` is not exported by `@nakara-tickets/db`.** Import `eq`, `and`, … from `drizzle-orm` everywhere.

## L1 (core + db) — scope adds `tickets/packages/db/src/schema.ts`
1. bytea fix above.
2. `queries/tickets.ts:196` passes the DB row to `nextState`, which reads `claimerId` → unclaim/transfer always
   `not_claimer`, close keeps `undefined`. Map `{ status: row.status, claimerId: row.claimer_id }`. Add tests:
   unclaim by claimer ok, by other → not_claimer; transfer with/without target.
3. `openTicket` races: take `pg_advisory_xact_lock(hashtextextended('nt-open:' || guild_id, 0))` at the start of the
   transaction so number and per-user limit are serialized; map unique violation `23505` to a retry once.
4. `transitionTicket`: `SELECT … FOR UPDATE` inside a transaction (or conditional UPDATE on the old status).
5. `test/queries.test.ts:276,312` import `eq` from `drizzle-orm`.

## L2 (discord)
1. **Delete the duplicates** `src/core-bridge.ts` and `src/db-bridge.ts` (write them as empty is not enough: remove
   every import of them and write each file's content as a single line `export {};` — the reviewer deletes them).
   Import `isStaff` from `@nakara-tickets/core` and `openTicket`, `transitionTicket`, `getCategory`,
   `getTicketByChannel`, `appendMessage`, `TicketError`, `TicketsDb` from `@nakara-tickets/db` directly. No
   `(pkg as any).x` feature detection.
2. `handlers/open.ts:3` imports `eq` from `@nakara-tickets/db` → `drizzle-orm`.
3. `test/test-db.ts:13` reads `tickets/db/migrations/0000_init.sql` (does not exist). Resolve from the test file:
   `new URL('../../db/migrations/', import.meta.url)` and apply every `*.sql` in name order (drizzle's
   `--> statement-breakpoint` separators split statements).
4. Defer first: in `handlers/ticket-actions.ts` and `open.ts` call `deferReply({ ephemeral: true })` before any DB
   read; catch `TicketError` and `editReply` with the i18n text for its code; unknown errors → generic text + log.

## L4 (bridge + resource) — scope adds `packages/tickets/spec/**`
1. **Blocker — HMAC key mismatch.** The pair response secret is base64url text; the resource signs with the utf8 of
   that text while the API verifies with the 32 raw bytes. In `server/js/signer.js` (and wherever the key is used)
   use `Buffer.from(secret, 'base64url')`. Add a test that runs pair → sign exactly as the resource does → API accepts
   (server test b7: take `secret` from the pair response, sign with `Buffer.from(secret,'base64url')`). Resource spec
   r1 must sign with a base64url secret decoded the same way.
2. **Blocker — pairing race.** `routes/bridge.ts:83-97`: one transaction:
   `UPDATE pair_codes SET used_at = now() WHERE code_hash = $1 AND used_at IS NULL AND expires_at > now() RETURNING *`,
   then insert `game_servers`. Normalise the code before hashing (uppercase, Crockford I/L→1, O→0) on both create and
   pair; hash only the normalised form.
3. **Blocker — fail-open staff routes.** `routes/game-servers.ts:35-39` and `routes/actions.ts`: if
   `app.requireStaff` is missing, respond 500 `{code:'misconfigured'}`; never call the handler. Use
   `preHandler: (req, reply) => app.requireStaff(req, reply)` typed via L3's declaration (`declare module 'fastify'`
   `requireStaff(req, reply): Promise<void>` — declare it in `src/bridge/staff-types.ts` too if missing so tsc passes).
4. **Blocker — safety scan.** `node packages/devkit/bin/fivem-devkit.js safety` reports 8 `undeclared-http`:
   `api.js` reuses a variable `url` four times so jsscan cannot fold it. Write each call as
   `fetch(API + '/bridge/v1/pair', …)` with `API` the single `const` from `GetConvar('nakara_tickets_api', '')`
   (see `packages/devkit/src/safety/jsscan.js:180-200`). `oss.json` `http` must equal what the scanner folds
   (`${nakara_tickets_api}/bridge/v1/` style; check the scanner and `packages/rongroi/oss.json` for the format).
   `spec/bridge.test.js` is scanned too: do not call `GetConvar` or `fetch` as values there; inject stubs through a
   parameter (e.g. `createApi({ fetchImpl, apiBase })`).
5. `routes/bridge.ts:101` `Buffer.alloc(32)` fallback key → 500 `misconfigured` when no key.
6. Unconfirmed server: wait the full `wait` seconds then return null (no hot loop). `main.js`: after a null or error,
   sleep at least 1 s.
7. `main.js`: wrap each loop iteration in try/catch with backoff and a log line (never let the loop die);
   result retry stops on 4xx other than 429 (log + drop) and after 10 attempts.
8. Result: validate body (`ok` boolean, `code` string ≤ 32, `message` ≤ 512, no extra keys) → 400; compare deep
   equality, not `JSON.stringify` of jsonb; record only via `UPDATE … WHERE id=$1 AND server_id=$2 AND status='leased' RETURNING`.
9. Heartbeat: validate (≤ 2048 players, playerId int ≥ 0, discordId `^[0-9]{17,20}$`) → 400. Pair rate-limit map:
   prune entries past `resetAt`.
10. Bridge auth: timestamp `/^\d{1,12}$/`, nonce `/^[A-Za-z0-9_-]{16,64}$/`, else 401.
11. `actions.js:14-18,91`: inside a CommonJS module `exports` is the module object; use `globalThis.exports` for the
    FiveM export function and for `qbx_core`. Teleport: `ok:false, code:'error'` when the ped is 0/null.
12. `store.js`: prune executed ids older than 120 s from memory too. `api.js`: `AbortSignal.timeout(35000)` on fetch.
13. `routes/bridge.ts:213` `leasedRes` unknown → type it. W0 `test/routes.test.ts` r2 is updated by L5.

## L3 (web + session) — runs e19352 (server) and a2fb77 (web)
1. `test/session.test.ts` a4 and `test/categories.test.ts` (create, a5, PUT/DELETE) get 400
   `Invalid string: must match pattern /^[0-9]{17,20}$/`: the tests post non-snowflake ids (e.g. `parent_channel_id` /
   role ids). Use 18-digit strings in test data; keep the validation.
2. `test/auth.test.ts:125` a7 `TypeError: Invalid URL`: the test builds `new URL()` from a relative `location`
   header; parse with a base (`new URL(loc, "http://localhost")`) or have the redirect use `PUBLIC_ORIGIN`.
3. `src/routes/auth.ts:72,172` TS2345 number passed where string expected — fix the types.
4. `test/categories.test.ts:368` imports `eq` from `@nakara-tickets/db` → `drizzle-orm`.
5. Web: `src/main.tsx:4` TS2882 for `./styles.css` → add `src/vite-env.d.ts` with
   `/// <reference types="vite/client" />`; `apps/web` must pass `tsc --noEmit -p apps/web`.
6. Confirm `session.ts` declares `requireStaff(req, reply): Promise<void>` and `requireUser` in its
   `declare module "fastify"` block (L4 routes rely on it); missing decorator must never fail open.
Hook timeouts in auth/categories/session are fixed by L5 item 2.

## L5 (deploy) — scope adds `tickets/apps/server/test/routes.test.ts`
1. `static.ts`: `reply.sendFile` is not visible in the root not-found handler (plugin encapsulation) → 500. Register
   `@fastify/static` and the not-found handler inside one plugin function passed to `app.register`, or use
   `decorateReply` with a root-level registration — whichever makes s1 pass; keep the headers.
2. `vitest.config.ts`: `testTimeout: 30000`, `hookTimeout: 30000` (pglite boots take > 5 s under load; m1 timed out).
3. `test/routes.test.ts` r2: implemented operations no longer answer 501. Change r2 to: every operationId in
   `openapi.yaml` has a registered route (status ≠ 404); keep the 501 assertion only for operations still stubbed
   (list them explicitly: panels, tickets read endpoints, tags, blocks, stats, audit, data, getExport, deleteMeData).
4. `Dockerfile`: healthcheck uses `127.0.0.1`. `compose.yaml`: pin `cloudflare/cloudflared` to a version tag;
   `ALLOWED_GUILD_IDS` and `DISCORD_APP_ID` use `${VAR:?set VAR}` so compose fails loudly when unset.

## Acceptance (reviewer runs)
`npx vitest run` 0 failed (pglite tests included) · `npx tsc -b` 0 errors · `fivem-devkit safety` 0 errors ·
`npm test --workspace packages/tickets` passes.
