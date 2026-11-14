# Tickets W1 · rework 2 · after rework-1 runs 68da4c 882c09 40eb18 c33e25 de5a34

**Route:** agy:B · one run (it touches test files of every lane, so it cannot be split).
Evidence (reviewer, `feat/tickets-w1` + rework-1): `fivem-devkit safety` 0 errors (1 warning) ✅ ·
`npm test --workspace packages/tickets` ✅ · `npx vitest run` 98 tests: 7–15 fail, **a different set each run** ·
`npx tsc -b` 7 errors. `s1` failed twice with the same check, so the reviewer diagnosed it before this brief (AGENTS §5.6).
Do not run shell commands; file tools only. Never print connection strings, passwords, tokens or keys.

## Diagnosed causes and the fix for each
1. **`static.test.ts` s1 → 500 `res.setHeader is not a function`.** `@fastify/static` 10 calls
   `setHeaders(reply: FastifyReply, path, stat)` (see `node_modules/@fastify/static/types/index.d.ts:97`), not a Node
   response. In `apps/server/src/static.ts` use `reply.header(...)` in `setHeaders`.
2. **`bridge.test.ts` b1 → 400.** The test stores `sha256(‘PAIRCODE10’)` but the route hashes the normalised code
   (`O`→`0`), so the hash never matches. Tests must store `sha256(normalizePairCode(code))`. Also
   `normalizePairCode` is duplicated in `routes/bridge.ts:21` and `routes/game-servers.ts:18`: move it (and the
   sha256 helper) to `apps/server/src/bridge/pair-code.ts`; both routes and the tests import it.
3. **Flaky timeouts (`Hook timed out in 10000ms`, `Test timed out in 5000ms`) in every pglite file.** Each test boots
   a new PGlite and replays migrations (`beforeEach(createTestDb)`), several files in parallel; and the root
   `vitest.config.ts` `testTimeout/hookTimeout` do **not** reach `projects` (vitest projects inherit root options only
   with `extends: true`). Fix:
   - `tickets/packages/db/test-support/pglite.ts`: `openTestDb()` creates one PGlite per file, applies every
     `packages/db/migrations/*.sql` (split on `--> statement-breakpoint`) once, returns `{ db, pg, reset(), close() }`;
     `reset()` runs one `TRUNCATE <all 18 tables> RESTART IDENTITY CASCADE`. Path resolved with
     `new URL('../migrations/', import.meta.url)`.
   - Every pglite test file (`apps/server/test/{auth,bridge,categories,game-servers,session}.test.ts`,
     `packages/db/test/queries.test.ts`, `packages/discord/test/acceptance.test.ts`) uses `beforeAll(open)`,
     `beforeEach(reset)`, `afterAll(close)`; remove explicit per-hook timeouts; delete `packages/discord/test/test-db.ts`
     (write it as `export {};`, the reviewer deletes it). `migrate.test.ts` keeps its own fresh PGlite (it tests migrating).
   - `tickets/vitest.config.ts`: `projects` as objects with `extends: true` for `packages/core`, `packages/db`,
     `packages/discord`, `apps/server` (`test: { name, root }`), and `'apps/web'` as a path (it has its own config);
     `testTimeout: 30000`, `hookTimeout: 60000` at root.
4. **tsc TS2322 in `routes/categories.ts:47,57,75,104`, `settings.ts:25,45`, `me.ts:12`:** a `preHandler` returns the
   `FastifyReply`. Write preHandlers as `async (req, reply) => { await app.requireStaff(req, reply); }` (return
   nothing).
5. Q3 left for this run: `oss.json` warning `http '${nakara_tickets_api}/bridge/v1/' declared but never used` — set
   the `http` entry to exactly what the scanner folds from `api.js` (run is file-only: read
   `packages/devkit/src/safety/jsscan.js` and an existing passing `oss.json` to get the folded form).

## Acceptance (reviewer runs, three times in a row, no failures)
`npx vitest run` 0 failed · `npx tsc -b` 0 errors · `tsc --noEmit -p apps/web` 0 · `fivem-devkit safety` 0 errors 0 warnings.

## Scope
`tickets/vitest.config.ts` · `tickets/packages/db/test-support/*` · `tickets/packages/db/test/*` ·
`tickets/packages/discord/test/*` · `tickets/apps/server/test/*` · `tickets/apps/server/src/static.ts` ·
`tickets/apps/server/src/bridge/*` · `tickets/apps/server/src/routes/{bridge,game-servers,categories,settings,me}.ts` ·
`packages/tickets/oss.json`
