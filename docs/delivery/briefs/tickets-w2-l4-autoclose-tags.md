# Tickets W2 · L4 · auto-close, saved replies (/tag), blacklist UI

**Route:** agy:B · also read `tickets-w2-common.md`

## Goal
1. `apps/server/src/discord-rest.ts`: add `patchChannel(channelId, body)` (same timeout/429/error handling). You are the
   only lane editing this file.
2. `apps/server/src/jobs/auto-close.ts` `run`: for open/claimed tickets whose category has `auto_close_hours`:
   inactive (`last_activity_at`, else `created_at`) ≥ `auto_close_hours − auto_close_warn_hours` and not warned →
   post a warning line (i18n by guild locale) and set `auto_close_warned_at`; inactive ≥ `auto_close_hours` →
   `transitionTicket(close, actor 'system', reason 'auto-close')`, post a line, `patchChannel({archived:true, locked:true})`
   for threads. Activity after the warning (a newer `last_activity_at`) clears the warning (`auto_close_warned_at = null`).
   At most 200 tickets per run; discord null → transition only. Never throws per ticket (log, continue).
3. `apps/server/src/routes/tags.ts` (CRUD) and `routes/blocks.ts` (list/create/delete): zod per openapi; tag name
   `^[a-z0-9-]{1,32}$`, unique per guild (409), body ≤ 2000; block `user_id` snowflake, reason ≤ 500, unique per guild.
4. `packages/discord/src/handlers/tag.ts`: `/tag name:<tag>` (staff only) posts the tag body in the channel with
   variables `{user}` (ticket opener mention), `{staff}` (invoker mention), `{ticket}` (number), `{server}` (guild
   name), unknown `{x}` left as is; mentions limited with `allowed_mentions: { users: [opener] }`. Autocomplete returns up
   to 25 tag names starting with the typed text. `i18n/tag.ts`.
5. Web `pages/Tags.tsx` (list, create, edit with variable help, delete) and `pages/Blocks.tsx` (list with reason and
   date, add by user id, remove). `api/tags.ts`, `i18n/tags.ts` (both pages).

## Acceptance tests — write first
a1 auto-close: warn once at the threshold, close at the limit, activity after warning resets, category without
`auto_close_hours` untouched, discord null still closes. a2 tags: duplicate name 409, bad name 400, guild scoped. a3 blocks
duplicate 409. a4 `/tag` variable substitution and `allowed_mentions`; non-staff refused; autocomplete prefix + limit 25.
a5 web tag create posts the right body; block remove calls DELETE.

## Scope
`tickets/apps/server/src/discord-rest.ts` · `tickets/apps/server/src/jobs/auto-close.ts` · `tickets/apps/server/src/routes/{tags,blocks}.ts` ·
`tickets/apps/server/test/{auto-close,tags,blocks}.test.ts` · `tickets/packages/discord/src/handlers/tag.ts` · `tickets/packages/discord/src/i18n/tag.ts` ·
`tickets/packages/discord/test/tag.test.ts` · `tickets/apps/web/src/pages/{Tags,Blocks}.tsx` · `tickets/apps/web/src/api/tags.ts` ·
`tickets/apps/web/src/i18n/tags.ts` · `tickets/apps/web/test/tags.test.tsx`
