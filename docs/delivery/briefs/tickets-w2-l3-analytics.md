# Tickets W2 · L3 · analytics, staff leaderboard, ratings, audit log

**Route:** agy:B · also read `tickets-w2-common.md` · ADR 0003 decision 5 (rating = button, DM once on opt-in, ignore 50007)

## Goal
1. `apps/server/src/routes/stats.ts` (getStats): query `from`/`to` (ISO dates, max 366 days, default last 30) →
   `{ opened, closed, open_now, median_first_response_s, median_close_s, rating_avg, rating_count,
   daily: [{ date, opened, closed }], by_category: [{ category_id, name, opened }],
   staff: [{ user_id, claimed, closed, rating_avg }] }`. Medians in SQL (`percentile_cont(0.5)`); days in UTC;
   days with no tickets appear with zeros. Guild scoped.
2. `apps/server/src/routes/audit.ts` (getAudit): cursor pagination newest first, filter by `action`.
3. `packages/discord/src/handlers/rating.ts`:
   - `ratingOnClose(ctx)`: post one message in the ticket channel with 5 buttons `nt:rate:<ticketId>:<1..5>` (⭐ labels);
     if `guildSettings.rating_dm` is true, DM the opener once with the same buttons (store nothing extra; send only
     when no rating exists); DM error code 50007 → ignore silently, other errors → log.
   - `handleRatingButton`: only the opener may rate, once per ticket (else ephemeral i18n message); shows modal
     `nt:ratefb:<ticketId>:<score>` with one optional paragraph input (≤ 1000) for feedback.
   - `handleRatingModal`: insert `ratings` (score, feedback, staff_id = ticket claimer) if none exists; ephemeral thanks.
   `i18n/rating.ts`.
4. Web `pages/Analytics.tsx`: range picker (7/30/90 days), stat tiles, daily opened/closed chart drawn as inline SVG
   (two lines, axis labels, tooltips via `<title>`), by-category bars, staff table sortable by column, audit log table
   with paging. `api/analytics.ts`, `i18n/analytics.ts`.

## Acceptance tests — write first
s1 stats with fixture tickets: medians correct for odd/even counts, zero-filled days, other guild excluded. s2 range > 366
days → 400. s3 rating: opener rates once (second → refused), non-opener refused, feedback stored, staff_id = claimer.
s4 ratingOnClose with rating_dm: DM 50007 swallowed, channel message still posted; rating_dm false → no DM. s5 audit
pagination. s6 web: tiles show stub numbers; SVG has one point per day.

## Scope
`tickets/apps/server/src/routes/{stats,audit}.ts` · `tickets/apps/server/test/{stats,audit}.test.ts` ·
`tickets/packages/discord/src/handlers/rating.ts` · `tickets/packages/discord/src/i18n/rating.ts` · `tickets/packages/discord/test/rating.test.ts` ·
`tickets/apps/web/src/pages/Analytics.tsx` · `tickets/apps/web/src/api/analytics.ts` · `tickets/apps/web/src/i18n/analytics.ts` · `tickets/apps/web/test/analytics.test.tsx`
