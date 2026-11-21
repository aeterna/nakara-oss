# tickets UI polish — names instead of user IDs, Thai status badge, picker labels
Repo nakara-oss, project `tickets/` (own npm project: Fastify server `apps/server`, React SPA `apps/web`; vitest). Write the failing tests first, then the fix. Use your file editing tools only; do not run shell commands (build/test run after you). Edit only files in the scope. No real secrets in code or tests. Keep the change to these three items.

Found in the live test on 2026-11-21 (dashboard in Thai):

1. **Ticket list and ticket page show raw Discord user IDs** for the opener (`ผู้แจ้ง`) and the claimer (`ผู้ดูแล`). Show the member's display name instead.
   - `apps/server/src/discord-rest.ts`: add `getGuildMember(guildId, userId)` (GET `/guilds/{guildId}/members/{userId}`) with the existing `request` helper (same timeout, 429 handling, token redaction).
   - `apps/server/src/routes/discord-lookup.ts`: add `GET /api/v1/guilds/{guildId}/discord/members?ids=<id>,<id>` — staff only and guild scoped exactly like the channels/roles routes in that file. Accept at most 50 ids; every id must match `/^[0-9]{17,20}$/` (else 400 `{ code: 'invalid_ids' }`); duplicates count once. Answer `[{ id, name }]` where name = member `nick`, else `user.global_name`, else `user.username`. Cache each guild+user name in memory for 10 minutes, at most 2000 entries (drop the oldest); also cache a "not found" (Discord 404) for 10 minutes and leave that id out of the answer. Fetch at most 5 members at a time. Any other Discord error for one id: leave it out of the answer (do not fail the whole request) and do not cache it. Extend `clearDiscordLookupCache` to clear this cache too.
   - `tickets/openapi.yaml`: add the path and schema in the style of the channels/roles paths.
   - `apps/web/src/api/discord.ts`: add `getGuildMembers(guildId, ids)`.
   - `apps/web/src/pages/Tickets.tsx`: after the list (and the selected ticket) load, ask for the names of the opener and claimer ids on screen in one call; render the name, with the raw id in a `title` attribute; while loading or when a name is missing, render the id as today. A failed lookup must not break the page.
2. **Status badge text is English** (`CLAIMED`, `open`, `closed`) in both the list and the ticket page. Render the existing i18n labels `statusOpen` / `statusClaimed` / `statusClosed` for the dashboard locale (keep the badge CSS classes as they are).
3. **Labels of fields that are now pickers still say "ID"**:
   - `apps/web/src/i18n.ts`: `parentChannelId` → th `ช่องหลัก (Parent Channel)`, en `Parent Channel`; `staffRoleIds` → th `บทบาททีมงาน (Staff Roles)`, en `Staff Roles`. Leave `logChannelId` as it is (Settings still uses a text box).
   - `apps/web/src/i18n/panels.ts`: `channelId` → th `ช่อง Discord (Channel)`, en `Channel`; add `channelRequired` → th `กรุณาเลือกช่อง`, en `Choose a channel`.
   - `apps/web/src/pages/Panels.tsx`: the hard-coded `'Channel ID is required'` message uses `channelRequired`.

Tests:
- `apps/server/test/discord-lookup.test.ts`: members route — staff-only 401/403, 400 on a bad id and on more than 50 ids, name order nick → global_name → username, cache hit makes no second fetch, a 404 id is left out and cached, another error leaves only that id out.
- `apps/server/test/discord-rest.test.ts`: `getGuildMember` path.
- new `apps/web/test/tickets.test.tsx` (copy the setup and fetch mocking of `apps/web/test/categories.test.tsx`): list shows names with the id in `title`; falls back to the id when the lookup fails; badge shows `statusClaimed` text in Thai.
- `apps/web/test/i18n.test.ts` / `apps/web/test/panels.test.tsx`: update any assertion on the old label text.
