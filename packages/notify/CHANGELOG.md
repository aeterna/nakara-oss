# Changelog

All notable changes to `aeterna_notify` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

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
