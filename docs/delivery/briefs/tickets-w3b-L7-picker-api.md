# tickets W3b L7 — server: list a guild's channels and roles for the dashboard pickers
Repo nakara-oss, project `tickets/` (own npm project: Fastify server `apps/server`, React SPA `apps/web`; vitest). Write the failing test first, then the fix. Use your file editing tools only; do not run shell commands (build/test run after you). Edit only files in the scope. No real secrets in code or tests. Keep the change to this task.

Dashboard forms ask staff to paste raw channel and role IDs. A later lane adds pickers in the web; this lane adds the API.
1. `apps/server/src/discord-rest.ts`: add `listGuildChannels(guildId)` (GET `/guilds/{id}/channels`) and `listGuildRoles(guildId)` (GET `/guilds/{id}/roles`) using the existing `request` helper (same timeout, 429 handling and token redaction).
2. New route file `apps/server/src/routes/discord-lookup.ts`, registered in `apps/server/src/routes/index.ts`, staff-only exactly like `routes/categories.ts` (`app.requireStaff`), guild scoped:
   - `GET /api/v1/guilds/{guildId}/discord/channels` → `[{ id, name, type, parentId, position }]` for text (0), announcement (5), forum (15) and category (4) channels, sorted by position;
   - `GET /api/v1/guilds/{guildId}/discord/roles` → `[{ id, name, color, position }]` without `@everyone` (id = guild id) and without managed roles, highest position first.
   Cache each guild's answer in memory for 60 s, at most 200 guilds (drop the oldest). A Discord error returns 502 `{ code: 'discord_unavailable', message }` without the token. Find how the route gets the REST client from how other routes post messages (e.g. `routes/panels.ts`).
3. `tickets/openapi.yaml`: add both paths and their schemas in the style of the existing ones.
Tests: new `apps/server/test/discord-lookup.test.ts` (filtering, sorting, staff-only 401/403, cache hit makes no second fetch, 502 on Discord error), `apps/server/test/discord-rest.test.ts` (paths called).
