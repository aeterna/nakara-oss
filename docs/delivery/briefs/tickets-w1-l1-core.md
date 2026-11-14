# Tickets W1 · L1 · ticket rules and guild-scoped queries

**Route:** agy:B · **Gate:** G1 ✅ Pik 2026-11-14 · also read `tickets-w1-common.md`

## Goal
Pure ticket rules in `@nakara-tickets/core`, and the database queries every other lane calls, in `@nakara-tickets/db`.

1. `packages/core/src/ticket-state.ts`
   - `type TicketStatus = 'open' | 'claimed' | 'closed'` (matches enum `ticket_status`);
     `type Transition = 'claim' | 'unclaim' | 'transfer' | 'close' | 'reopen'` (openapi postTicketTransition).
   - `nextState(cur: { status, claimerId: string | null }, t: Transition, actorId: string, targetId?: string)`
     → `{ ok: true, status, claimerId } | { ok: false, reason: 'invalid_transition' | 'not_claimer' | 'target_required' }`.
     Rules: claim open→claimed (claimer=actor); unclaim claimed→open only by the claimer; transfer claimed→claimed to
     targetId (required) only by the claimer; close from open|claimed → closed (claimer kept); reopen closed→open
     (claimer null). Anything else = invalid_transition.
2. `packages/core/src/permissions.ts`
   - `MANAGE_GUILD = 1n << 5n`; `isStaff({ permissions: bigint, roleIds: string[], staffRoleIds: string[] })` = has
     MANAGE_GUILD (or ADMINISTRATOR `1n << 3n`) or shares a role with staffRoleIds.
   - `canViewTicket({ userId, staff, openerId, memberIds })`.
   - Re-export both from `packages/core/src/index.ts` (add lines only).
3. `packages/db/src/queries/*.ts`, re-exported from `packages/db/src/index.ts` (add lines only):
   - `TicketsDb` is already exported from `packages/db/src/index.ts` (W1-0); use it, do not redefine.
   - `class TicketError extends Error { code: 'limit' | 'blocked' | 'not_found' | 'invalid_transition' | 'not_claimer' | 'target_required' }`
   - guilds: `ensureGuild(db, guildId, name)` upsert + default `guild_settings` row; `getSettings(db, guildId)`;
     `updateSettings(db, guildId, patch)`.
   - categories: `listCategories(db, guildId)`, `getCategory(db, guildId, id)`, `createCategory(db, guildId, input)`,
     `updateCategory(db, guildId, id, patch)`, `deleteCategory(db, guildId, id)` (throws `TicketError('not_found')`
     for another guild's id; refuses delete while tickets reference it → code `limit`).
   - tickets: `openTicket(db, { guildId, categoryId, openerId, channelId, answers })` in one transaction: refuses
     a blocked user (`blocked`), refuses when the opener already has `max_open_per_user` open/claimed tickets in that
     category (`limit`), `number` = per-guild max + 1, inserts the opener into `ticket_members` (role `opener`).
     `getTicket(db, guildId, id)`, `getTicketByChannel(db, guildId, channelId)`,
     `listTickets(db, guildId, { status?, limit = 50, before? })` newest first,
     `transitionTicket(db, guildId, id, t, actorId, targetId?, reason?)` using `nextState`; sets `closed_at`,
     `close_reason`, increments `reopened_count` on reopen; writes an `audit_log` row.
   - messages: `appendMessage(db, key: Buffer, { guildId, ticketId, id, authorId, authorName, isStaff, isSystem, content })`
     seals content with `sealBytes`; sets `first_response_at` the first time a staff message arrives and
     `last_activity_at` always. `readMessages(db, key, guildId, ticketId)` returns decrypted text, oldest first.

## Acceptance tests — write first
- core `test/ticket-state.test.ts`: every allowed transition, and a table of at least 8 refused ones with the reason.
- core `test/permissions.test.ts`: MANAGE_GUILD yes; ADMINISTRATOR yes; staff role yes; none → no.
- db `test/queries.test.ts` (pglite, migrations applied):
  q1 two guilds, same category name, `listCategories` returns only its own; q2 `getCategory` with the other guild's
  id → not_found; q3 `openTicket` numbers 1, 2 per guild independently; q4 limit; q5 blocked; q6 claim→close→reopen
  updates columns and writes 3 audit rows; q7 `appendMessage` stores bytes that do not contain the plain text and
  `readMessages` returns it; q8 first staff message sets `first_response_at` once.

## Scope
`tickets/packages/core/src/{ticket-state,permissions,index}.ts` · `tickets/packages/core/test/{ticket-state,permissions}.test.ts` ·
`tickets/packages/db/src/index.ts` · `tickets/packages/db/src/queries/*` · `tickets/packages/db/test/queries.test.ts`

## Out of scope
Discord, HTTP routes, schema or migration changes (report back if the schema is missing something).
