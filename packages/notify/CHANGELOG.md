# Changelog

All notable changes to `aeterna_notify` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

0.2.0, written by Claude Code - Claude Opus 5.5 (agent engineer), from `docs/specs/aeterna_notify.md` "0.2 additions" (ADR 0005).

### Added

- Toast fields `actions` (1–2 buttons), `sound`, `history` and `merge`. Actions are pressed with the key mappings `+aeterna_notify_action1` / `+aeterna_notify_action2` (no default key) or by mouse when the cursor is already free; the press fires `aeterna_notify:action` client-local (client export) or, through the rate-limited `aeterna_notify:sv:action`, server-local (server export). `Config.toast.actionDuration`.
- Lifetime bar on timed toasts (`Config.toast.lifetimeBar`), not drawn under reduced motion.
- Optional frontend sounds per toast type (`Config.sound`), the `aeterna_notify_sound` command and client KVP `aeterna_notify:settings:v1`.
- Countdown announcements: server exports `announceCountdown` / `cancelCountdown`, the `aeterna_announce_countdown` command, client event `aeterna_notify:cl:countdown`, server-local `aeterna_notify:countdownEnd`, `Config.countdown.marks`.
- Client exports `history` / `clearHistory`, client-local `aeterna_notify:added`, `Config.history.max`.
- The MOTD stays on screen and ignores input while `aeterna_core`'s focus overlay pauses it.
- Theme type tokens (`--fs-1` … `--fs-5`, `--lh`) in `style.css`, and the `aeterna_theme_preset` preset on the page.

### Changed

- Identical toasts now merge into one with `×n` by default (`Config.toast.merge = false` restores the 0.1 stack; `merge = false` exempts one toast).
- The client `notify` export returns the `toastId` instead of `true`; the server export's `clean` carries `toastId`.
- MOTD buttons and ESC wait for the client to close the card instead of hiding it in the page first.

### Fixed (Q3 review)

- A toast with `actions` and an `id` longer than 24 characters is refused (`id: maxLen 24 with actions`) instead of showing buttons that could never be pressed.
- The server keeps open action toasts per owner resource + `toastId` (8 per player per owner); resending the same `id` without actions drops that owner's record.
- Auto `toastId`s are `c` + base-36 for client-made toasts and `s` + base-36 for server-made ones, so a client toast and a server toast on screen at once never share an id; history uses the same id.
- `cancelCountdown` only works for the resource that started the countdown; a countdown ends with `cancelled = true` when its owner resource or notify stops.
- The README no longer names the phone package (ADR 0005 decision 2).

## [0.1.0] - 2026-11-18

- Bundle the IBM Plex Sans Thai font (OFL-1.1).
### Added

- Initial `aeterna_notify` package for the AETERNA Starter Kit (ADR 0004).
- Client `notify` and `clear` exports and server `notify(src, opts)` export with bounded queue (`Config.toast.max`), in-place replacement by `id`, text cleaning, duration clamping (`1000–15000` ms), and type fallback (`info`).
- Server `announce` export and ACE-checked `aeterna_announce` command (`aeterna.notify.announce`) with queued banner display (`Config.announce.queue`).
- Once-per-version MOTD card (`config/motd.json`) with schema validation, `playerSpawned` / `QBCore:Client:OnPlayerLoaded` / `showMotd()` triggers, `aeterna_core` focus coordination, and client KVP persistence (`aeterna_notify:motd_seen:v1`).
- Optional `aeterna_layout` coordinate integration via local client events (`aeterna_layout:add`, `aeterna_layout:hello`, `aeterna_layout:apply`) for `toasts` and `announce`.
- Asphalt default theme (`html/theme.css`), inline Lucide icon map (`html/icons.js`, `NOTICE`), Thai and English locales (`locales/th.lua`, `locales/en.lua`), capability manifest (`oss.json`), and busted unit/harness specs (`spec/notify_spec.lua`).

### Fixed

- Locale files merge into the tables created by `@aeterna_core/import.lua` instead of replacing them, and layout registrations now include their `owner`.
- Toast opts ignore extra `lib.notify` keys, drop an unknown `icon` without rejecting the toast, and use `description` as the title when `title` is missing.
- Layout placement accepts any positive scale up to `4`, the announcement stand-in keeps its registered `88` px height, and the MOTD does not open when `aeterna_core` refuses focus.
