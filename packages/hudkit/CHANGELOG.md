# Changelog

All notable changes to `aeterna_hudkit` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

- Bundle the IBM Plex Sans Thai font (OFL-1.1).
### Added

- Initial `aeterna_hudkit` package for the AETERNA Starter Kit (ADR 0004).
- Status bars (health, armour, state bag needs) with `--accent` health styling and `--bad` threshold warning.
- Vehicle cluster displaying rounded speed in km/h or mph, gear badge (`R`, `N`, `1`–`8`), and fuel level bar.
- Street and zone location display with 8-direction compass heading (`N` through `NW`).
- Game radar minimap integration using native component positioning (`SetMinimapComponentPosition`), resolution watcher, and display modes (`always`, `vehicle`, `never`).
- Coordinate-based element registration with `aeterna_layout` for all HUD parts (`status`, `vehicle`, `street`, `minimap`).
- Client-local event API for external resources to push custom status bars (`aeterna_hudkit:bar`, `aeterna_hudkit:removeBar`).
- In-game settings card (`aeterna_hudkit_settings`, `+aeterna_hudkit_settings`) with focus lock via `aeterna_core` and client KVP persistence (`aeterna_hudkit:settings:v1`).
- Default Asphalt theme (`html/theme.css`), inline Lucide icon map (`html/icons.js`, `NOTICE`), Thai and English locales (`locales/th.lua`, `locales/en.lua`), capability manifest (`oss.json`), and unit/harness specs (`spec/hudkit_spec.lua`).

### Fixed

- Reset change-detection state (`lastValues`, `lastVehicleVisible`) and resend bars, settings (`settings:apply`), and part visibility on NUI ready.
- Compass heading angle calculation normalized from counter-clockwise `GetGameplayCamRot` z and formatted with `hudkit.dir.*` locale keys.
- Part placement in NUI using `transform-origin: 0 0` with exact coordinate and anchor scaling math.
- Minimap mask and blur component offsets scaled relative to minimap base when scaling.
- Status rows order enforced at every render (health, armour, needs, extra bars by order then id).
- Refuse extra bar ids `health`, `armour`, `hunger`, `thirst`, `stress`, and refuse ids already owned by another resource.
- Disappearing need values emit `null` in diff, remove DOM rows, and avoid stale cached state bag fallbacks.
- Skip bigmap re-render when minimap positions are unchanged, remove duplicate apply in watcher, and restore hidden base bars after re-render.
- Minimap radar visibility toggled only on mode or vehicle transition, and release scaleform movie handle.
- Measure parts with hidden class removed, and report updated element sizes to layout when status rows change.
- Propagate `Config.low` threshold to NUI for dynamic `--bad` status styling.
- Keep vehicle panel hidden on load until first runtime `hud:visible` is received even if `hud:place` arrives first.
