# tickets W3b L8 — web: channel and role pickers instead of raw IDs
Repo nakara-oss, project `tickets/` (own npm project; vitest). Write the failing test first, then the fix. Use your file editing tools only; do not run shell commands (build/test run after you). Edit only files in the scope. No real secrets in code or tests. Keep the change to this task.

The server now has `GET /api/v1/guilds/{guildId}/discord/channels` → `[{ id, name, type, parentId, position }]` (type 0 text, 4 category, 5 announcement, 15 forum) and `GET /api/v1/guilds/{guildId}/discord/roles` → `[{ id, name, color, position }]` (see `tickets/openapi.yaml`, `apps/server/src/routes/discord-lookup.ts`). Forms still ask staff to paste raw IDs.
1. New `apps/web/src/api/discord.ts` with `getGuildChannels(guildId)` and `getGuildRoles(guildId)` in the style of `apps/web/src/api/servers.ts`.
2. New `apps/web/src/components/DiscordPicker.tsx`: `ChannelSelect` (single; prop for allowed types; shows `# name` grouped under its category name) and `RoleMultiSelect` (checkbox list with the role colour dot). Both keep working when the lookup fails: show a text input for the raw ID(s) and a short error line, so a form is never blocked. A saved ID that is not in the list is still shown (as the raw ID) and kept.
3. `apps/web/src/pages/Categories.tsx`: parent channel → `ChannelSelect` (thread mode: text/announcement/forum; channel mode: category); staff roles → `RoleMultiSelect`. Table shows names instead of IDs when known.
4. `apps/web/src/pages/Panels.tsx`: the panel's target channel → `ChannelSelect` (text/announcement).
New strings go in `apps/web/src/i18n.ts` (Thai + English).
Tests: new `apps/web/test/discord-picker.test.tsx` (lists, grouping, fallback to text input on error, unknown saved ID kept); `apps/web/test/categories.test.tsx` and `apps/web/test/panels.test.tsx` updated so saving still sends the same IDs.
