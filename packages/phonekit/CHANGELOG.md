# Changelog

All notable changes to `aeterna_phonekit` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- Initial `aeterna_phonekit` package for the AETERNA Starter Kit (ADR 0004).
- Phone shell frame (320 × 640 px at scale 1), Asphalt surfaces, status bar with clock, home grid of app tiles with badge counters, and bottom bar/back navigation.
- Four built-in client apps requiring no server code: Calculator (operator order as typed, percent, divide-by-zero error, 10 significant digits), Notes (up to 50 notes, 16 KB KVP limit), Contacts (up to 100 contacts, 16 KB KVP limit), and Settings (text size, 24-hour clock, and optional layout editor trigger).
- Server app API exports (`addTile`, `removeTile`, `showApp`, `updateApp`, `badge`, `notifyApp`, `listenOpen`, `allowOpen`, `denyOpen`) for external resources to draw uikit panel specs inside the phone frame without modifying phonekit files.
- Configurable opening check (`Config.ask = true`) with 1000 ms timeout, listener tracking, and `aeterna_phonekit:cl:refused` toast feedback.
- Phone prop and animation holding behavior while open (`Config.animation = true`), with safety cancellation on death, ragdoll, or water entry.
- Optional draggable/scalable coordinate integration with `aeterna_layout` via local client events (`aeterna_layout:add`, `aeterna_layout:hello`, `aeterna_layout:apply`).
- Asphalt default theme (`html/theme.css`), inline Lucide icon map (`html/icons.js`, `NOTICE`), Thai and English locales (`locales/th.lua`, `locales/en.lua`), capability manifest (`oss.json`), and busted unit/harness specs (`spec/phonekit_spec.lua`).
