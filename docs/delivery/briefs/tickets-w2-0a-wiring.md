# Tickets W2-0a · wire the server end to end + W1 Q3 minors

**Route:** agy:B · **Gate:** G1 ✅ Pik 2026-11-14 ("Start W2") · also read `tickets-w1-common.md` (rules still apply)

## Why
W1 merged every piece but nothing connects them: `apps/server/src/main.ts` never installs the session, bridge auth or
static files, never starts the Discord gateway, `ROLE=migrate` prints "not implemented", and `/healthz` is a constant.
The image does not work end to end. This run wires it, plus the shared server pieces the W2 lanes call.

## Goal
1. `src/discord-rest.ts`: `createDiscordRest({ token, fetchImpl = fetch })` →
   `{ sendMessage(channelId, body), editMessage(channelId, messageId, body), deleteMessage(channelId, messageId),
   createDM(userId) }` over `https://discord.com/api/v10` with `Authorization: Bot …`, `AbortSignal.timeout(10000)`,
   429 → wait `retry_after` once then retry; non-2xx → throws `DiscordRestError { status, code }` (never the token).
   Export type `DiscordRest`.
2. `src/worker.ts`: `startWorker(jobs: Job[], ctx: JobContext, log)` → `{ stop(): Promise<void> }`.
   `Job = { name: string; intervalMs: number; run(ctx: JobContext): Promise<void> }`;
   `JobContext = { db: TicketsDb; config: TicketsConfig; discord: DiscordRest | null; log }`. Each job runs on its own
   timer, never overlapping itself; a throw is logged with the job name and the timer continues; `stop()` waits for
   running jobs.
3. `src/jobs/index.ts` exports `jobs: Job[] = [retentionJob, autoCloseJob]`; create `src/jobs/retention.ts` and
   `src/jobs/auto-close.ts`, each exporting a job (`intervalMs` 15 min / 5 min) whose `run` does nothing yet (lanes fill it).
4. `src/app.ts` + `src/types.ts`: `BuildAppOptions` gains `gateway?: { status(): GatewayStatus }` and
   `discord?: DiscordRest | null`; decorate `app.gateway`, `app.discord` (null when absent). Add exported
   `installAll(app, { config, db, webDir })` that calls `installSession(app, { config, db })`,
   `installBridgeAuth(app, { db, dataKey: config.TICKETS_DATA_KEY })` and `installStatic(app, webDir)`.
5. `src/main.ts`:
   - `ROLE=migrate`: `runMigrations(DATABASE_URL, migrationsDir)` then exit 0 (exit 1 on error, message without the
     URL). `migrationsDir` = env `MIGRATIONS_DIR` or `new URL('../../../packages/db/migrations/', import.meta.url)`.
   - `ROLE=all`: `createDb` → `createDiscordRest` → `startGateway({ token, appId, allowedGuildIds, db, pool,
     dataKey, log })` (from `@nakara-tickets/discord`; do not await the connect, it may wait in standby) →
     `buildApp({ config, db, gateway, discord, logger: true })` → `installAll(…, webDir = env WEB_DIR or
     '/app/web')` → `startWorker(jobs, …)` → `listen`. Shutdown on SIGTERM/SIGINT: worker.stop → gateway.stop →
     app.close → db close → exit 0, each step in try/catch.
6. `src/routes/system.ts`: `/healthz` = `{ ok, db, gateway, version }`: `db` from `select 1` with a 1 s timeout
   (`up`/`down`), `gateway` = `app.gateway?.status() ?? 'connecting'` mapped into the openapi enum, `ok` = db up;
   status 200 when ok, 503 otherwise. `/metrics`: Prometheus text (`text/plain; version=0.0.4`):
   `nakara_tickets_up 1`, `nakara_tickets_tickets{status="open|claimed|closed"}` counts,
   `nakara_tickets_game_servers_online` (last_seen within 90 s), `nakara_tickets_gateway_connected 0|1`. No guild ids
   or names in labels.
7. W1 Q3 minors:
   - `routes/bridge.ts` result route: `:actionId` must match a UUID regex → 400 `invalid`.
   - `staff.ts`, `session.ts`, `routes/auth.ts`: every Discord `fetch` gets `AbortSignal.timeout(10000)`; the staff and
     user caches are bounded (max 5,000 entries, drop oldest) and expire.
   - `routes/auth.ts` `POST /auth/logout`: requires the CSRF header (same check as `/api/v1` writes).
   - `session.ts`: store `sha256(csrf)` in `csrf_hash` and compare hashes in constant time; the plain token is only
     returned by `GET /api/v1/me` for the current session (keep it in the session row? no — derive it as
     `HMAC(TICKETS_DATA_KEY, 'csrf:' + session id)` so nothing plain is stored, and check by recomputing).
   - OAuth state cookie: sign with a key derived from `TICKETS_DATA_KEY` (`HMAC(key, 'oauth-cookie')`), and put an
     `exp` (10 min) inside the signed payload.

## Acceptance tests — write first (`apps/server/test/`)
w1 `worker.test.ts`: a job runs on its interval (fake timers), a throwing job is logged and runs again, a slow job never
overlaps itself, `stop()` waits. w2 `discord-rest.test.ts`: header `Bot <token>`, 429 retried once, error text never
contains the token. w3 `system.test.ts`: healthz 200/`up` with a pglite db, 503/`down` with a db whose query throws;
metrics contains the four series and no snowflake. w4 `wiring.test.ts`: `buildApp` + `installAll` with a full config
and pglite → `GET /api/v1/me` without cookie = 401 (session installed), `POST /bridge/v1/heartbeat` unsigned = 401
(bridge auth installed), `GET /` serves `index.html` from a temp `webDir`. w5 bridge result with `actionId=nope` → 400.
w6 logout without CSRF → 403. w7 no session row contains the CSRF token or a value equal to it.
Existing 98 tests stay green (update only tests whose subject changed: csrf/oauth-cookie internals).

## Scope
`tickets/apps/server/src/{main,app,types,discord-rest,worker,session,staff}.ts` · `tickets/apps/server/src/jobs/*` ·
`tickets/apps/server/src/routes/{system,auth,bridge}.ts` · `tickets/apps/server/test/*`

## Out of scope
Discord handlers, web, schema, any other route file.
