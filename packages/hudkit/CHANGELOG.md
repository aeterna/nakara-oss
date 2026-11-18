# Changelog

All notable changes to `aeterna_hudkit` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

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
