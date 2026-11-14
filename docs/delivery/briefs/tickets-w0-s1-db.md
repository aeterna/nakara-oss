# Tickets W0 · S1 · npm project skeleton + Drizzle schema

**Repo:** nakara-oss · **Branch:** `feat/tickets-w0-scaffold` · **Route:** agy:B → opencode:A · **Gate:** G1 ✅ Pik 2026-11-14

## Goal (requirements only)
`tickets/` becomes its own npm project (ADR 0003 decision 11) and gets the database schema every W1 lane imports
(decision 4), so no W1 lane edits the schema or the lockfile.
1. `tickets/package.json`: `"private": true`, `"type": "module"`, `"license": "MIT"`, `engines.node >=22`, workspaces
   `["apps/*", "packages/*"]`, scripts `test` (`vitest run`), `typecheck` (`tsc -b`). It is NOT added to the root
   `package.json` workspaces.
2. `tickets/tsconfig.base.json` (strict, `module`/`moduleResolution` `NodeNext`, `target` ES2023) and
   `tickets/tsconfig.json` with project references to `packages/db` (S2 adds `apps/server` later).
3. `tickets/packages/db` (`@nakara-tickets/db`): `src/schema.ts` defines the 18 tables of ADR 0003 decision 4 with
   Drizzle `pg-core`, fields as in `tickets/openapi.yaml` schemas. Every table has `guild_id` (text, not null) except
   `sessions` and `bridge_nonces` (which key on their own ids). Required constraints:
   - `tickets`: unique (`guild_id`, `number`); status enum `open|claimed|closed`.
   - `bridge_nonces`: primary key (`server_id`, `nonce`), `expires_at` timestamptz not null.
   - `game_actions`: status enum `queued|leased|done|failed|expired`; `lease_until`, `expires_at` timestamptz.
   - `game_servers.secret_enc` and `messages.content_enc` are `bytea` (encrypted at rest; never plaintext columns).
   - `pair_codes` stores `code_hash` (text), never the code.
4. `src/index.ts` exports the schema and a `guildScoped(db, guildId)` helper whose query functions always add
   `guild_id = $guildId` (decision 4). `drizzle.config.ts` points at `src/schema.ts` and `migrations/`.
5. No migration SQL in this run (the Orchestrator generates it with drizzle-kit after install).

## Acceptance tests (`tickets/packages/db/test/schema.test.ts`, vitest) — write these first
- (s1) all 18 table names exist in the exported schema (use `getTableConfig`).
- (s2) every table except `sessions` and `bridge_nonces` has a non-null `guild_id` column.
- (s3) `tickets` has a unique index over (`guild_id`, `number`); `bridge_nonces` primary key is (`server_id`, `nonce`).
- (s4) no column named `secret`, `code`, `content` or `token` exists in any table (only `*_enc` / `*_hash`).
- (s5) `guildScoped(db, 'g1').tickets.list()` builds SQL whose where-clause contains `guild_id` (use `.toSQL()`, no DB).
- (c1) control: a test asserting a table `does_not_exist` exists fails.

## Deliverables
D1 `tickets/package.json` · D2 `tickets/tsconfig.base.json` + `tickets/tsconfig.json` · D3 `tickets/packages/db/package.json`
D4 `tickets/packages/db/src/schema.ts` · D5 `tickets/packages/db/src/index.ts` · D6 `tickets/packages/db/drizzle.config.ts`
D7 `tickets/packages/db/test/schema.test.ts` (s1–s5, c1) · D8 `tickets/packages/db/tsconfig.json`

Dependency versions (exact, do not change): `drizzle-orm 0.45.4`, `pg 8.23.1`; dev: `drizzle-kit 0.31.11`,
`vitest 5.1.0`, `typescript 7.0.2`, `@types/pg 8.23.1`, `@types/node 26.6.6`.

## Premise checked
- Table list and constraints: `docs/adr/0003-nakara-tickets.md` decision 4 and 8; field shapes: `tickets/openapi.yaml`
  `components.schemas` (on this branch, commit of PR #35).
- Root workspaces are only `packages/devkit` and `packages/rongroi` (root `package.json`); npm cannot nest workspaces.
- Versions above exist on npm (`npm view <pkg> version`, 2026-11-14).

## Scope
`tickets/package.json` · `tickets/tsconfig.base.json` · `tickets/tsconfig.json` · `tickets/packages/db/**`

## Out of scope
`tickets/apps/**` (S2), root files, lockfiles, `packages/`, `.github/`, migration SQL. You cannot install packages or
run commands: read Drizzle's types carefully and keep imports to `drizzle-orm`, `drizzle-orm/pg-core`, `pg`.
