# Tickets W2 · rework 3 · last five failures (diagnosed by the reviewer, AGENTS §5.6)

Evidence after rework-2 (runs 04253b a6c241 272c10): vitest 216/221 in three runs (same 5 each time) · tsc -b 0 · web tsc 0.
Do not run shell commands; file tools only. Never print connection strings, passwords, tokens or keys.

## RS · product (owner: tickets/apps/server/src/routes/tickets.ts, tickets/packages/discord/src/handlers/archive.ts)
1. `routes/tickets.ts` builds the system line as `` `${transition}ed` `` → users see "closeed". Use an explicit past-tense
   map: claim→claimed, unclaim→unclaimed, transfer→transferred, close→closed, reopen→reopened (and i18n by guild locale
   if a dictionary exists there).
2. `handlers/archive.ts`: when the cap is exceeded, cancel the source in **both** branches — the `getReader()` branch
   already calls `reader.cancel()`; the async-iterator branch only `break`s. Call `res.body.cancel?.()` (and abort the
   fetch's `AbortController`) there too, so no bytes past the cap are pulled. `archive.test.ts:434` expects the stream to
   be cancelled.

## RW · web tests (owner: tickets/apps/web/test/{actions,analytics,tags}.test.tsx)
3. `tags.test.tsx` a5-2: the page asks `window.confirm` before deleting; jsdom's `confirm` returns a falsy value, so
   no DELETE is sent. Stub it: `vi.spyOn(window, 'confirm').mockReturnValue(true)` (restore after).
4. `actions.test.tsx` g4: `getByText(/duplicate item warning|repeat/i)` matches the heading, the paragraph and a button.
   Query the heading by role: `getByRole('heading', { name: /duplicate item warning/i })`, then the confirm button by
   role inside the dialog.
5. `analytics.test.tsx` s6: `getByText('ticket.close')` matches the filter `<option>` and the audit row. Query inside the
   audit table (`within(screen.getByRole('table', …))`) or use `getAllByText(...).length >= 1` for the row.

## Acceptance
vitest 0 failed three runs in a row · tsc -b 0 · web tsc 0.

## Round 2 (reviewer diagnosis after runs 1223f7 e671d4: 220/221, same archive check failed twice)
Instrumented run: the download takes the `getReader()` path and reads chunks 1 MiB … 26 MiB against a cap of
26,214,400 bytes (25 MiB); the cap is crossed only on the **last** chunk (26 × 1 MiB), when the source has already
queued `controller.close()`. `reader.cancel()` on a closing stream does not call the source's `cancel()`, so
`streamCancelled` stays false. **Product code is correct; the test is wrong.**
6. `packages/discord/test/archive.test.ts` (lying-size case): make the source keep producing past the cap
   (`chunkCount = 40`), so the cap is crossed while the stream is still open; keep every assertion.
