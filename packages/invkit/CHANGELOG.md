# Changelog

All notable changes to `aeterna_invkit` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

## [0.1.0] - 2026-11-18

### Added

- Initial `aeterna_invkit` package for the AETERNA Starter Kit (ADR 0004).
- Personal stash support (`openStash`, `stashId`, `+aeterna_invkit_open`, `aeterna_stash`) with `character` and `account` scopes, OneSync server-side distance verification, and `aeterna_uikit` proximity key hints.
- Item-use registry (`registerUsable`, `unregisterUsable`, `allowUse`, `denyUse`) with `aeterna_uikit:progress` integration, animation and prop support, `ask = true` 1000 ms pre-use check (`aeterna_invkit:asking`), server-side duration and item removal verification (`aeterna_invkit:used`), and automatic cleanup on resource stop.
- Isolated `ox_inventory` and `qbx_core` adapter (`server/ox_adapter.lua`) guarded by `GetResourceState`, Thai and English locales (`locales/th.lua`, `locales/en.lua`), capability manifest (`oss.json`), and busted unit/harness specs (`spec/invkit_spec.lua`).

### Fixed

- Accept FiveM `vector3` values for stash point/player coordinates and item-use prop position/rotation.
- Recover from an `ox_inventory` restart or late start by clearing the registered stash and hook state, then resyncing the item-use hook.
- Expire a running item use after its duration plus five seconds and always clear a pending use on server cancel, regardless of the client `cancelable` flag.
- Treat only a truthy `forceOpenInventory` result as success, read the documented `usingItem` hook payload, and show refusal reasons through the base game feed.
