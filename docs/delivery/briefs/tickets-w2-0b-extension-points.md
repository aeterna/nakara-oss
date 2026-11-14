# Tickets W2-0b · extension points so the five W2 lanes never share a file

**Route:** agy:B · **Gate:** G1 ✅ Pik 2026-11-14 · also read `tickets-w1-common.md`

## Goal
Create empty, typed hooks and files each W2 lane will fill, and register them in the shared files now.

### Discord (`tickets/packages/discord/src`)
1. Stub handler files, each exporting the named async function(s) that only `await interaction.deferReply?.({ephemeral:true})`
   and reply "not available yet" (or for hooks: do nothing):
   - `handlers/archive.ts`: `archiveOnClose(ctx: CloseHookContext): Promise<void>` (L1)
   - `handlers/data.ts`: `handleDeleteMyData(port, db, interaction, deps)` (L1)
   - `handlers/rating.ts`: `ratingOnClose(ctx: CloseHookContext)`, `handleRatingButton(port, db, interaction, deps)`,
     `handleRatingModal(port, db, interaction, deps)` (L3)
   - `handlers/tag.ts`: `handleTagCommand(port, db, interaction, deps)`, `handleTagAutocomplete(db, interaction)` (L4)
   - `handlers/close-hooks.ts`: `runCloseHooks(ctx)` = `await Promise.allSettled([archiveOnClose(ctx), ratingOnClose(ctx)])`,
     logging rejections. `CloseHookContext = { port, db, dataKey, ticket, category, guildSettings, actorId, log }`
     exported from `types.ts`.
2. `handlers/ticket-actions.ts`: after a successful close (button or `/ticket close`), call `runCloseHooks` without
   blocking the reply (fire after `editReply`).
3. `gateway.ts` routing: buttons `nt:rate:<ticketId>:<score>` → `handleRatingButton`; modal `nt:ratefb:<ticketId>:<score>`
   → `handleRatingModal`; command `tag` → `handleTagCommand`; autocomplete for `tag` → `handleTagAutocomplete`;
   command `tickets` subcommand `delete-my-data` → `handleDeleteMyData`. Add the slash definitions: `tag` (option
   `name`, string, required, autocomplete) and `tickets` (subcommand `delete-my-data`).
4. `i18n.ts`: merge per-area dictionaries from new files `i18n/archive.ts`, `i18n/rating.ts`, `i18n/tag.ts`,
   `i18n/data.ts`, each `export default { th: {}, en: {} }`; existing keys stay where they are; `t()` looks in the
   merged map.

### Web (`tickets/apps/web/src`)
5. Pages (stubs rendering a heading from i18n): `pages/Tickets.tsx` (L1), `pages/Privacy.tsx` (L1), `pages/Panels.tsx`
   (L2), `pages/Analytics.tsx` (L3), `pages/Tags.tsx` and `pages/Blocks.tsx` (L4), `pages/GameServers.tsx` (L5).
   Each takes `{ guildId: string; locale: Locale }`.
6. `App.tsx`: nav buttons + routing for all seven pages (order: Tickets, Categories, Panels, Tags, Blocks, Analytics,
   Game servers, Settings, Privacy).
7. `i18n.ts`: same merge pattern with `i18n/{tickets,panels,analytics,tags,servers,privacy}.ts`; add the nav labels
   to those files (th + en).
8. `api/{tickets,panels,analytics,tags,servers,privacy}.ts`: each `export {}` for now with a comment that it uses
   `request` from `../api.js`. Do not change `api.ts` except to make sure `request` and `ApiError` are exported.

### Schema (`tickets/packages/db/src/schema.ts`) — reviewer generates the migration
9. `tickets`: add `archived_at` (timestamptz, null) and `auto_close_warned_at` (timestamptz, null).
   `guild_settings`: add `attachment_quota_mb` (integer, not null, default 500) and `auto_close_warn_hours`
   (integer, not null, default 12).

## Acceptance tests — write first
x1 `packages/discord/test/close-hooks.test.ts`: closing a ticket calls both hooks once, a rejecting hook does not stop
the other or the reply. x2 gateway routing test: each new customId/command reaches its handler (fake interactions).
x3 `apps/web/test/nav.test.tsx`: all nine nav items render and switching shows each page heading. x4 i18n merge: a key
defined only in `i18n/tags.ts` resolves through `t()`. Existing tests stay green.

## Scope
`tickets/packages/discord/src/**` · `tickets/packages/discord/test/**` · `tickets/apps/web/src/**` ·
`tickets/apps/web/test/**` · `tickets/packages/db/src/schema.ts`

## Out of scope
Server (`apps/server`), migrations SQL, lockfiles.
