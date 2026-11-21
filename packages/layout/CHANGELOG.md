# Changelog

All notable changes to `aeterna_layout` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added (0.2.0)

- Clamp on size change: an element that grows (a re-add with a new `w`/`h`, a scale change, a screen size change reported by the page) is moved back on screen, also outside the editor. The clamped place is not saved, so a shrinking element returns to the saved place.
- Presets: `Config.presets` (`default`, `compact`, `centered`; up to 8), validated at start, applied from a Preset select in the editor (session only: Done saves, Cancel undoes).
- Grid: drawn while dragging; the toolbar's snap control is a select (Off and `Config.snapSteps`), kept in client KVP `aeterna_layout:prefs:v1`.
- Export / import as text (`aeterna-layout:1:` + JSON), parsed and validated in Lua; a refused text changes nothing and shows the first error path.
- NUI messages `editor:clamp`, `editor:presets`, `export:show`, `import:result`; callbacks `preset`, `snap`, `import`, `exportOpen`, `screen`.
- The editor stays open and ignores input while a core focus overlay pauses it.
- Theme type tokens (`--fs-1`…`--fs-4`, `--lh`) and the theme preset (`data-preset`) in the page.
- Locale keys for presets, the snap select, the menu panel and export / import.

### Changed (0.2.0)

- The `aeterna_uikit` menu entry opens a panel with Edit, Reset all (confirm, then saves at once) and Export / import (`Config.menuPanel`, default `true`). Upgrade note: `Config.menuPanel = false` keeps the 0.1 behaviour. `aeterna_layout:cl:open` takes an optional `{ mode = 'editor' | 'share' | 'reset' }`.

## [0.1.0] - 2026-11-18

- Bundle the IBM Plex Sans Thai font (OFL-1.1).
### Added

- Initial `aeterna_layout` package for the AETERNA Starter Kit (ADR 0004).
- Coordinate-based HUD layout protocol (`aeterna_layout:add`, `aeterna_layout:remove`, `aeterna_layout:hello`, `aeterna_layout:apply`) with screen-fraction anchors (`0`, `0.5`, `1`), screen-edge clamping, and grid snapping.
- Interactive NUI layout editor with live 100 ms drag updates, Shift snap bypass, keyboard nudging and scaling, per-element scale/hide/reset inspector, and Reset all confirmation.
- Client KVP persistence (`aeterna_layout:places:v1`) via `AeternaCore.kvp`, shared menu entry in `aeterna_uikit`, and focus lock integration with `aeterna_core`.
- Asphalt default theme (`html/theme.css`), inline Lucide icon map (`html/icons.js`, `NOTICE`), Thai and English locales (`locales/th.lua`, `locales/en.lua`), capability manifest (`oss.json`), and busted unit/harness specs (`spec/layout_spec.lua`).

### Fixed

- Layout locale files merge into the locale tables loaded by `@aeterna_core/import.lua` instead of replacing them.
- Reset all stays inside the editor session; only Done persists, and Cancel restores the places from when the editor opened.
- Done saves only elements moved from their default and removes saved places that match the default again.
- Enter confirms Done when no toolbar button has focus, and the toolbar shows the shortcut.
- The editor does not open when `aeterna_core` refuses focus.
- Re-adding an element during an open editor keeps its in-session place and Cancel snapshot.
