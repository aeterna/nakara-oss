# Tickets W2 · rework 4 · `ROLE=migrate` must not need app-only settings

Evidence (reviewer, real `docker compose up` on `8f52294`, dummy secrets): image layout is right (`/app/server.mjs`,
`/app/migrations` with `meta/_journal.json`, `/app/web`, `MIGRATIONS_DIR`/`WEB_DIR` set) but the `migrate` container exits
1: `Config validation error: PUBLIC_ORIGIN … is required; ALLOWED_GUILD_IDS … is required`. The compose `migrate`
service only gets `DATABASE_URL_FILE` and `TICKETS_DATA_KEY_FILE`, which is correct: a migration needs no Discord or web
settings.

## Fix (owner: tickets/apps/server/src/config.ts, tickets/apps/server/test/config.test.ts)
1. `loadConfig`: when `ROLE=migrate`, only `DATABASE_URL` is required; `TICKETS_DATA_KEY`, `PUBLIC_ORIGIN`,
   `ALLOWED_GUILD_IDS` and the Discord values are optional (validated when present). `ROLE=all` keeps every current
   requirement. Keep the returned type usable by `main.ts` (make the fields optional in a `MigrateConfig` branch of a
   discriminated union on `ROLE`, or keep one type with optional fields and assert presence in the `all` branch —
   whichever keeps `tsc -b` clean without changing `main.ts`; if `main.ts` must change, note it under "Needs from others").
2. Tests: e1 changes to "ROLE=migrate with only DATABASE_URL loads"; new e7 "ROLE=all without PUBLIC_ORIGIN throws
   naming it"; keep e2–e6.
Do not run shell commands; file tools only. Never print connection strings, passwords, tokens or keys.
