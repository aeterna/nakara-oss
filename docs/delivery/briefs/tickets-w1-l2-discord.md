# Tickets W1 · L2 · Discord gateway: lock, panels, open / claim / close

**Route:** agy:B · **Gate:** G1 ✅ Pik 2026-11-14 · also read `tickets-w1-common.md` · ADR 0003 decisions 3 and 5

## Goal
`@nakara-tickets/discord` connects one gateway per Discord application and runs the ticket flow in Discord.

1. `packages/discord/src/lock.ts`: `acquireGatewayLock(pool: pg.Pool, appId: string, opts?: { intervalMs = 5000, signal?: AbortSignal })`
   takes a dedicated client and loops on `pg_try_advisory_lock(hashtextextended($1, 0))` with key
   `'nakara-tickets:' + appId` until held or aborted; returns `{ release(): Promise<void> }`. `onStandby?()` callback
   fires while waiting.
2. `packages/discord/src/gateway.ts`: `startGateway(deps: { token: string; appId: string; allowedGuildIds: string[];
   db: TicketsDb; pool: pg.Pool; dataKey: Buffer; log: { info, warn, error } })` →
   `Promise<{ status(): 'standby' | 'connecting' | 'connected'; stop(): Promise<void> }>`. Waits for the lock (status
   `standby`), then logs in with intents Guilds, GuildMessages, GuildMembers, MessageContent. On `guildCreate` for a
   guild not in `allowedGuildIds` it leaves that guild. Registers guild slash commands on ready.
3. `packages/discord/src/handlers/*.ts`: plain functions taking a small adapter interface (`DiscordPort`: create
   private thread, add member, send message, edit message, show modal, reply ephemeral) so tests use a fake port.
   - Panel button custom id `nt:open:<categoryId>`: if the category has a `form` (≤5 fields) show a modal
     `nt:form:<categoryId>`, else open directly. Open = `openTicket(...)` from `@nakara-tickets/db` (L1; signature in
     `tickets-w1-l1-core.md`), then a private thread named from `name_template` (`{number}` zero-padded to 4,
     `{user}`), add opener, post welcome message + buttons `nt:claim:<ticketId>` and `nt:close:<ticketId>`.
     `TicketError` codes `limit` / `blocked` → ephemeral reply (Thai and English text from `src/i18n.ts`, by
     guild locale).
   - Claim / close buttons and slash commands `/ticket claim`, `/ticket close [reason]`, `/ticket reopen`: staff only
     (`isStaff` from core with member permissions and the category's `staff_role_ids`); call `transitionTicket`;
     post a system line; on close, lock and archive the thread.
   - `/panel send category:<id> channel:<channel>`: staff only; posts an embed with one button per category given
     and stores it in `panels`.
   - `messageCreate` in a ticket thread (not from a bot) → `appendMessage` with `isStaff` computed.
4. Interactions must be acknowledged within 3 s: defer first when a database write happens before the reply.

## Acceptance tests — write first (fake `DiscordPort`, pglite db)
d1 lock: a second `acquireGatewayLock` on the same key keeps waiting until the first releases (pass a
fake pool whose client answers the advisory query; assert the SQL text and the retry); d2 open without form creates
thread with name `ticket-0001` and posts claim/close buttons; d3 open with form shows modal and nothing is written;
d4 limit → ephemeral reply, no thread; d5 non-staff claim refused, staff claim updates row; d6 close archives thread
and status is closed; d7 message in ticket thread stored encrypted, bot message ignored; d8 guild not allowed → leave.

## Scope
`tickets/packages/discord/src/**` · `tickets/packages/discord/test/**`

## Out of scope
HTTP routes, web, wiring into `main.ts` (W1-int calls `startGateway` with the signature above), attachments,
transcripts, ratings, auto-close (W2).
