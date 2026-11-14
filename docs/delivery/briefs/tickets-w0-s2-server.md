# Tickets W0 · S2 · Fastify server skeleton + route stubs from openapi.yaml

**Repo:** nakara-oss · **Branch:** `feat/tickets-w0-scaffold` · **Route:** agy:B → opencode:A · **Gate:** G1 ✅ Pik 2026-11-14

## Goal (requirements only)
W1 lanes each fill their own route files; this run lays down the server and one stub file per OpenAPI tag so no two
lanes edit the same file (ADR 0003 decision 7, plan §13.6 Wave 0).
1. `tickets/apps/server` (`@nakara-tickets/server`): `src/app.ts` exports `buildApp(opts)` returning a Fastify instance
   (no listen). `src/main.ts` reads `ROLE` (`all` | `migrate`; anything else exits 1 with a message) and `PORT`
   (default 8080), and for `all` calls `buildApp().listen`. `migrate` only logs `migrate: not implemented` and exits 0.
2. One file per tag under `src/routes/<tag>.ts` (tags: system, auth, me, settings, categories, panels, tickets,
   actions, tags, blocks, stats, game-servers, audit, data, bridge), each a Fastify plugin registering every operation
   of that tag with the exact method and path from `tickets/openapi.yaml` (convert `{x}` to `:x`).
3. Every stub answers 501 with body `{ "code": "not_implemented", "message": "<operationId>" }`, except
   `GET /healthz`, which answers 200 `{ "ok": true, "db": "down", "gateway": "standby", "version": "<package version>" }`.
4. `src/routes/index.ts` registers all plugins; nothing else in `app.ts` knows route paths.

## Acceptance tests (`tickets/apps/server/test/routes.test.ts`, vitest) — write these first
- (r1) Parse `tickets/openapi.yaml` (dev dependency `yaml`) and, for every operation, `app.inject` the method + path
  (fill path params with valid sample values: snowflake `123456789012345678`, uuid `00000000-0000-4000-8000-000000000000`,
  transition `claim`) and assert the status is not 404.
- (r2) every operation except `getHealthz` answers 501 with `message` equal to its `operationId`.
- (r3) `GET /healthz` answers 200 with `ok: true` and `version` equal to `apps/server/package.json` version.
- (r4) the count of registered routes equals the count of operations in the spec (no extra routes).
- (c1) control: injecting `GET /api/v1/nope` answers 404.

## Deliverables
D1 `tickets/apps/server/package.json` · D2 `tickets/apps/server/tsconfig.json` · D3 `tickets/apps/server/src/app.ts`
D4 `tickets/apps/server/src/main.ts` · D5 `tickets/apps/server/src/routes/index.ts` · D6 the 15 files `src/routes/<tag>.ts`
D7 `tickets/apps/server/test/routes.test.ts` (r1–r4, c1)

Dependency versions (exact): `fastify 5.12.8`; dev: `vitest 5.1.0`, `typescript 7.0.2`, `yaml 2.9.1`, `@types/node 26.6.6`.

## Premise checked
- 15 tags and 44 operations, each with an `operationId`: `tickets/openapi.yaml` (redocly lint valid, PR #35).
- `{ticketId}/{transition}` is one path with `transition` enum `claim|unclaim|transfer|close|reopen`.

## Scope
`tickets/apps/server/**`

## Out of scope
`tickets/package.json` and `tsconfig*.json` at `tickets/` root (S1), `packages/db`, any business logic, Discord, auth,
lockfiles. You cannot install packages or run commands; read Fastify 5's types carefully.
