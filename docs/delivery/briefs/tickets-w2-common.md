# Tickets W2 · rules shared by lanes L1a L1b L2 L3 L4 L5

Read with your lane brief and `tickets-w1-common.md` (all W1 rules still apply). Base: `feat/tickets-w2` after W2-0
(server wired end to end; `app.discord` REST client; `startWorker` + `src/jobs/*`; Discord close hooks; web page
stubs, per-area `i18n/*.ts` and `api/*.ts`; schema columns `tickets.archived_at`, `tickets.auto_close_warned_at`,
`guild_settings.attachment_quota_mb`, `guild_settings.auto_close_warn_hours`; migration generated).

- **Only your files.** Shared files (`app.ts`, `main.ts`, `gateway.ts`, `App.tsx`, `i18n.ts`, `api.ts`,
  `jobs/index.ts`, `close-hooks.ts`, schema, migrations, any `package.json`, lockfiles) are off limits, except the
  single additions your brief assigns to you by name (L1a `adapter.ts`, L1b `gateway.ts` + db `index.ts`, L4
  `discord-rest.ts`, L5 `routes/bridge.ts`). If you need a
  change there, write it under "Needs from others" in your final answer; do not make it.
- **Contract:** `tickets/openapi.yaml` request/response shapes; `{code, message}` errors; zod bodies.
- **Routes** use `preHandler: async (req, reply) => { await app.requireStaff(req, reply); }` (never return the reply)
  and read `req.guildId`. Every query is guild scoped (`inGuild`).
- **Discord REST** from the API process: `app.discord` (`sendMessage`, `editMessage`, `deleteMessage`, `createDM`);
  from jobs: `ctx.discord`. Null in tests unless stubbed — handle null with 503 `discord_unavailable`.
- **Web:** plain React function components, `textContent`-safe JSX only (no `dangerouslySetInnerHTML`), strings via
  `t()` from your area's `i18n/<area>.ts` (th + en), API calls in your `api/<area>.ts` with `request()`.
- **Tests:** vitest; DB tests via `openTestDb()` from `@nakara-tickets/db/test-support` (beforeAll / beforeEach reset /
  afterAll close); server tests build the app with `buildApp` + `installAll` or stub `app.requireStaff`; web tests
  jsdom + testing-library with stubbed `fetch`. Every test can fail; include a negative case.
- Do not run any shell command; file tools only. Never print connection strings, passwords, tokens or keys.
