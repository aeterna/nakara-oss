# Changelog

All notable changes to `aeterna_invkit` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- Initial `aeterna_invkit` package for the AETERNA Starter Kit (ADR 0004).
- Personal stash support (`openStash`, `stashId`, `+aeterna_invkit_open`, `aeterna_stash`) with `character` and `account` scopes, OneSync server-side distance verification, and `aeterna_uikit` proximity key hints.
- Item-use registry (`registerUsable`, `unregisterUsable`, `allowUse`, `denyUse`) with `aeterna_uikit:progress` integration, animation and prop support, `ask = true` 1000 ms pre-use check (`aeterna_invkit:asking`), server-side duration and item removal verification (`aeterna_invkit:used`), and automatic cleanup on resource stop.
- Isolated `ox_inventory` and `qbx_core` adapter (`server/ox_adapter.lua`) guarded by `GetResourceState`, Thai and English locales (`locales/th.lua`, `locales/en.lua`), capability manifest (`oss.json`), and busted unit/harness specs (`spec/invkit_spec.lua`).
