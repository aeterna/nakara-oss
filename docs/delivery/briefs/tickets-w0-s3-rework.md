# Tickets W0 · S3 · Rework after Q3 (schema + typecheck wiring)

**Repo:** nakara-oss · **Branch:** `feat/tickets-w0-scaffold` (S1 6df7846, S2 65c4eb6 already in) · **Route:** agy:B · **Gate:** G1 ✅ Pik 2026-11-14

## Goal (requirements only)
Q3 found that the shared schema is not yet safe for parallel W1 lanes. Fix all of it in one run. Do not rewrite code
that already works unless an item below names it.
1. Replace `guildScoped()` in `packages/db/src/index.ts` with a generic, typed helper so no lane ever edits that file
   to add a table: `export function inGuild<T extends AnyPgTable & { guild_id: AnyPgColumn }>(table: T, guildId: string): SQL`
   returning `eq(table.guild_id, guildId)`. Keep no per-table code in `index.ts`. Remove `guildScoped`.
2. `sessions`: `id` uuid default random; `token_hash` text NOT NULL with a unique index; `csrf_hash` NOT NULL. No
   column may hold the raw cookie value.
3. Foreign keys (all `ON DELETE CASCADE` unless noted): tickets.category_id → categories.id (`RESTRICT`),
   ticket_members/messages/attachments/ratings/game_actions.ticket_id → tickets.id, game_actions.server_id →
   game_servers.id, bridge_nonces.server_id → game_servers.id, categories.game_server_id → game_servers.id
   (`SET NULL`), guild_settings.guild_id → guilds.guild_id.
4. Indexes: `game_actions(server_id, status)`, `tickets(guild_id, status)`, `messages(ticket_id)`,
   unique `pair_codes(code_hash)`, `bridge_nonces(expires_at)`, unique `ratings(ticket_id, user_id)`,
   unique `ticket_members(ticket_id, user_id)`, unique `tags(guild_id, name)`, unique `blocks(guild_id, user_id)`.
5. Columns: `attachments.storage_key` text (null until stored); `game_servers.protocol` integer NOT NULL default 1;
   `pair_codes.used_at` timestamptz.
6. `apps/server/tsconfig.json` extends `../../tsconfig.base.json` with `composite: true`, `rootDir: "."`,
   `resolveJsonModule: true`; `tickets/tsconfig.json` references `apps/server`; `apps/server/package.json` gets
   `"private": true` and `"license": "MIT"`. `npm run typecheck` (`tsc -b`) must then cover db and server.
7. Tests: s5 rewritten for `inGuild` and asserting the generated SQL has `where` + `guild_id` + param `g1`
   (not only the column list); c1 replaced by a control that would catch a schema bug (e.g. assert `messages` has a
   column `content` and show that assertion fails). r4 compares the set of `METHOD path` strings, not a count.

## Acceptance tests (extend `packages/db/test/schema.test.ts`, `apps/server/test/routes.test.ts`) — write first
- (f1) each FK in item 3 exists with its delete rule (`getTableConfig(t).foreignKeys`, `fk.onDelete`).
- (f2) each index in item 4 exists with the right columns and uniqueness.
- (f3) `sessions.id` is uuid, `token_hash` not null + unique; no column named `token` or `cookie` anywhere.
- (f4) `attachments.storage_key`, `game_servers.protocol` (not null, default 1), `pair_codes.used_at` exist.
- (f5) `inGuild(schema.tickets, 'g1')` used in `db.select().from(tickets).where(...)`.toSQL() has `where` and param `g1`.
- (r4') registered `METHOD path` set equals the spec's set (path params converted).
- Suite today: 11 passed (db 6, server 5) ⇒ state the final count.

## Deliverables
D1 `inGuild` in `tickets/packages/db/src/index.ts` · D2 schema changes in `tickets/packages/db/src/schema.ts`
D3 tests f1–f5 in `schema.test.ts` · D4 r4' in `routes.test.ts` · D5 `tickets/apps/server/tsconfig.json`
D6 `tickets/tsconfig.json` reference · D7 `tickets/apps/server/package.json` private + license

## Carried in
| from | trap | not again |
|---|---|---|
| S1 run 20261114-173810-4479f4 | engine ran a shell command, got auto-denied, wrote nothing | no shell commands at all; file tools only |
| Q3 2026-11-14 | s5 passed vacuously (column list contains guild_id) | assert the WHERE clause |

## Premise checked
Q3 findings with lines: `packages/db/src/index.ts:6`, `schema.ts:120`, `schema.ts:225`, `apps/server/tsconfig.json`,
`schema.test.ts:96,99`, `routes.test.ts:59`; migration `0000_init.sql` has 0 FKs and 1 index (drizzle-kit output).

## Scope
`tickets/packages/db/src/**` · `tickets/packages/db/test/**` · `tickets/apps/server/test/routes.test.ts` ·
`tickets/apps/server/tsconfig.json` · `tickets/apps/server/package.json` · `tickets/tsconfig.json`

## Out of scope
Migrations (Orchestrator regenerates), lockfiles, route files, `.github/`, anything outside `tickets/`.
