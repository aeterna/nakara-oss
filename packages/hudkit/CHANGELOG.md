# Changelog

All notable changes to `aeterna_hudkit` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- Version 0.2.0 (ADR 0005). Agent: Claude Code - Claude Opus 5.5 (agent engineer).
- Bar style setting (`bar` or `ring`, default `Config.barStyle`): status bars, extra bars and the fuel figure draw as circular gauges in ring style; the `status` element is re-registered with its new size.
- Compass tape layout element `compass` (top-centre): a tick every 15°, the eight direction labels and the heading in whole degrees; `Config.compass.enabled` and `Config.compass.span` (60–180).
- Voice indicator layout element `voice`, shown only while `pma-voice` is started (runtime `GetResourceState` check, never a dependency, no export calls): talking from `NetworkIsPlayerTalking`, proximity mode from the `proximity` state bag, radio from the `radioChannel` state bag and the `pma-voice:radioActive` local event; `Config.voice.enabled`.
- Seatbelt icon in the vehicle part, driven by the client-local event `aeterna_hudkit:seatbelt` (`{ on = boolean }` or `nil`); the owning resource stopping hides it; `Config.seatbelt.enabled`.
- NUI messages `hud:compass`, `hud:voice`, `hud:seatbelt`; `settings:open` / `settings:apply` carry `barStyle` and the compass span; `ready` reports `compass` and `voice` sizes.
- Locale keys for bar style, compass, voice and seatbelt (en, th).

### Changed

- The default screen gains the `compass` element. Upgrade note: `Config.compass.enabled = false` keeps the 0.1 screen.
- Settings KVP `aeterna_hudkit:settings:v1` gains `barStyle`; a 0.1 value without it reads as `Config.barStyle`.
- While another resource holds `aeterna_core`'s focus overlay, the settings card stays open and ignores input.
- Font sizes use the theme type tokens (`--fs-1` … `--fs-5`, `--lh`) instead of pixel values.
- `ready` accepts sizes only for hudkit's own parts.
- The compass tape has its own ~50 ms thread (camera heading only, sent on whole-degree change, idle while the element is hidden) instead of the 200 ms value tick.
- `pma-voice` is also checked every second, so a resource still reading `starting` at `onClientResourceStart` is picked up.
- The voice distance label uses the locale key `hudkit.unit.m` (en `m`, th `ม.`).
- `aeterna_hudkit:seatbelt` takes its owner from the invoking resource only; a `nil` payload is honoured only from the owner, and an event with no invoking resource is refused.

### Fixed

- Extra bar `label` length is counted in UTF-8 characters (`utf8.len`) instead of bytes, so Thai labels up to 24 characters are accepted; invalid UTF-8 is refused (0.1 bug).

## [0.1.0] - 2026-11-18

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
