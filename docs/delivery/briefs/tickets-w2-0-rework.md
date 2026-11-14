# Tickets W2-0 rework · after runs 47ab30 (0a) and 3b98ce (0b)

Evidence: `npx vitest run` 125 tests, 4 failed · `tsc -b` 0 · web `tsc --noEmit -p apps/web` 1 error. Causes diagnosed:
1. **0a `test/routes.test.ts` r3** expects `/healthz` 200 with no database; the new behavior (no db → `db:'down'`, 503) is
   what the brief asked. Update r3: without a db it answers 503 `{ ok:false, db:'down' }`; add a case with a pglite db → 200.
2. **0a `test/system.test.ts` w3-3** inserts a ticket without `channel_id` (NOT NULL, `23502`). Give the fixture a
   channel id (18-digit string).
3. **0a `test/worker.test.ts` w1-3** times out: the job awaits `setTimeout(2500)` under fake timers and the test
   advances only to 2000 ms before awaiting completion/`stop()`. Advance far enough (`await vi.advanceTimersByTimeAsync(…)`
   until the run finishes) before `stop()`, or make `stop()` race the running job with the fake clock advanced; keep the
   assertion that `maxConcurrent` stays 1.
4. **0b `apps/web/test/nav.test.tsx`**: (a) TS2741 — the `getMe` mock guild lacks `icon` (type `Me`); add `icon: null`.
   (b) The default locale is `th`, so nav labels are Thai and `/tickets/i` never matches. Click the language toggle
   first (or match the Thai labels from `i18n/*.ts`), then assert all nine labels and each page heading.
Do not change product code for these; only the four test files. Do not run shell commands; file tools only.
Never print connection strings, passwords, tokens or keys.

## Scope
`tickets/apps/server/test/{routes,system,worker}.test.ts` · `tickets/apps/web/test/nav.test.tsx`
