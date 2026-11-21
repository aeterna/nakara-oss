# Changelog

All notable changes to `aeterna_phonekit` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

Version 0.2.0 (ADR 0005 decisions 1, 2, 3, 5). Written by Claude Code - Claude Opus 5.5 (agent engineer).

### Added

- Eight phone models (`keypad`, `burner`, `qwerty`, `slab`, `fold`, `pro`, `book`, `pad`) with their own frame size,
  case colours, home form (tile pages or a numbered list with keypad keys) and apps per model (`Config.models[m].apps`,
  burner `'*,-contacts'`). Neutral names or the optional universe preset (`Config.names`).
- Device modes: `single` (server resource KVP `aeterna_phonekit:device:v1:<who>`) and `items` (the open gate answered
  through the server-local events `hello`, `listen`, `answer`, `devicesChanged`, `deviceSave`; active device KVP
  `aeterna_phonekit:active:v1:<who>`). `allowOpen(checkId, answer?)` takes the optional device answer.
- Battery counted by the server: tick over loaded players, screen pulse, vehicle charging, chargers, warnings, save
  rule, `cl:power` and the server-local `aeterna_phonekit:power` event. Exports `battery`, `setBattery`, `charge`,
  `setCharger`, `activity`, `device`, `refreshDevices`; client exports `activity`, `isOpen`.
- Hooks for add-ons: `ring`, `stopRing`, `live`, `canCall`, contact intents (`addTile` `handles`, `needs = 'voice'`),
  client `getContacts`, `addContact` and the client-local `aeterna_phonekit:contactsChanged`.
- Shell: lock screen (`Config.lockScreen`), control centre, battery and live pill in the status bar, home bar, cover
  screen on a closed `fold` (`Config.cover`), fold continuity, two panes on an open `book` from uikit 0.2 `detailOf`,
  exit contract with the open key's code, keypad list rules, notification history from `aeterna_notify`'s `history`
  export (client KVP `aeterna_phonekit:seen:v1` for Clear).
- Command and key `aeterna_phonekit_fold` / `+aeterna_phonekit_fold` / `-aeterna_phonekit_fold` (no default key).
- Net events `sv:screen`, `sv:fold`, `sv:device`, `sv:ring`, `sv:battery`, `cl:device`, `cl:battery`, `cl:power`,
  `cl:ring`, `cl:ringStop`, `cl:live`.
- The phonekit copy of the uikit spec validator accepts uikit 0.2: `tabs`, `slider`, `table`, `empty`, list `search`
  and `empty`, `detailOf` / `detailItem`, and the new `update` keys.
- `Config.prop` (the held prop, per model with `Config.models[m].prop`).
- Self-tests (spec § Self-tests (0.2)), registered with `aeterna_core:addSelftest` on start: 25 of the 26 rows
  (`eye_battery_dead` is not registered: a client test has no way to make the server set 0 %). Server rows run on a
  fake device or on the presser's phone and restore what they change; ped and eye rows open the phone through the
  normal path, show another model or fold on the page only, and put it back on `aeterna_core:selftestEnd`. Pure
  rules in `shared/logic/selftest.lua`, busted cases in `spec/selftest_spec.lua`. The page answers self-test probes
  on the NUI callback `selftest`, and the client keeps the page-only test ring card away from the server.

### Changed

- The frame size comes from the held model (default `slab` 392 × 812) instead of 320 × 640. The layout element
  `phone` is re-added with the new size on every model switch, fold and unfold.
- The status bar shows the battery; `Config.battery = false` brings back the 0.1 status bar.
- `sv:tap` may carry an optional `intent = { kind, number }` (contact intents); a tap needs an open phone.
- Text sizes use the theme type tokens (`--fs-1` … `--fs-5`, `--lh`).

### Upgrade note

- A layout scale a player saved in 0.1 was chosen for a 320 × 640 frame. After the upgrade the same scale applies to
  the larger 0.2 frame (a `slab` is 1.27 × taller), capped by the viewport fit so it stays on screen. Players who want
  the 0.1 size set the phone's scale again in the layout editor (about 0.8 of the old value).
- Nothing else changes for a 0.1 server until it sets the new keys: the lock screen is off, the device mode is
  `single`, and the App API, KVP keys and 0.1 events keep their names and schemas.

### Fixed

- `postNui` reads the callback's JSON answer, so the notes and contacts lists refresh after a save.

## [0.1.0] - 2026-11-18

- Bundle the IBM Plex Sans Thai font (OFL-1.1).
### Added

- Initial `aeterna_phonekit` package for the AETERNA Starter Kit (ADR 0004).
- Phone shell frame (320 × 640 px at scale 1), Asphalt surfaces, status bar with clock, home grid of app tiles with badge counters, and bottom bar/back navigation.
- Four built-in client apps requiring no server code: Calculator (operator order as typed, percent, divide-by-zero error, 10 significant digits), Notes (up to 50 notes, 16 KB KVP limit), Contacts (up to 100 contacts, 16 KB KVP limit), and Settings (text size, 24-hour clock, and optional layout editor trigger).
- Server app API exports (`addTile`, `removeTile`, `showApp`, `updateApp`, `badge`, `notifyApp`, `listenOpen`, `allowOpen`, `denyOpen`) for external resources to draw uikit panel specs inside the phone frame without modifying phonekit files.
- Configurable opening check (`Config.ask = true`) with 1000 ms timeout, listener tracking, and `aeterna_phonekit:cl:refused` toast feedback.
- Phone prop and animation holding behavior while open (`Config.animation = true`), with safety cancellation on death, ragdoll, or water entry.
- Optional draggable/scalable coordinate integration with `aeterna_layout` via local client events (`aeterna_layout:add`, `aeterna_layout:hello`, `aeterna_layout:apply`).
- Asphalt default theme (`html/theme.css`), inline Lucide icon map (`html/icons.js`, `NOTICE`), Thai and English locales (`locales/th.lua`, `locales/en.lua`), capability manifest (`oss.json`), and busted unit/harness specs (`spec/phonekit_spec.lua`).

### Fixed

- Notify server when phone closes via `aeterna_phonekit:sv:close` to reset open state, clean up screen stacks, and trigger `__close` actions.
- Automatically save active note and contact edits when exiting via home button, backspace, right-click, escape, or phone close.
- Enforce resource ownership, ACE checks, and phone open state on `showApp` and `updateApp`; use unguessable screen IDs and support child screen history up to 8 levels via `__back`.
- Clean up tiles, screens, and badges when an owner resource stops, refreshing open phone interfaces.
- Reject reserved built-in app IDs in `addTile` (`calculator`, `notes`, `contacts`, `settings`).
- Prevent prop and animation leaks by checking a generation counter during async load waits and setting prop as non-networked.
- Refresh open phone instances cleanly upon re-triggering `cl:open` without re-requesting NUI focus.
- Calculate status bar time accurately using server time parts and local elapsed time.
- Omit empty number inputs from form values rather than defaulting them to 0.
- Lock weapon and look controls while phone is open, and disable all control actions while typing in text boxes.
- Preserve user form input across partial spec updates.
- Retain local note and contact buffers when a save request fails.
- Validate string payload lengths on `sv:tap` and `sv:action`.
