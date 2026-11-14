# Tickets W2 · L1a · transcripts, attachment archive, tickets API + page

**Route:** agy:B · also read `tickets-w2-common.md` · ADR 0003 decisions 4, 6

## Goal
Staff can browse tickets and read a full transcript after Discord's attachment links expire.
1. `apps/server/src/storage.ts`: `createStorage(config)` → `Storage { put(key, bytes, contentType), get(key) →
   {bytes, contentType} | null, delete(key), usedBytes?(prefix) }`. Local driver under `STORAGE_DIR` (paths only from
   `<guildId>/<ticketId>/<uuid>`; reject `..`); S3 driver when env `S3_ENDPOINT`, `S3_BUCKET`, `S3_REGION`,
   `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` (or `*_FILE`) are set, using `aws4fetch` (`AwsClient`). Bytes are sealed
   with `sealBytes` before `put` and opened after `get`. Read the S3 env directly in this file (config.ts is shared).
2. `packages/discord/src/handlers/archive.ts` `archiveOnClose(ctx)`: for each message of the ticket with attachments
   (fetch the thread's messages through `ctx.port`, add a `fetchMessages(channelId, before?)` there only if the port
   lacks it — port is in `adapter.ts`, which is yours for this addition), download only from hosts
   `cdn.discordapp.com` and `media.discordapp.net` (URL host check, https only), cap 25 MB per file and the guild's
   `attachment_quota_mb` total (sum of `attachments.size`), store via storage, insert `attachments` rows
   (`stored=true`, `storage_key`, `sha256`, `size`, `content_type`, `filename`), then set `tickets.archived_at`.
   Over a cap → row with `stored=false`. Never throw out of the hook (log).
   Storage is passed in `CloseHookContext`? It is not — create it inside the hook from env via a small
   `packages/discord/src/storage-client.ts` that re-implements only `put` (local + S3, same layout/sealing), so the
   discord package does not import the server.
3. `apps/server/src/routes/tickets.ts` (replace stubs): getTickets (filters status, category, opener, search by number;
   cursor pagination, newest first), getTicket, getTicketMessages (decrypted, oldest first, author, staff flag),
   getTicketTranscript (HTML file: inline CSS, **no script**, every text HTML-escaped, attachments as links to
   getAttachment; headers `Content-Disposition: attachment; filename="ticket-<number>.html"`,
   `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; img-src data:`, `nosniff`),
   postTicketTransition (calls `transitionTicket`; posts a system line via `app.discord` when available),
   getAttachment (stored only; `Content-Disposition: attachment`, `nosniff`, content type from the row but never
   `text/html` → `application/octet-stream`).
4. Web `pages/Tickets.tsx`: list with filters + paging; detail view with messages, status actions (claim/close/reopen),
   "download transcript" link, attachments list. Render `<TicketActions guildId ticketId locale />` imported from
   `../components/TicketActions.js` (L5 writes that file; you only import it). `api/tickets.ts`, `i18n/tickets.ts`.

## Acceptance tests — write first
t1 storage local put/get round trip, stored bytes ≠ plain, `../` key rejected; S3 driver signs a PUT (stub fetch,
assert `Authorization: AWS4-HMAC-SHA256`). t2 archive: allowed host stored; `evil.example` skipped; 26 MB → stored=false;
quota reached → stored=false; `archived_at` set. t3 transcript: a message `<script>alert(1)</script>` appears escaped,
response has no `<script`, headers present. t4 tickets list scoped by guild (other guild's ticket absent), cursor works.
t5 attachment row with content_type `text/html` served as `application/octet-stream`. t6 web: list renders rows from a
stubbed api, detail shows messages.

## Scope
`tickets/apps/server/src/storage.ts` · `tickets/apps/server/src/routes/tickets.ts` · `tickets/apps/server/test/{storage,tickets,transcript}.test.ts` ·
`tickets/packages/discord/src/handlers/archive.ts` · `tickets/packages/discord/src/storage-client.ts` ·
`tickets/packages/discord/src/adapter.ts` · `tickets/packages/discord/src/types.ts` · `tickets/packages/discord/src/i18n/archive.ts` · `tickets/packages/discord/test/archive.test.ts` ·
`tickets/apps/web/src/pages/Tickets.tsx` · `tickets/apps/web/src/api/tickets.ts` · `tickets/apps/web/src/i18n/tickets.ts` · `tickets/apps/web/test/tickets.test.tsx`
