# Tickets W2 · L2 · panel designer with live preview

**Route:** agy:B · also read `tickets-w2-common.md`

## Goal
Staff design a ticket panel in the browser, see it as Discord will show it, and send or update it in one click.
1. `apps/server/src/routes/panels.ts` (replace stubs, openapi `panels` operations): list, create, update, delete,
   send. Body: `channel_id` (snowflake), `embed` (title ≤ 256, description ≤ 4096, color int, footer ≤ 2048,
   image/thumbnail https URL or null), `kind` (`buttons` | `select`), `buttons`: 1–25 entries
   `{ category_id, label ≤ 80, emoji?, style: primary|secondary|success|danger }`, every `category_id` must belong to
   the guild (else 422). Validate total embed size ≤ 6000 chars.
   Send: build the Discord message (`embeds:[…]`, `components`: buttons in rows of 5 with `custom_id`
   `nt:open:<categoryId>`, or one string select `nt:open-select` whose values are category ids — add nothing to the
   gateway: use buttons for `select` too if the gateway has no select route, and note it), then
   `app.discord.editMessage` when `message_id` is set and still exists, else `sendMessage`; store `message_id`.
   Delete removes the Discord message (ignore 404) and the row.
2. `apps/server/src/panel-message.ts`: pure `buildPanelMessage(panel, categories)` used by the route and the web
   preview contract test.
3. Web `pages/Panels.tsx`: list + editor. Left: form (channel id, title, description with line breaks, color picker,
   footer, image URL, buttons with category select / label / emoji / style, reorder up/down). Right: live preview
   styled like Discord's dark theme (embed with colored left bar, title, description preserving newlines as text,
   footer, image, then button rows with Discord's button colors). Preview updates on every keystroke. Buttons:
   Save, Send/Update in Discord, Delete (confirm). Character counters at the Discord limits. `api/panels.ts`,
   `i18n/panels.ts`; styles in `pages/Panels.css` imported by the page.

## Acceptance tests — write first
n1 `buildPanelMessage`: 7 buttons → rows of 5 + 2, custom ids `nt:open:<id>`, embed fields mapped. n2 create with a
category of another guild → 422; title 257 chars → 400. n3 send without `message_id` calls `sendMessage` and stores the
id; with one calls `editMessage`; edit 404 falls back to send. n4 delete ignores Discord 404. n5 web: typing a title updates
the preview text; adding 6 buttons shows 2 rows; description `<b>x</b>` shows as literal text.

## Scope
`tickets/apps/server/src/routes/panels.ts` · `tickets/apps/server/src/panel-message.ts` · `tickets/apps/server/test/panels.test.ts` ·
`tickets/apps/web/src/pages/Panels.tsx` · `tickets/apps/web/src/pages/Panels.css` · `tickets/apps/web/src/api/panels.ts` · `tickets/apps/web/src/i18n/panels.ts` · `tickets/apps/web/test/panels.test.tsx`
