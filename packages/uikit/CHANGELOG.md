# Changelog

All notable changes to `aeterna_uikit` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

- Bundle the IBM Plex Sans Thai font (OFL-1.1).
### Added

- Initial `aeterna_uikit` package for the AETERNA Starter Kit (ADR 0004).
- Server-owned panel exports (`open`, `update`, `close`, `isOpen`) with spec validation, field/toggle/select value cleaning, and server-local `aeterna_uikit:action` events.
- Shared server menu registry (`addMenuEntry`, `removeMenuEntry`, `showMenu`) with per-entry ACE filtering, automatic cleanup on resource stop, and server-local `aeterna_uikit:menu` events.
- Client prompt exports (`confirm`, `input`, `progress`, `skillCheck`, `keyHints`, `clearKeyHints`) coordinated through `aeterna_core` focus locks.
- Asphalt default theme (`html/theme.css`), inline Lucide icon map (`html/icons.js`, `NOTICE`), Thai and English locales (`locales/th.lua`, `locales/en.lua`), capability manifest (`oss.json`), and busted unit/harness specs (`spec/uikit_spec.lua`).
