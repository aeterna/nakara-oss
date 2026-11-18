# Changelog

All notable changes to `aeterna_layout` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- Initial `aeterna_layout` package for the AETERNA Starter Kit (ADR 0004).
- Coordinate-based HUD layout protocol (`aeterna_layout:add`, `aeterna_layout:remove`, `aeterna_layout:hello`, `aeterna_layout:apply`) with screen-fraction anchors (`0`, `0.5`, `1`), screen-edge clamping, and grid snapping.
- Interactive NUI layout editor with live 100 ms drag updates, Shift snap bypass, keyboard nudging and scaling, per-element scale/hide/reset inspector, and Reset all confirmation.
- Client KVP persistence (`aeterna_layout:places:v1`) via `AeternaCore.kvp`, shared menu entry in `aeterna_uikit`, and focus lock integration with `aeterna_core`.
- Asphalt default theme (`html/theme.css`), inline Lucide icon map (`html/icons.js`, `NOTICE`), Thai and English locales (`locales/th.lua`, `locales/en.lua`), capability manifest (`oss.json`), and busted unit/harness specs (`spec/layout_spec.lua`).
