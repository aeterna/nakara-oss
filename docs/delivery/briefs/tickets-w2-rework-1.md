# Tickets W2 · rework 1 · local CI + Q3 findings after the six lanes

Evidence on `939bf17`: vitest 172/181 · `tsc -b` 16 errors · web tsc 21 · safety 0/0 · resource specs pass ·
`docker compose build` stops at tsc · Q3 (another model): 3 blockers, 11 majors, 5 minors. Six runs, disjoint files
(sections R-A … R-F). Read `tickets-w2-common.md`. Do not run shell commands; file tools only. Never print connection
strings, passwords, tokens or keys.

## Cross-run interfaces (implement exactly; the other side is written in parallel)
- `DiscordRest.getChannel(channelId) → Promise<{ id: string; guild_id?: string; type: number }>` (R-A writes).
- Server `app.storage: Storage | null` decorated in `app.ts`, created once in `main.ts` with `createStorage(config)`
  from `src/storage.ts`; `JobContext.storage: Storage | null` (R-A writes).
- Discord package `StoragePort = { put(key: string, bytes: Buffer, contentType: string): Promise<void>;
  delete(key: string): Promise<void> }` in `packages/discord/src/types.ts`; `StartGatewayDeps.storage?: StoragePort`
  passed into every `CloseHookContext` and the data handler (R-D writes; R-A passes `app.storage`).
- `GatewayHandle.closeHooks(guildId: string, ticketId: string, actorId: string): Promise<void>` — loads ticket, category,
  settings and runs `runCloseHooks` with the gateway's port, then locks + archives the thread (R-D writes). Server
  `types.ts` widens `app.gateway` to `{ status(): GatewayStatus; closeHooks?(guildId, ticketId, actorId): Promise<void> }`
  (R-A). Every non-Discord close (web transition, auto-close) calls `app.gateway?.closeHooks?.(…)` fire-and-forget after
  a successful `transitionTicket(close)` (R-B for `tickets.ts`, R-E for `auto-close.ts`).
- Every bot message whose text includes user- or game-supplied values is sent with `allowed_mentions: { parse: [] }`
  (plus explicit `users` where a mention is intended).

## R-A · wiring, image, session (owner of: main.ts app.ts types.ts worker.ts discord-rest.ts session.ts routes/auth.ts routes/system.ts Dockerfile compose.yaml deploy/ test files for these)
1. **Blocker — migrations:** `ROLE=migrate` uses the drizzle journal runner in `src/migrate.ts` (`runMigrations`), never a
   replay of every `.sql`. Test: migrating twice on pglite succeeds and leaves one journal row per migration.
2. Storage wiring per interfaces above; `startGateway(…, storage)`.
3. `discord-rest.ts`: add `getChannel`; 429 waits at most 2 s once, then throws `DiscordRestError{status:429}`.
4. Dockerfile: `RUN mkdir -p /data/files && chown node:node /data/files` before `USER node`.
5. `/metrics` requires `Authorization: Bearer <METRICS_TOKEN>` when env `METRICS_TOKEN` (or `_FILE`) is set, else 404;
   `/healthz` returns only `{ ok, db, gateway, version }` (no counts). `deploy/Caddyfile`: do not proxy `/metrics`.
6. `session.ts`: CSRF = `HMAC(HKDF(TICKETS_DATA_KEY, 'csrf'), session id)`; drop the branch that accepts `csrf_hash`
   as the header value. `routes/auth.ts`: OAuth cookie without `exp` → reject.
7. Test fixes: `test/routes.test.ts` r2 — every operation now implemented: assert each operationId's route exists
   (status ≠ 404) and drop the 501 list.

## R-B · tickets API + storage (owner of: storage.ts routes/tickets.ts and their tests)
1. `storage.ts:113`: pass `new Uint8Array(bytes)` (or `bytes.buffer` slice) as fetch body (TS2322). Add S3 `get` and
   `delete` signing tests.
2. `tickets.ts` transition: `allowed_mentions:{parse:[]}`; after close call `app.gateway?.closeHooks?.(…)`.
3. getAttachment: content-type allowlist (`image/png|jpeg|gif|webp`, `application/pdf`, `text/plain`, `video/mp4`,
   `audio/mpeg`), everything else `application/octet-stream`; add `Content-Security-Policy: sandbox`.
4. Use `app.storage` (not a per-request `createStorage`). `test/tickets.test.ts:121` import `afterEach`.

## R-C · personal data (owner of: packages/db/src/queries/privacy.ts apps/server/src/privacy.ts routes/data.ts jobs/retention.ts and tests)
1. `deleteUserData` also: nulls `tickets.answers` on that user's tickets, deletes their `blocks` rows (as target) and
   sets `created_by` to `'deleted'` where they blocked others, anonymises `audit_log` rows naming them (actor/target →
   `'deleted'`, detail scrubbed of the id), stores `data_requests.user_id` as `sha256(userId)`.
2. Storage deletes happen **after** the transaction commits; in `purgeExpired` keep the attachment row (mark for retry)
   when its file delete fails, never orphan files.
3. Use `app.storage` / `ctx.storage` (R-A wires them). Tests: delete-my-data with a stub storage deletes the objects;
   a failing storage delete leaves the row.

## R-D · Discord package (owner of: packages/discord/src/** and its tests)
1. **Blocker — archive SSRF:** `fetch(url, { redirect: 'manual' })`; a 3xx → follow only if `Location` is https and
   its host is in the allowlist (max 3 hops), else skip as `stored=false`.
2. **Blocker — size:** reject when `content-length` > cap; stream `res.body`, count bytes, abort past the per-file cap
   or the remaining guild quota; never `arrayBuffer()` an unbounded body. Tests: redirect to evil host skipped;
   lying size aborted at the cap.
3. `StoragePort` + `deps.storage` per interfaces; archive uses it (delete `storage-client.ts` usage if storage given;
   keep it as fallback only when `deps.storage` is absent).
4. `GatewayHandle.closeHooks(...)` per interfaces.
5. `gateway.ts`: handle string-select `nt:open-select` (`values[0]` = category id → same flow as `nt:open:`).
6. Ratings by DM: add `createDM`/`sendDM` to the port; let `nt:rate:` and `nt:ratefb:` interactions through without a
   `guildId` (resolve the guild from the ticket row); only the opener may rate.
7. `ticket-actions.ts`: no `Buffer.alloc(32)` fallback key — missing key throws at startup.

## R-E · routes panels/bridge/stats/audit/actions + auto-close + resource (owner of: routes/{panels,bridge,stats,audit,actions}.ts panel-message.ts jobs/auto-close.ts packages/tickets/** and their tests)
1. `panels.ts`: `app.discord.getChannel(channelId)` must have `guild_id === req.guildId` (else 422 `channel_not_in_guild`);
   on channel change delete the old message (ignore 404) and clear `message_id`.
2. `bridge.ts` result post and any other bot post: `allowed_mentions:{parse:[]}`; post fire-and-forget (never awaited
   by the response).
3. `stats.ts`: type the raw query results (no `unknown`, TS18046 ×11); reject impossible dates (`2026-02-31`) by
   round-tripping; `stats.ts` and `audit.ts` fail closed when `requireStaff` is missing (500 `misconfigured`).
4. `auto-close.ts`: after close call `app`-less `ctx.gateway?.closeHooks?.(…)` — add `gateway` to the job context
   usage as optional (`(ctx as any).gateway` is not allowed: R-A adds `JobContext.gateway?: { closeHooks?… }`; use it).
5. Resource `actions.js` give_item: `Object.hasOwn(allow, item)` and `Number.isInteger(max) && max > 0`.
6. Test fixes: `test/actions.test.ts:46` insert `secret_enc` as `sealBytes(key, randomBytes(32))` (bytea needs a
   Buffer); `test/bridge-result.test.ts` sign with `Buffer.from(rawSecret, 'base64url')` (the API verifies the raw
   bytes — W1 blocker) and import `eq` from `drizzle-orm`.

## R-F · web tests (owner of: tickets/apps/web/test/**)
1. `toBeInTheDocument` does not exist (no jest-dom): use `expect(el).toBeTruthy()` / `queryBy… === null` in
   `analytics.test.tsx` and `tickets.test.tsx`.
2. `tags.test.tsx:80`: guard `postCall` (assert defined first). `actions.test.tsx` g4: "multiple elements" — scope the
   query to the dialog (`within(screen.getByRole('dialog'))`) or use `getAllBy…[0]` with a role.

## Acceptance (reviewer)
vitest 0 failed (3 runs) · `tsc -b` 0 · web tsc 0 · safety 0/0 · resource specs · `docker compose up` twice in a row:
migrate exits 0 both times, `/healthz` 200 `db:up`, `/` serves the SPA, `/api/v1/me` 401, `/metrics` 404 without token.
