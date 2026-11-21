# Changelog

All notable changes to `aeterna_uikit` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- `slider` block: spec validation (range, step grid, at most 1000 steps, value inside the range) and server-side re-check of its value in `values`.
- Locale keys `uikit.search.placeholder`, `uikit.search.none`, `uikit.table.empty` and `uikit.tabs.label` (Thai and English).

## [0.1.0] - 2026-11-18

- Bundle the IBM Plex Sans Thai font (OFL-1.1).
### Added

- Initial `aeterna_uikit` package for the AETERNA Starter Kit (ADR 0004).
- Server-owned panel exports (`open`, `update`, `close`, `isOpen`) with spec validation, field/toggle/select value cleaning, and server-local `aeterna_uikit:action` events.
- Shared server menu registry (`addMenuEntry`, `removeMenuEntry`, `showMenu`) with per-entry ACE filtering, automatic cleanup on resource stop, and server-local `aeterna_uikit:menu` events.
- Client prompt exports (`confirm`, `input`, `progress`, `skillCheck`, `keyHints`, `clearKeyHints`) coordinated through `aeterna_core` focus locks.
- Asphalt default theme (`html/theme.css`), inline Lucide icon map (`html/icons.js`, `NOTICE`), Thai and English locales (`locales/th.lua`, `locales/en.lua`), capability manifest (`oss.json`), and busted unit/harness specs (`spec/uikit_spec.lua`).
