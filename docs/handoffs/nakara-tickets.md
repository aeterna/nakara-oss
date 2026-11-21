# Handoff · Nakara Tickets (`tickets/`, `packages/tickets`)

Written by: Claude Code - Claude Opus 5.5 · 2026-11-15 · Decision record: [ADR 0003](../adr/0003-nakara-tickets.md) (accepted)
Plan and live status table (owner's doc): https://claude.ai/artifact/RvXxBw8wnhYMrkK3mYEmEZ

## Status now

| Wave | What | State | Evidence |
|---|---|---|---|
| W0 | release script fix, ADR 0003, `openapi.yaml`, schema + migration, route stubs, CI workflow | merged | #34 `7db5315` · #35 `8a36db0` · #36 `37cf907` |
| W1 | core (crypto, HMAC, state machine), Discord gateway, dashboard login/categories/settings, bridge API, resource `nakara_tickets` (pair, signed `fetch` long-poll, info/teleport) | merged | #39 `7b3b343` |
| W2 | end-to-end wiring + esbuild image, transcripts + attachment archive (local/S3), personal data (delete/export/retention), panel designer, analytics + ratings + audit, auto-close + `/tag` + blocks, revive/give_item + repeat-confirm + results in Discord, game servers page | merged | #40 `4f852c1`; main CI runs 43617424598 + 43617424610 success |
| W3a | Live test on the owner's Windows host instead of a VM (owner's pick, 2026-11-20): real Discord bot, dashboard on the tailnet, clean qbx FXServer Enhanced (kit-test) | **passed** after six fixes; test setup removed | fixes #79 `190d178` · method + handoff #77 `18dbf51` (both merged 2026-11-20) |
| W3b-UI | UI bugs from the W3a test + the five Q3 minors on the resource, plus channel/role pickers (2026-11-20, owner's order) | **passed** live retest 2026-11-21 (kit-test + live dashboard) | #83 `4550b63` (merged 2026-11-21); briefs `docs/delivery/briefs/tickets-w3b-*.md` |
| W3b | Nakara deploy: own small VM (Q4b), a Discord app of its own, panel in the support channel, private adapter in nakara-city | not started — owner decides (VM price first) | — |
| W4 | release `nakara-tickets@0.1.0` (image + resource zip with provenance), public announcement | **released 2026-11-21** from `main` `f21a957`: release + zip + SHA256SUMS, image `ghcr.io/aeterna/nakara-tickets:0.1.0` public, provenance verified for zip and image; Thai/English release notes; post in Discord `#📦・releases`; README + site catalog live | release run 44873581484 · UI polish #87 `f44986a` · promotions #86 #88 #90 #93 · catalog #89 · Pages fix #91 |

Verified on `main` (local, 2026-11-14): vitest 233/233 three runs in a row, `tsc -b` 0, web build, server bundle,
`npm audit --omit=dev --audit-level=high` 0, root `npm run ci` exit 0, `fivem-devkit safety` 0 errors 0 warnings, and
`docker compose up` twice in a row with dummy secrets (migrate `Applied 2` then `Applied 0`, `/healthz` 200 `db:up`, SPA
200, `/api/v1/me` 401, `/metrics` 404 without token, `/auth/login` 302 to Discord, `/data/files` writable, container
healthy). Two Q3 reviews per wave by another model; every blocker and major fixed.

**Proven on 2026-11-20 (W3a):** gateway login, slash-command registration, panel post, ticket open + claim in a private thread, dashboard login as the guild owner, pairing + heartbeat, and all four game actions on FXServer Enhanced (info, teleport, give_item with the inventory read back, revive of a dead character). **Still not verified:** rating DMs, transcripts on close, S3, and Legacy. The W3a run first failed on six bugs every spec had passed (#79).

**Earlier note (2026-11-15) — not verified then:** a real Discord bot (gateway login, slash commands, rating DMs, panels in a live guild), a real
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

1. **W3b** (Nakara deploy): approve the VM machine type and monthly price before it is created (AGENTS §15.2),
   create the Discord application (turn off Public Bot, enable the four intents) and put the token in the VM's secret
   files yourself, pick the support channel for the first panel.
2. Done: real-server test of `player.revive` and `player.give_item` (W3a), and the AETERNA Game bot token was reset and its env file updated (the bot posted the release on 2026-11-21).
3. Done 2026-11-21: **W4** release. The owner ran `tickets-release` from `main`, approved `release`, allowed public packages in the org settings (Packages → Package creation → Public) and set `nakara-tickets` to Public. Next release: same steps, no visibility change (`docs/maintainers/tickets-release.md`).
4. Done 2026-11-21: live retest of W3b-UI. The Discord channel `#oss-test` (under STAFF in the AETERNA Game guild) is kept for later live tests at the owner's request; everything else opened for the test was removed (list in the log below).
5. Optional: delete the leftover ref `delegate/tkt-l6-res-20261120-220629-a1f602` in the Mac checkout (`git branch -D …`). It holds no work (its tip is commit 1 of the merged #83, no worktree), but `closeout` cannot prove a discarded run and the §4.1 hook blocks a forced delete by an agent.

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
- 2026-11-20 — W3a live test (owner chose the Windows host, borrowed the AETERNA Game app, test channel under STAFF). Six bugs found and fixed with failing-first tests: guild owner not staff; relative `require` from the resource root; `rawCommand` replacing the api in the pair command; Lua-only `GetPlayers` and `GetPlayerIdentifiers` in JS; string player ids and multi-value export returns. PR #79 (Q3 Sonnet: no blocker, no major; five minors listed there). Method written as `docs/maintainers/live-test.md` (#77). Test setup removed the same day: channel, rcon, diagnostics resource, stack and secrets on the host, tailscale serve, bot intents and redirect. UI issues seen (not fixed): category edit button, snake_case vs camelCase in the category table, no game-server field, raw IDs in forms, guild name `Guild <id>`, English panel defaults, repeat-confirm counting a failed action, server list not refreshing after pairing; FXServer logs `Reader released` on each long-poll cycle (non-fatal). — Claude Code - Claude Opus 5.5

- 2026-11-20 — W3b-UI (owner's order "fix the noted UI bugs and the five Q3 minors, then W4"): eight engineer lanes in parallel (agy), then six reworks. Fixed: categories API snake_case → camelCase (the old server test mocked the db in camelCase, so it passed while the real API did not), edit button, game-server field, clearing fields with null, game server checked against the guild; real guild name from the gateway and Discord (placeholder never overwrites a real name, failed lookups cached 60 s); server list refreshes while pairing; tickets empty state; info result shown; panel defaults follow the dashboard language; repeat-confirm ignores failed actions; result message in the guild's language with a non-pinging mention; new staff-only `/discord/channels` + `/discord/roles` (60 s cache) and pickers in categories and panels. Resource: config via `LoadResourceFile`, loader falls back only when the missing module is the requested one (FXServer reports the resolved absolute path — an earlier attempt matched `./x.js` and would have broken loading), shared `players.js`, `Revive` false = failure, `Number.isFinite` on the id, long-poll timer cleared (cause of `Reader released`: an uncleared `AbortSignal.timeout` firing after the body was read). Rejected along the way: a rewrite that hid the `fetch(API + …)` pattern from the safety scanner, and a new `playerId` target path that could reach a player other than the ticket owner. Q3 (Sonnet): no blocker, one major (fields could not be cleared) fixed with four minors. Local: vitest 272/272 ×3, tsc ×3, vite build, bundle, audit, root `npm run ci`, busted, safety 0/0, DCO; compose smoke on the digest-pinned image passed. Not yet run on a real FXServer or live dashboard. — Claude Code - Claude Opus 5.5
- 2026-11-21 — W3b-UI live retest (owner's order "merge + retest"; #83 and #84 merged by the owner's order). Stack rebuilt from `dev` on the Windows host (BuildKit failed over ssh with `PROTOCOL_ERROR`; the legacy builder `DOCKER_BUILDKIT=0` worked), fresh database, borrowed AETERNA Game app again (owner reset and pasted the token and client secret himself via `put-secret.sh`). Passed on kit-test + live dashboard: real guild name; Thai empty state; server list refreshed by itself after pairing; channel and role pickers; category game-server field; category edit opens filled and clearing the welcome message stores NULL; Thai panel defaults, panel posted; `player.info` result shown; revive, give_item (water ×1) and teleport done; an `over_cap` request (count 11 > cap 2) refused and not counted by repeat-confirm; result messages in Thai with a mention of the requester. Correction to the entry above: clearing the long-poll timer did not stop `Reader released`. Measured with a throwaway probe: FXServer's Node v26.3.0 logs it for every `fetch` with a request body (all body forms), never for one without; responses arrive normally. So the resource logs it at pairing and on each heartbeat; recorded as a known issue (CHANGELOG, README, `live-test.md`). Small UI notes, not fixed: the ticket page shows requester/claimer as raw user ids, the status badge is English, two picker labels still say "ID". Test access removed at the end: rcon, `nkt_diag`, `[tickets]` resources, test stack and secrets, `tailscale serve`, bot intents and redirect. Kept: `#oss-test` channel (owner's request). — Claude Code - Claude Opus 5.5
- 2026-11-21 — UI polish before the 0.1.0 release (owner's order "fix the 3 UI spots before release"): member names instead of raw user ids on the ticket list/page (new staff-only `/discord/members`, 10 min cache), Thai status badge, picker labels without "ID". Engineer runs `20261121-100439-d7313b` + two test-label reworks (agy fell back to Claude CLI haiku). Local: vitest 286/286 ×3, tsc, web build, audit, root ci. Not checked on a live dashboard. — Claude Code - Claude Opus 5.5
- 2026-11-21 — W4 closed (owner's orders "Merge + promote", "Released", "ทำข้อ 1 + 2 · 3 use bot"). #87 merged `f44986a`, promoted to `main` `f21a957` (#88). The owner ran `tickets-release` (run 44873581484: test + bundle, publish both success). Tag and release `nakara-tickets@0.1.0` on `f21a957` with `nakara_tickets-0.1.0.zip` + `SHA256SUMS` (checksum OK); image `ghcr.io/aeterna/nakara-tickets:0.1.0` set Public by the owner after allowing public packages in the org settings (anonymous manifest pull HTTP 200); `gh attestation verify` passed for the zip and the image (SLSA v1, `tickets-release.yml@refs/heads/main`). Release notes got a Thai/English intro above the changelog. The AETERNA Game bot posted the release in `#📦・releases`, in the same one-line style as the GitHub app's rongroi posts. README (EN/TH) and site (TH/EN) got a released-scripts catalog (#89, promoted #90). The Pages deploy then failed three times in a row: `deploy-pages` listed no artifacts one second after the upload in the same job. Fixed by splitting build and deploy into separate jobs (#91, promoted #93; Pages run 44877235893 success, live site checked). Run branches of the W3b-UI and polish waves were cleared with the new `closeout` proof from merged PR commits (org-standards#177); 18 of 19 removed, L6 left (owner's item 5). — Claude Code - Claude Opus 5.5

## Lessons kept for the next waves

- A PR is not "working" until the image runs: always do the compose smoke, not only unit tests.
- Delegate gotchas: `--scope` is comma-separated (a repeated flag keeps only the last); default `--max-diff-lines` is 500;
  split runs that may exceed 15–25 min; the preflight refuses secret-looking strings (`gitleaks:allow` on fake fixtures);
  when agy and the free engines hit quota, runs fall back to the paid `claude` engine (about $0.60 on 2026-11-14).
- Same check failing twice ⇒ diagnose before re-briefing (AGENTS §5.6); in W1–W2 the cause was usually the test (locale, jsdom
  `confirm`, stream timing) and sometimes the product (`@fastify/static` `setHeaders` signature).
- 2026-11-20 — #79 merged as `190d178`, #77 as `18dbf51` (owner's order). Work branches and Mac worktrees closed out with `tools/closeout` (manifest in the workspace `backups/`). Nine `delegate/task-20261120-*` branches stay in the Windows host's fleet bare repo: `closeout` cannot prove them there (no GitHub remote), so they wait for the fleet `--delegate-gc` tool. Next: W3b. — Claude Code - Claude Opus 5.5
- A Pages job that uploads and deploys in one job can fail on artifact-list lag: keep `build` and `deploy` as separate jobs.
- Engines in write mode cannot run tests: every round left 1–4 failing tests that only the Orchestrator's own vitest run found. Run the full suite after each applied run, and put the measured cause in the next brief (§5.6) — it cut the reworks from guesswork to one-liners.
- A test that mocks the db layer can pass while the real API is wrong (categories camelCase): prefer the pglite test db.
