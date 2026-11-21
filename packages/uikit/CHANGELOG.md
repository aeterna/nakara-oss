# Changelog

All notable changes to `aeterna_uikit` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- Self-tests (0.2) registered with `aeterna_core`: `spec_limits`, `values_recheck`, `forged_action` (server), `panel_every_block`, `motion_reduced`, `overlay_pauses` (eye) and `tabs_switch`, `slider_keyboard`, `focus_lost_closes` (ped). Client tests open a test panel on the presser's client only; its actions never reach the server. Written by Claude Code - Claude Opus 5.5 (agent engineer).
- `slider` block: spec validation (range, step grid, at most 1000 steps, value inside the range) and server-side re-check of its value in `values`.
- Locale keys `uikit.search.placeholder`, `uikit.search.none`, `uikit.table.empty` and `uikit.tabs.label` (Thai and English).
- `tabs` block (2–6 tabs, one per spec, switched in the page, active tab in `values`, `report = true` fires the tab id) and `tab` on any block.
- `table` block (≤ 6 columns, ≤ 50 rows, `selectable = true` makes row ids actions), stand-alone `empty` block with one optional action, and the `empty` option on `list` and `table`.
- `list.search`: a search box that filters by label and meta in the page; the item limit is 200 with it, 50 without.
- `detailOf` / `detailItem` top-level spec fields (shape check only; uikit's own window ignores them).
- NUI rendering of the new blocks; slider keyboard (arrows one step, Page Up / Page Down ten steps, Home / End).
- Enter and exit motion for panels and prompts (none under reduced motion; `replaced` swaps with no exit; the answer never waits for the animation).

### Changed

- `update` also patches `rows` (table), `value` of `tabs` and `slider` (a slider value out of range or off the step grid is refused) and `empty`.
- A focus overlay (`aeterna_core` 0.2 `focusPaused` / `focusResumed`) pauses an open panel or prompt instead of closing it; a real `focusLost` still closes with `__close`.
- Text sizes come from the theme type tokens `--fs-1` … `--fs-4` and `--lh` instead of pixel values.

## [0.1.0] - 2026-11-18

- Bundle the IBM Plex Sans Thai font (OFL-1.1).
### Added

- Initial `aeterna_uikit` package for the AETERNA Starter Kit (ADR 0004).
- Server-owned panel exports (`open`, `update`, `close`, `isOpen`) with spec validation, field/toggle/select value cleaning, and server-local `aeterna_uikit:action` events.
- Shared server menu registry (`addMenuEntry`, `removeMenuEntry`, `showMenu`) with per-entry ACE filtering, automatic cleanup on resource stop, and server-local `aeterna_uikit:menu` events.
- Client prompt exports (`confirm`, `input`, `progress`, `skillCheck`, `keyHints`, `clearKeyHints`) coordinated through `aeterna_core` focus locks.
- Asphalt default theme (`html/theme.css`), inline Lucide icon map (`html/icons.js`, `NOTICE`), Thai and English locales (`locales/th.lua`, `locales/en.lua`), capability manifest (`oss.json`), and busted unit/harness specs (`spec/uikit_spec.lua`).
