# Tickets W1 · rules shared by lanes L1–L5

Read with your lane brief. Base: `feat/tickets-w1` after W1-0 (shared config, db handle, `@nakara-tickets/core`
crypto + HMAC, all dependencies already in the manifests and lockfile).

- **Contract:** `tickets/openapi.yaml` (paths, bodies, error shape `{code, message}`), ADR `docs/adr/0003-nakara-tickets.md`.
- **No shared files.** Touch only your lane's Scope. Do not edit `apps/server/src/app.ts`, `main.ts`, `types.ts`,
  `config.ts`, `db.ts`, any `package.json` (except where your Scope lists one), or a lockfile. Wiring into `app.ts`
  and `main.ts` is a later run (W1-int) that calls the exports named in your brief **with exactly those signatures**.
- **Fastify decorators** you add go in your own file with its own `declare module 'fastify'` block, installed by an
  exported `installX(app)` function (plain call, not `app.register`, so decorators stay visible to routes).
- **Guild scope:** every query filters by `guild_id` through `inGuild()` from `@nakara-tickets/db`.
- **Tests:** vitest. Database tests use `@electric-sql/pglite` (in-process Postgres) via
  `drizzle-orm/pglite`, applying `tickets/packages/db/migrations/*.sql` first. Each test must be able to fail;
  include a negative control. No network in tests (stub `fetch` / discord.js objects).
- **Imports:** ESM, NodeNext, relative imports end in `.js`.
- Never print connection strings, passwords, tokens or keys. Error messages name a field, never its value.
- Do not run any shell command; use only read-file and write-file tools. The reviewer runs build and tests.
