# Tickets W2 · rework 5 · Q3 second pass (all 19 first-pass items fixed or partial; one new major)

Do not run shell commands; file tools only. Never print connection strings, passwords, tokens or keys.
1. **Major N1** `apps/server/src/jobs/auto-close.ts:86-120`: `closeHooks` is fired without await and the job then
   archives/locks the thread itself, racing the rating post and the archive's message fetch. `await
   ctx.gateway.closeHooks(...)` (it already locks + archives last); only when `ctx.gateway?.closeHooks` is absent patch
   the channel directly. Test: with a closeHooks stub that resolves later, `patchChannel` is not called before it resolves.
2. N2 `packages/discord/src/gateway.ts` `closeHooks`: run only when the ticket status is `closed`;
   `handlers/archive.ts`: skip when `ticket.archived_at` is set (no duplicate attachment rows after reopen + close).
3. Item 4 `handlers/archive.ts`: remove the `createStorageClient` fallback; when `ctx.storage` is missing, log a warning
   and record rows with `stored=false`. Delete `storage-client.ts` content (write `export {};`, reviewer deletes) if unused.
   N3: when the DB insert fails after `storage.put`, delete the object.
4. N4 + item 18 `apps/server/src/routes/audit.ts`: invalid cursor or date → 400 `invalid` (not 500).
5. Item 17 `apps/server/src/routes/actions.ts`: `player.give_item` `count` integer 1..1000 (API-side sanity cap; the game
   config cap stays final).
6. N5 `apps/server/src/routes/panels.ts`: when `app.discord` is null, create/update/send answer 503 `discord_unavailable`
   instead of skipping the channel-in-guild check.
7. N8 `apps/server/src/routes/system.ts`: metrics bearer compared in constant time.
Add a test for each item next to the existing ones.

## Scope
`tickets/apps/server/src/jobs/auto-close.ts` · `tickets/apps/server/src/routes/{audit,actions,panels,system}.ts` ·
`tickets/apps/server/test/{auto-close,audit,actions,panels,system}.test.ts` · `tickets/packages/discord/src/gateway.ts` ·
`tickets/packages/discord/src/handlers/archive.ts` · `tickets/packages/discord/src/storage-client.ts` ·
`tickets/packages/discord/test/{archive,close-hooks}.test.ts`
