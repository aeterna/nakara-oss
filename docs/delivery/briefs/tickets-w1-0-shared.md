# Tickets W1-0 · shared foundations before the five W1 lanes

**Repo:** nakara-oss · **Branch:** `feat/tickets-w1` · **Route:** agy:B · **Gate:** G1 ✅ Pik 2026-11-14 ("Start W1")

## Goal (requirements only)
Every W1 lane needs config, a database handle, encryption at rest and the bridge HMAC. Lay these down once so no two
lanes edit the same file (AGENTS §13.6 Wave 0), and declare every lane's dependencies now so no lane edits a lockfile.
1. New package `tickets/packages/core` (`@nakara-tickets/core`, private, MIT, ESM, no runtime deps beyond `node:`):
   - `src/crypto.ts`: `sealBytes(key: Buffer, plain: Buffer): Buffer` and `openBytes(key, sealed): Buffer` with
     AES-256-GCM; output layout `version(1 byte = 1) | iv(12) | tag(16) | ciphertext`. `parseDataKey(b64: string): Buffer`
     accepts exactly 32 bytes of base64/base64url and throws otherwise.
   - `src/hmac.ts`: `bridgeCanonical({timestamp, nonce, method, pathWithQuery, body})` returns
     `` `${timestamp}\n${nonce}\n${METHOD}\n${pathWithQuery}\n${sha256hex(body)}` `` (as in `tickets/openapi.yaml`
     securitySchemes.bridgeHmac); `signBridge(secret, parts)` → hex HMAC-SHA256; `verifyBridge(secret, parts, sigHex,
     nowSec, skewSec = 60)` → `{ ok: true } | { ok: false, reason: 'skew' | 'signature' | 'malformed' }`, constant-time.
   - `src/index.ts` re-exports both.
2. `tickets/apps/server/src/config.ts`: `loadConfig(env = process.env)` validated with zod, returning a frozen object:
   `ROLE` (`all`|`migrate`), `PORT` (int 1–65535, default 8080; invalid → error, not silent default), `DATABASE_URL`
   (required), `TICKETS_DATA_KEY` (required, via `parseDataKey`), `DISCORD_TOKEN`, `DISCORD_APP_ID`,
   `DISCORD_CLIENT_SECRET` (required when ROLE=all), `PUBLIC_ORIGIN` (https URL; http allowed only for localhost),
   `ALLOWED_GUILD_IDS` (comma list of snowflakes, required, non-empty), `STORAGE_DIR` (default `/data/files`).
   Any `*_FILE` variant (e.g. `DISCORD_TOKEN_FILE`) is read from that file path when the plain variable is absent.
   Error messages name the variable, never its value.
3. `tickets/apps/server/src/db.ts`: `createDb(url)` returns `{ db, pool, close() }` using `pg` Pool + drizzle with the
   `@nakara-tickets/db` schema.
4. `tickets/apps/server/src/app.ts`: `buildApp(opts)` takes optional `{ config, db }` and decorates the Fastify
   instance with `app.config` and `app.db` (typed via a `declare module 'fastify'` block in `src/types.ts`). With no
   options it must still build (tests inject routes without a database).
5. `main.ts` uses `loadConfig()`; ROLE=migrate stays a stub (L5 implements it).
6. Workspace manifests with every W1 dependency (exact versions below), so the Orchestrator generates one lockfile:
   - `apps/server/package.json` add: `@nakara-tickets/core`, `@nakara-tickets/db` (`"*"`), `drizzle-orm 0.45.4`,
     `pg 8.23.1`, `zod 4.6.7`, `@fastify/cookie 11.1.5`, `@fastify/static 10.1.11`, `discord.js 14.28.1`.
   - new `packages/discord/package.json` (`@nakara-tickets/discord`, deps `discord.js 14.28.1`, `@nakara-tickets/core`,
     `@nakara-tickets/db`), with `src/index.ts` exporting nothing yet but a `VERSION` const, plus `tsconfig.json`.
   - new `apps/web/package.json` (`@nakara-tickets/web`): deps `react 19.3.1`, `react-dom 19.3.1`; dev `vite 8.3.8`,
     `@vitejs/plugin-react 6.3.0`, `@types/react 19.3.0`, `@types/react-dom 19.3.0`, `jsdom 31.0.1`,
     `@testing-library/react 16.3.3`, `vitest 5.1.0`, `typescript 7.0.2`. Only the manifest in this run.
   - `tickets/tsconfig.json` references `packages/core` and `packages/discord` too.

## Acceptance tests — write these first
- `packages/core/test/crypto.test.ts`: (k1) round trip of empty, 1 byte and 64 KiB; (k2) flipping any byte of the
  sealed output makes `openBytes` throw; (k3) a different key throws; (k4) two seals of the same input differ;
  (k5) `parseDataKey` rejects 31 and 33 bytes and non-base64.
- `packages/core/test/hmac.test.ts`: (h1) canonical string for a known input equals a literal expected string;
  (h2) sign→verify ok; (h3) one changed char in path, body, nonce or timestamp → `signature`; (h4) |now−ts| = 61 →
  `skew`, 60 → ok; (h5) non-hex or wrong-length signature → `malformed` (no throw).
- `apps/server/test/config.test.ts`: (e1) minimal valid env (ROLE=migrate, DATABASE_URL, key, ALLOWED_GUILD_IDS,
  PUBLIC_ORIGIN) loads; (e2) `PORT=abc` and `PORT=0` throw naming `PORT`; (e3) ROLE=all without `DISCORD_TOKEN`
  throws naming it; (e4) `DISCORD_TOKEN_FILE` is read; (e5) no error message contains the token or key value;
  (e6) `PUBLIC_ORIGIN=http://example.com` throws, `http://localhost:8080` loads.
- Existing suites must still pass: today 15 (db 10, server 5).

## Deliverables
D1 `packages/core/src/{crypto,hmac,index}.ts` + `package.json` + `tsconfig.json` · D2 core tests k1–k5, h1–h5 ·
D3 `apps/server/src/{config,db,types}.ts` · D4 `app.ts` + `main.ts` changes · D5 `apps/server/test/config.test.ts` e1–e6 ·
D6 `packages/discord/{package.json,tsconfig.json,src/index.ts}` · D7 `apps/web/package.json` · D8 `tickets/tsconfig.json`,
`apps/server/package.json`

## Carried in
| from | trap | not again |
|---|---|---|
| W0 runs | agy runs a shell command → auto-denied → empty patch | no shell commands; file tools only |
| W0 Q3 | test that passes vacuously | each test must be able to fail; include the controls above |

## Premise checked
Bridge canonical string: `tickets/openapi.yaml` components.securitySchemes.bridgeHmac. Decisions: ADR 0003 4, 6, 8.
Versions: `npm view` 2026-11-14. Current `app.ts` takes `FastifyServerOptions` only; `main.ts` reads ROLE/PORT inline.

## Scope
`tickets/packages/core/**` · `tickets/packages/discord/**` · `tickets/apps/web/package.json` ·
`tickets/apps/server/src/{config,db,types,app,main}.ts` · `tickets/apps/server/test/config.test.ts` ·
`tickets/apps/server/package.json` · `tickets/tsconfig.json`

## Out of scope
Route files, Discord logic, web UI, the resource, Docker, lockfiles, migrations, `.github/`.
