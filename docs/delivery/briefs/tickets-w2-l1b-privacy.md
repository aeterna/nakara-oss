# Tickets W2 · L1b · personal data: delete my data, export, retention

**Route:** agy:B · also read `tickets-w2-common.md` · ADR 0003 decision 12 · Discord Developer Terms §5

## Goal
1. `apps/server/src/privacy.ts`: `deleteUserData(db, storage?, guildId | null, userId)` → counts: deletes that user's
   `messages`, their `attachments` rows (and stored objects when a storage is given — accept an optional
   `{ delete(key) }`), `ratings`; replaces `opener_id`/`claimer_id` on their tickets with `'deleted'`; writes a
   `data_requests` row (`kind='delete'`, `status='done'`) and an `audit_log` row without the user id in the message.
   `exportGuild(db, dataKey, guildId)` → JSON (guild, settings, categories, panels, tags, blocks, tickets with
   decrypted messages, ratings; no secrets: no `game_servers.secret_enc`, no sessions). `purgeExpired(db, now)` →
   deletes messages and attachments of tickets closed more than `retention_days` ago (per guild) and returns counts.
2. `apps/server/src/routes/data.ts` (replace stubs): deleteMeData (`requireUser`, current user, all guilds; CSRF;
   returns counts), getExport (`requireStaff`; `Content-Disposition: attachment; filename="nakara-tickets-<guild>.json"`).
3. `apps/server/src/jobs/retention.ts`: `run` calls `purgeExpired` and logs counts (no ids).
4. Put the pure database deletion/export/purge in `packages/db/src/queries/privacy.ts` and export it from
   `packages/db/src/index.ts` (you own that one export line; no other lane edits it). `apps/server/src/privacy.ts`
   wraps it (storage object deletion). `packages/discord/src/handlers/data.ts` `handleDeleteMyData`: ephemeral confirm
   button `nt:delme:confirm`; add that one routing branch in `gateway.ts` (you are the only W2 lane editing it), then
   delete in that guild only via the db query.
5. Web `pages/Privacy.tsx`: "delete my data" with a confirm step, shows counts; staff-only "export guild" button.
   `api/privacy.ts`, `i18n/privacy.ts`.

## Acceptance tests — write first
p1 delete removes only that user's rows, in all guilds (web) or one guild (Discord), keeps other users; tickets keep
existing with `'deleted'`. p2 export has no `secret_enc`, no session/csrf, messages decrypted. p3 purgeExpired removes a
ticket closed 91 days ago with retention 90 and keeps one closed 89 days ago and an open one. p4 route deleteMeData
without CSRF → 403. p5 web confirm flow calls the API once.

## Scope
`tickets/packages/db/src/queries/privacy.ts` · `tickets/packages/db/src/index.ts` (one export line) · `tickets/packages/db/test/privacy.test.ts` · `tickets/packages/discord/src/gateway.ts` (one routing branch) · `tickets/apps/server/src/privacy.ts` ·
`tickets/apps/server/src/routes/data.ts` · `tickets/apps/server/src/jobs/retention.ts` · `tickets/apps/server/test/{privacy,data}.test.ts` ·
`tickets/packages/discord/src/handlers/data.ts` · `tickets/packages/discord/src/i18n/data.ts` · `tickets/packages/discord/test/data.test.ts` ·
`tickets/apps/web/src/pages/Privacy.tsx` · `tickets/apps/web/src/api/privacy.ts` · `tickets/apps/web/src/i18n/privacy.ts` · `tickets/apps/web/test/privacy.test.tsx`
