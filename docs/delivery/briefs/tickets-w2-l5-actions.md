# Tickets W2 · L5 · game actions: revive, give item, repeat-confirm, results in Discord, game servers page

**Route:** agy:B · also read `tickets-w2-common.md` · ADR 0003 decisions 8–10 · repo `AGENTS.md` hard rule 5 (last bullet)

## Goal
### Resource `packages/tickets`
1. `server/js/actions.js` built-ins:
   - `player.revive`: only when `GetResourceState('qbx_medical') === 'started'` (else `adapter_missing`) and
     `config.enabledActions` contains it; calls the server export `exports.qbx_medical.Revive(playerSrc)` (verified
     in use server-side in a real server: Nakara `aeterna_admin/server/tools.lua:45`, Lua `exports.qbx_medical:Revive(target)`),
     wrapped in try/catch → `error` on throw.
   - `player.give_item`: only with `ox_inventory` started and enabled; `params.item` must be in
     `config.giveItem.allow` (object item → max count), `params.count` integer 1..max (`over_cap` otherwise);
     `exports.ox_inventory:CanCarryItem` then `AddItem`; failure → `error`.
   - Both off by default in `config.json` (`giveItem.allow` empty).
2. `oss.json`, `README.md` (actions table, config, the exact framework calls), `CHANGELOG.md`; specs in
   `spec/actions.test.js` with stubbed `GetResourceState` and `exports`.
### API
3. `apps/server/src/routes/actions.ts` postTicketAction: a `player.give_item` with the same ticket, item and target
   player within 10 minutes and `confirmRepeat !== true` → 409 `repeat_confirm` (openapi). Known actions validated
   (`player.teleport {spot}`, `player.give_item {item, count}`, `player.revive {}`, `player.info {}`); others pass as
   custom (name pattern) with params ≤ 16 keys.
4. `apps/server/src/routes/bridge.ts` result route (you are the only lane editing it): after recording a result, post
   one line into the ticket channel via `app.discord` (`✅`/`❌`, action, code, requested_by), and audit-log it;
   discord failure never fails the result.
### Web
5. `components/TicketActions.tsx` `{ guildId, ticketId, locale }`: buttons for info / teleport (spot input) / revive /
   give item (item + count), shows recent actions and their status (poll every 3 s while any is queued/leased), handles
   409 `repeat_confirm` with a confirm dialog that resends with `confirmRepeat: true`.
6. `pages/GameServers.tsx`: list servers (name, edition, version, players, last seen, confirmed/revoked), "create pair
   code" (shows the code once with the console command `nakara_tickets pair <code>` and a 10-minute countdown), confirm,
   rename, revoke (confirm). `api/servers.ts`, `i18n/servers.ts`.

## Acceptance tests — write first
g1 resource: revive without qbx_medical → adapter_missing; disabled → not_allowed; give_item not in allow → not_allowed;
count above cap → over_cap; happy path calls AddItem once. g2 repeat-confirm: second give_item within 10 min → 409,
with confirmRepeat → 202; different item → 202. g3 result posts a channel line; discord throwing still returns 200.
g4 web: pair code shown with the console command; repeat-confirm dialog resends with the flag.

## Scope
`packages/tickets/**` · `tickets/apps/server/src/routes/{actions,bridge}.ts` · `tickets/apps/server/test/{actions,bridge-result}.test.ts` ·
`tickets/apps/web/src/components/TicketActions.tsx` · `tickets/apps/web/src/pages/GameServers.tsx` · `tickets/apps/web/src/api/servers.ts` ·
`tickets/apps/web/src/i18n/servers.ts` · `tickets/apps/web/test/{actions,servers}.test.tsx`
