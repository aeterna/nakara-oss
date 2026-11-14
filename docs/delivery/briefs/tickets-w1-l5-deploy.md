# Tickets W1 · L5 · image, compose, migrations, static files

**Route:** agy:B · **Gate:** G1 ✅ Pik 2026-11-14 · also read `tickets-w1-common.md` · ADR 0003 decisions 1–2

## Goal
One image runs the whole system in run mode A (VM + compose) or B (serverless container); `ROLE=migrate` applies
migrations and exits.

1. `tickets/apps/server/src/migrate.ts`: `runMigrations(databaseUrl: string, migrationsFolder: string)` with
   `drizzle-orm/node-postgres/migrator`; logs applied count; never logs the URL.
2. `tickets/apps/server/src/static.ts`: `installStatic(app, dir: string)` serves the built SPA with
   `@fastify/static`; unknown GET paths outside `/api`, `/auth`, `/bridge`, `/healthz`, `/metrics` return
   `index.html`; adds `X-Content-Type-Options: nosniff` and a CSP (`default-src 'self'; img-src 'self'
   https://cdn.discordapp.com data:; frame-ancestors 'none'`). Missing `dir` → logs a warning, serves nothing.
3. `tickets/vitest.config.ts`: `test.projects` for `packages/*` and `apps/*`, exclude `**/dist/**` and
   `**/node_modules/**`; `tickets/package.json` scripts unchanged (`vitest run`).
4. `tickets/Dockerfile`: multi-stage, `node:22-bookworm-slim` pinned by digest placeholder comment
   (`# pin: node:22-bookworm-slim@sha256:<fill at release>` and use the tag for now); build stage `npm ci`,
   `tsc -b`, `vite build` for `apps/web`; runtime stage copies only `dist`, production `node_modules`,
   `packages/db/migrations`, web `dist`; runs as user `node`; `ENV ROLE=all PORT=8080`; `HEALTHCHECK` with
   `node -e` fetching `/healthz`; `CMD ["node","apps/server/dist/main.js"]`. `tickets/.dockerignore`.
5. `tickets/compose.yaml`: services `postgres` (17, volume, healthcheck, `mem_limit`), `migrate` (same image,
   `ROLE=migrate`, `depends_on` postgres healthy, `restart: "no"`), `app` (`depends_on` migrate completed
   successfully, volume `/data/files`, `mem_limit`), profiles `caddy` (ports 80/443, `deploy/Caddyfile`) and
   `cloudflared` (no ports, token from a Docker secret file), `backup` (daily `pg_dump` to a volume, keeps 7).
   Secrets via `*_FILE` variables and Docker secrets (config.ts reads `*_FILE`), never inline values.
6. `tickets/deploy/`: `Caddyfile`, `env.example` (names only, no values), `backup.sh`, `README.md` (run mode A
   step by step; run mode B: one always-on instance min=max=1, session-mode Postgres, S3 storage note, "billed as
   always-on"; Discord app setup: intents, permissions list from ADR decision 5, turn off Public Bot,
   `ALLOWED_GUILD_IDS`), `PRIVACY-TEMPLATE.md` (ADR decision 12: what is stored, retention, deletion route, contact).

## Acceptance tests — write first
m1 (`apps/server/test/migrate.test.ts`, pglite + `drizzle-orm/pglite/migrator` on the same folder): all 18 tables exist
after migrating, and migrating twice is a no-op; s1 (`static.test.ts`, temp dir with `index.html` + `app.js`):
`/app.js` served, `/categories` returns index.html, `/api/v1/nope` is not index.html, headers present; s2 missing dir
→ app still builds. Config sanity (`deploy.test.ts`, parse `compose.yaml` with `yaml`): every service has
`mem_limit`; no service has an inline value for a variable whose name contains TOKEN, SECRET, PASSWORD or KEY;
migrate has `restart: "no"`.

## Scope
`tickets/apps/server/src/{migrate,static}.ts` · `tickets/apps/server/test/{migrate,static,deploy}.test.ts` ·
`tickets/vitest.config.ts` · `tickets/Dockerfile` · `tickets/.dockerignore` · `tickets/compose.yaml` · `tickets/deploy/**`

## Out of scope
`main.ts` / `app.ts` wiring (W1-int calls `runMigrations` and `installStatic`), CI workflow and image publishing
(`.github/`, done by the reviewer / W4), actually running Docker.
