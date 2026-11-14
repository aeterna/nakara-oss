# Tickets W1 · L3 · dashboard: Discord login, guild picker, categories, settings

**Route:** agy:B · **Gate:** G1 ✅ Pik 2026-11-14 · also read `tickets-w1-common.md` · ADR 0003 decision 6

## Goal
Staff log in with Discord, pick a guild they manage, and edit ticket categories and guild settings in the browser.

### Server (`tickets/apps/server/src`)
1. `session.ts`: `installSession(app, { config, db })` registers `@fastify/cookie` and decorates:
   - `app.requireUser` preHandler: cookie `nt_session` (random 32 bytes, base64url) → `sessions` row by
     `sha256(token)` (`token_hash`), not expired; sets `req.user = { id, username, avatar }`. 401 otherwise.
   - `app.requireStaff` preHandler for routes with `:guildId`: requireUser, guild in `ALLOWED_GUILD_IDS`, and
     `checkStaff` true; sets `req.guildId`. 403 otherwise.
   - CSRF: every non-GET under `/api/v1` needs header `X-CSRF-Token` equal to the session's csrf value
     (constant-time compare). 403 `csrf` otherwise.
   - Cookie: `HttpOnly`, `Secure` unless `PUBLIC_ORIGIN` is http://localhost, `SameSite=Lax`, `Path=/`, 7-day expiry.
2. `staff.ts`: `checkStaff({ token, fetchImpl = fetch }, guildId, userId, staffRoleIds)` reads
   `GET https://discord.com/api/v10/guilds/{guildId}/members/{userId}` and the guild roles with the bot token,
   computes permissions, calls `isStaff` from core; caches the result 60 s per guild+user.
3. `routes/auth.ts` (replace stubs): getAuthLogin → redirect to Discord authorize with scopes `identify guilds`,
   `state` + PKCE S256 kept in a short-lived signed cookie; getAuthCallback → exchange code (fetch), read the user,
   create the session, discard the Discord access token, redirect to `/`; postAuthLogout deletes the session.
4. `routes/me.ts`: getMe → user + guilds from `ALLOWED_GUILD_IDS` where `checkStaff` is true (guild names from
   `guilds` table, `ensureGuild` on first sight). deleteMeData stays 501 (W2).
5. `routes/categories.ts` and `routes/settings.ts`: CRUD with `requireStaff`, zod bodies matching openapi, calling
   L1's `listCategories / createCategory / updateCategory / deleteCategory / getSettings / updateSettings`
   (signatures in `tickets-w1-l1-core.md`). `TicketError('not_found')` → 404, `limit` → 409.

### Web (`tickets/apps/web`)
6. Vite + React SPA: `index.html`, `vite.config.ts` (build to `dist/`, dev proxy `/api` `/auth` → :8080),
   `tsconfig.json`, `src/main.tsx`, `src/api.ts` (fetch wrapper adding `X-CSRF-Token` from `GET /api/v1/me`),
   pages: Login, GuildPicker, Categories (list, create, edit form incl. staff roles, mode, parent channel id,
   name template, max open), Settings (locale, retention days, log channel, rating DM, privacy URL).
   `src/i18n.ts` with `th` (default) and `en`. Plain CSS in `src/styles.css`, no UI framework, no `innerHTML`.

## Acceptance tests — write first
Server (`apps/server/test/`, Fastify `inject`, pglite, fetch stubbed): a1 no cookie → 401; a2 valid session, not
staff → 403; a3 staff, guild not in allowlist → 403; a4 POST without CSRF → 403, with → 201; a5 category of guild A
not reachable via guild B → 404; a6 callback rejects a wrong `state`; a7 callback stores only the token hash (row
does not contain the cookie value); a8 `checkStaff` cached (second call does not fetch).
Web (`apps/web/test/`, jsdom + testing-library): w1 Categories renders rows from a stubbed api; w2 create form posts
the right body; w3 language switch changes a label.

## Scope
`tickets/apps/server/src/{session,staff}.ts` · `tickets/apps/server/src/routes/{auth,me,categories,settings}.ts` ·
`tickets/apps/server/test/{session,auth,categories}.test.ts` · `tickets/apps/web/**` except `package.json`

## Out of scope
Tickets list / transcript pages (W2), panels editor (W2), game servers (L4), `app.ts` wiring (W1-int calls
`installSession(app, { config, db })`).
