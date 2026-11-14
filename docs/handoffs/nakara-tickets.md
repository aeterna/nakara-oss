# Handoff · Nakara Tickets (`tickets/`, `packages/tickets`)

Written by: Claude Code - Claude Opus 5.5 · 2026-11-15 · Decision record: [ADR 0003](../adr/0003-nakara-tickets.md) (accepted)
Plan and live status table (owner's doc): https://claude.ai/artifact/RvXxBw8wnhYMrkK3mYEmEZ

## Status now

| Wave | What | State | Evidence |
|---|---|---|---|
| W0 | release script fix, ADR 0003, `openapi.yaml`, schema + migration, route stubs, CI workflow | merged | #34 `7db5315` · #35 `8a36db0` · #36 `37cf907` |
| W1 | core (crypto, HMAC, state machine), Discord gateway, dashboard login/categories/settings, bridge API, resource `nakara_tickets` (pair, signed `fetch` long-poll, info/teleport) | merged | #39 `7b3b343` |
| W2 | end-to-end wiring + esbuild image, transcripts + attachment archive (local/S3), personal data (delete/export/retention), panel designer, analytics + ratings + audit, auto-close + `/tag` + blocks, revive/give_item + repeat-confirm + results in Discord, game servers page | merged | #40 `4f852c1`; main CI runs 43617424598 + 43617424610 success |
| W3 | Nakara deploy: own small VM (Q4b), Discord app, panel in support channel, private adapter in nakara-city | **not started — owner decides** | — |
| W4 | release `nakara-tickets@0.1.0` (image + resource zip with provenance), public announcement | not started — owner decides | — |

Verified on `main` (local, 2026-11-14): vitest 233/233 three runs in a row, `tsc -b` 0, web build, server bundle,
`npm audit --omit=dev --audit-level=high` 0, root `npm run ci` exit 0, `fivem-devkit safety` 0 errors 0 warnings, and
`docker compose up` twice in a row with dummy secrets (migrate `Applied 2` then `Applied 0`, `/healthz` 200 `db:up`, SPA
200, `/api/v1/me` 401, `/metrics` 404 without token, `/auth/login` 302 to Discord, `/data/files` writable, container
healthy). Two Q3 reviews per wave by another model; every blocker and major fixed.

**Not verified yet:** a real Discord bot (gateway login, slash commands, rating DMs, panels in a live guild), a real
FiveM server running `nakara_tickets` against a deployed API (`qbx_medical` `Revive` and `ox_inventory` `AddItem` —
names taken from Nakara's own server code), S3 against a real endpoint. W3 is where these get proven.

## Short rules for other sessions

- `tickets/` is its own npm project (own lockfile, outside root workspaces). Work in `tickets/`: `npm ci`, `npx vitest run`,
  `npx tsc -b`, `cd apps/web && npx tsc --noEmit -p . && npx vite build`, `npm run build:server`. Delete `dist/` and
  `*.tsbuildinfo` after `tsc -b` before committing (`tickets/.gitignore` guards emitted files).
- The resource `packages/tickets` is a root workspace: `npm test --workspace packages/tickets` and the root
  `fivem-devkit safety` cover it. Its URL must stay `const API = GetConvar('nakara_tickets_api', '')` + concatenation.
- Contract = `tickets/openapi.yaml`. Every query is guild scoped (`inGuild`). Bot posts with user or game text use
  `allowed_mentions: { parse: [] }`.
- Image = one esbuild bundle `server.mjs` (`npm run build:server`); `ROLE=migrate` uses the drizzle journal and needs only
  `DATABASE_URL`. Run a compose smoke before claiming the image works (recipe below).
- New migrations: edit `packages/db/src/schema.ts`, then `cd tickets/packages/db && npx drizzle-kit generate --name <slug>`.
- Never commit `tickets/secrets/` (ignored); never put real secrets in tests or briefs.
- Briefs and every rework round are in `docs/delivery/briefs/tickets-*.md` (W0 → W2 rework-5); read them before
  changing the same area.

### Compose smoke (how W2 was proven)
Copy `tickets/` to a scratch folder (exclude `node_modules`, `dist`, `secrets`), write dummy values to
`secrets/{postgres_password,database_url,tickets_data_key,discord_token,discord_client_secret,cloudflared_token}.txt`
(`database_url` = `postgres://postgres:<pw>@postgres:5432/tickets`, key = 32 random bytes base64), export
`DISCORD_APP_ID` and `ALLOWED_GUILD_IDS` (any snowflake), `docker compose up -d postgres migrate app` twice, probe with
`docker compose exec -T app node -e "fetch('http://127.0.0.1:8080/healthz').then(r=>r.text()).then(console.log)"`.
Remove the scratch folder and the image afterwards.

## Owner's pending items

1. **Start W3** (Nakara deploy): approve the VM machine type and monthly price before it is created (AGENTS §15.2),
   create the Discord application (turn off Public Bot, enable the four intents) and put the token in the VM's secret
   files yourself, pick the support channel for the first panel.
2. During W3, one real-server test of `player.revive` and `player.give_item` (both off by default in `config.json`).
3. **W4** release and any public announcement (AGENTS §6).

## Rollback

- Code: every wave is one squash commit on `main` (`7db5315` … `4f852c1`); revert the wave's commit in a PR.
- Nothing is deployed and no Nakara server loads `nakara_tickets`, so there is no runtime to roll back yet.
- After W3: `stop nakara_tickets` on the game server, stop the VM/compose stack; Nakara's own in-game and web ticket
  queues keep working (no shared tables). Database backups are daily `pg_dump` in the `backup` service volume.

## Log (in order)

- 2026-11-14 — Researched AR Ticket Tool (paid FiveM Discord ticket bot); wrote the plan; owner answered Q1–Q7, Q4b
  (separate small VM), Q7b (only `qbx_medical` + `ox_inventory` adapters); plan scrutinized (R1–R14).
- 2026-11-14 — W0: release-script fix #34, ADR + openapi + hard rule 5 extension #35, scaffold #36. Spike on Legacy
  35245 + Enhanced b170 chose global `fetch` over `PerformHttpRequest` (Enhanced reports 200 on timeout/refusal); spike
  branch deleted after W1 (manifest `fivem/backups/branch-cleanup-2026-11-14/manifest.txt`).
- 2026-11-14 — W1: W1-0 shared foundations + 5 lanes + 3 reworks; Q3 found an HMAC key mismatch, a pairing race,
  fail-open staff routes and safety-scan failures — all fixed; merged #39. Gap found later: wiring never done.
- 2026-11-14 — W2: W2-0 wired the server and fixed the image (found by a real compose run); 6 lanes; 5 reworks (Q3
  blockers: migration replay, archive SSRF via redirects, unbounded download; plus a CSRF test regression, a
  `@ts-ignore` hiding a missing export, a test-design flaw in the stream-cancel test); merged #40.
- 2026-11-15 — This handoff.

## Lessons kept for the next waves

- A PR is not "working" until the image runs: always do the compose smoke, not only unit tests.
- Delegate gotchas: `--scope` is comma-separated (a repeated flag keeps only the last); default `--max-diff-lines` is 500;
  split runs that may exceed 15–25 min; the preflight refuses secret-looking strings (`gitleaks:allow` on fake fixtures);
  when agy and the free engines hit quota, runs fall back to the paid `claude` engine (about $0.60 on 2026-11-14).
- Same check failing twice ⇒ diagnose before re-briefing (AGENTS §5.6); in W1–W2 the cause was usually the test (locale, jsdom
  `confirm`, stream timing) and sometimes the product (`@fastify/static` `setHeaders` signature).
