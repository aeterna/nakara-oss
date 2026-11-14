# ADR 0003 — Nakara Tickets (`tickets/`, `packages/tickets`): a self-hosted Discord ticket system with a FiveM bridge

- Status: accepted — owner answered Q1–Q7 and Q4b/Q7b as recommended and started W1, 2026-11-14 (W1 PR)
- Date: 2026-11-14
- Related: ADR 0001 (Server Kit: KVP settings, Node `crypto`, measured S1/S3/S5); ADR 0002 (a product under its own
  folder with its own workflow); this repo's `AGENTS.md` hard rules 3, 4, 5, 7 and 8; plan "Nakara Tickets"
  (owner's doc, review findings R1–R14)
- Written by: Claude Code - Claude Opus 5.5

## Context

FiveM servers run their player support on Discord. Paid ticket bots sell categories, ticket panels, transcripts,
analytics, ratings, auto-close, blacklists, saved replies and a FiveM link that lets staff revive, teleport or give an
item to the player who opened the ticket. None of them can be self-hosted or read before it runs. Nakara City has
tickets in game (F1) and on its website, but no running Discord bot and no way to act on a player from outside the
game.

A review of the first plan against this repo, the Nakara repository and Discord's documentation (2026-11-14) found
facts that shape the decisions below:

- Discord's gateway connection belongs to the bot token and covers every guild; two copies that both connect handle
  every event twice.
- On a request-billed serverless platform the CPU is throttled after the response, a cold start can miss Discord's
  3 s interaction deadline, and a game server holding a long-poll keeps an instance billed all day anyway.
- Message Content is a privileged intent; it also applies to REST reads of message history. An app under 10,000 users
  turns it on itself ([Message Content FAQ](https://support-dev.discord.com/hc/en-us/articles/6207308062871)).
- Attachment URLs are signed and expire; Discord documents no refresh endpoint.
- Private threads need no server boost and do not count toward the 500-channel limit.
- Discord's Developer Terms §5 require a privacy policy, deletion on request, encryption at rest and breach notice
  ([Developer Terms](https://support-dev.discord.com/hc/en-us/articles/8562894815383)).
- `fivem-devkit safety` folds a `${convar}` URL only when it is read into a `const` and concatenated
  (`packages/devkit/src/safety/jsscan.js:188-195`); a `let`, `.replace()`, `new URL()` or an options object makes it
  `undeclared-http` (`undeclared-http.js:35-36`, `:61`). Nothing in this repo has made an outbound HTTP request from
  resource code yet.
- `build-release.mjs` chose npm over resource when a package had a `package.json` (fixed in #34).
- npm workspaces do not nest; the root `ci.yml` installs every root workspace for every job.

## Decision

1. **One process, one code path.** `ROLE=all` runs the Fastify API, the dashboard's static files, the discord.js
   gateway and the worker loop in one Node 22 process. `ROLE=migrate` runs migrations once and exits. There is no
   HTTP-interactions mode in v1; a scale-to-zero mode needs its own ADR.
2. **Two ways to run the same image** (`ghcr.io/aeterna/nakara-tickets`, amd64):
   - **A. VM + compose:** `app`, `postgres`, a one-shot `migrate`, and one ingress profile, `caddy` (public IP) or
     `cloudflared` (no inbound port). Every service has a memory limit. Daily `pg_dump`.
   - **B. Serverless container:** the same image on a platform that keeps one instance with CPU always on (minimum
     and maximum 1), an external Postgres in session mode (not a transaction pooler), and S3-compatible storage
     for attachments. It is billed as always-on; the docs say so.
3. **A single gateway per Discord application.** The process takes a Postgres advisory lock keyed by the application
   id on a dedicated connection before it connects. A second copy waits and reports `standby` on `/healthz`.
4. **Data.** Postgres 17 through Drizzle. Every table carries `guild_id`; every query goes through a helper that
   requires it. Tables: `guilds`, `guild_settings`, `categories`, `panels`, `tickets`, `ticket_members`, `messages`,
   `attachments`, `ratings`, `tags`, `blocks`, `game_servers`, `pair_codes`, `bridge_nonces`, `game_actions`,
   `data_requests`, `audit_log`, `sessions`. Transcript text and attachments are encrypted at rest (AES-256-GCM, key
   from `TICKETS_DATA_KEY`); attachments are downloaded only from `cdn.discordapp.com` and `media.discordapp.net`
   when a ticket closes, within a per-file and per-guild cap. Transcripts expire after the guild's retention
   (default 90 days).
5. **Discord surface.** Intents `Guilds`, `GuildMessages`, `GuildMembers` and `MessageContent`. Tickets are private
   threads by default; a category may use channels instead. Forms are modals of at most 5 Label components. Bot
   permissions: View Channels, Send Messages, Send Messages in Threads, Create Private Threads, Manage Threads,
   Manage Channels (only for channel categories), Embed Links, Attach Files, Read Message History; never
   Administrator. The instance answers only guilds in `ALLOWED_GUILD_IDS` and leaves any other; the docs tell the
   operator to turn off "Public Bot". Upload limits are read from the API (`attachment_size_limit`), never
   hard-coded. A rating request is a button in the closed ticket; a DM is sent once and only when the guild opts in,
   and error 50007 is ignored.
6. **Dashboard.** Discord OAuth2 with scopes `identify guilds`, `state` and PKCE; the access token is discarded after
   login. Staff = the Manage Server permission or a configured role, re-checked through the bot on every write
   (60 s cache). Session cookie `HttpOnly`, `SameSite=Lax`, plus a CSRF token on writes. Files and transcripts are
   served with `Content-Disposition: attachment`, `X-Content-Type-Options: nosniff` and a CSP without scripts.
7. **Contract.** `tickets/openapi.yaml` is the single API contract: `/api/v1` (dashboard), `/auth` (OAuth),
   `/bridge/v1` (game servers), `/healthz`, `/metrics`. The dashboard's client is generated from it.
8. **The bridge is outbound only.** `nakara_tickets` never calls `SetHttpHandler`, so it needs no `httpHandlers`
   capability, opens no port and works behind the Cfx proxy.
   - Pairing: the dashboard issues a one-time code of at least 40 bits, valid 10 minutes, bound to one guild. Staff
     type `nakara_tickets pair <code>` in the server console (the handler checks `source == 0`). The resource
     exchanges it for a `server_id` and a secret and stores both in KVP; it never reads a secret from a convar
     (hard rule 4). The dashboard shows the server's name for staff to confirm, and can revoke it.
   - Every request carries an HMAC-SHA256 over timestamp, nonce, method, path and body. The API refuses a skew over
     60 s or a nonce seen before (`bridge_nonces`). The secret is encrypted at rest on the API side.
   - Commands: `GET /bridge/v1/actions?wait=25` returns an action with a 30 s lease; the resource keeps the ids it
     has executed (memory plus a small KVP list covering the 60 s action lifetime) and answers a repeated id with
     the stored result; `POST /bridge/v1/actions/{id}/result` is retried with the same id until accepted. A lease
     that expires without a result re-sends the same id. The dashboard asks for confirmation before a second
     `give_item` for the same ticket, item and player within 10 minutes.
   - Success is judged on a response body that matches the schema, never on the status code alone.
   - The resource reads one convar, `nakara_tickets_api`, into a `const` and builds every URL by concatenation.
   - **Transport: global `fetch` in server JS, never `PerformHttpRequest`.** The W0 spike (branch
     `spike/tickets-bridge`, `tickets/spike/README.md`, 2026-11-14, Legacy 35245 and Enhanced b170) measured: `fetch`
     exists in both editions, moves GET and POST bodies of 1–64 KiB intact, holds 25 s and 55 s requests, and throws on
     a refused or unresolvable host. `PerformHttpRequest` on Enhanced stops at about 10 s and reports status 200 with
     an empty body on that timeout and on refused and unresolvable hosts, so it can neither long-poll nor tell success
     from failure there. Enhanced's 8 KiB limit (ADR 0001 S1) applies to inbound bodies only; outbound was not limited.
9. **Actions and adapters.** Built in: `player.info` (standalone, `qbx_core`), `player.teleport` to named spots from
   the resource's config (standalone), `player.revive` through `qbx_medical`, `player.give_item` through
   `ox_inventory`. Other actions register with `exports.nakara_tickets:registerAction(name, schema, fn)`. The
   resource's config holds the item allowlist, quantity caps and enabled actions, and is final: the API cannot ask for
   more. `give_item` is off by default. Every action is audit-logged and posted as a line in the ticket.
10. **Hard rule 5 is extended for this package** (owner, Q7b, 2026-11-14): `nakara_tickets` may call `qbx_medical`
    (revive) and `ox_inventory` (add item) only when `GetResourceState` says they are started and the server owner
    enabled the action in config; neither is a dependency. qb-core and es_extended adapters are not shipped; a
    community PR that adds one must include results from a real server.
11. **Where.** `tickets/` is its own npm project with its own `package.json` workspaces and lockfile, outside the
    root workspaces; `packages/tickets/` is the resource. The safety scanner covers only `packages/` and
    `templates/`, so `tickets/` is checked by eslint, `npm audit` and a license check (MIT, Apache-2.0, BSD, ISC) in
    `.github/workflows/tickets.yml`, which every PR triggers and which exits early when neither folder changed
    (org §11.1). A release tag `nakara-tickets@<version>` covers the image and the resource zip, both with build
    provenance.
12. **Personal data.** `deploy/PRIVACY-TEMPLATE.md` is a privacy policy the operator fills in and links in the
    Developer Portal. `/tickets delete-my-data` and a web route record a `data_requests` row and delete that user's
    messages, attachments and ratings; export and uninstall commands cover a whole guild. Each instance is its own
    Discord application, so its operator carries the duties in the Developer Terms; the README says so.

## Consequences

- A server owner can run the whole system from one image, on a VPS or a container platform, and read every line
  first; the resource passes the same scanner as every other package.
- The serverless mode is not cheaper than a small VM; it trades OS upkeep for an always-on instance.
- A compromised dashboard can queue actions, but cannot exceed the allowlist and caps in the game server's config.
- The bridge depends on `fetch` staying available in FXServer's server JS; the spike measured it on Legacy 35245 and Enhanced b170 only.
- Transcripts are personal data under the operator's control; the project ships the tools, not the compliance.
- Nakara runs it on its own small VM (Q4b), not on the production database VM, which has 2 GB and no public IP.
