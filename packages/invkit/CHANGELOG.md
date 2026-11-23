# Changelog

All notable changes to `aeterna_invkit` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

- Self-test phones are removed through their slot, found by `phoneId` (ox_inventory matches metadata as a whole, and phonekit may have written battery or fold since); `stash_open` reads a game vector3 point the way invkit does (found on a live run: "the test phone item was not removed", "not checked at a stash point"). Agent: Claude Code - Claude Opus 5.5.

- Self-tests run with no manual steps (owner 2026-11-23): the server gives the presser tagged test phones for `phone_two_items` and `phone_drop_active` (taking one back after 4 s) and puts the presser's own phone items aside for `phone_no_item`, giving everything back on `selftestEnd`; the three rows are now destructive. `stash_open` moves the presser to the first stash point and away, then back. Agent: Claude Code - Claude Opus 5.5.

- `phone_device_save` gives its test phone with a battery set (100), so aeterna_phonekit does not write its start battery after the test's own save (found on a live run, Enhanced b177). Agent: Claude Code - Claude Opus 5.5.

### Added

- 0.2.0: phone item mode for `aeterna_phonekit` `Config.devices = 'items'` (ADR 0005). `Config.phone.enabled` (default `false`) and `Config.phone.items` (ox item name → phonekit model, at most 32, bad entries skipped with one `warn`).
- Answers `aeterna_phonekit:asking` (`devices = 'items'`) with every phone item carried, lowest slots first, at most 8; fires `aeterna_phonekit:listen` on start and on `aeterna_phonekit:hello`. Server-local events only; phonekit stays optional.
- A phone item with no `metadata.phoneId` gets an 8-character hex serial written on first listing; `battery`, `fold` and `color` metadata are passed through when valid.
- `aeterna_phonekit:deviceSave` writes `battery` (clamped 0–100) and `fold` into the item metadata, keeping other fields, at most once per player per 5000 ms (later saves held, latest per phone written); a phone no longer carried fires `aeterna_phonekit:devicesChanged`.
- Held saves are written at once when the player drops or `aeterna_invkit` stops; a `deviceSave` arriving within 2 s after the player dropped is written at once if the item is still there, otherwise dropped with a `debug` log. No `devicesChanged` fires for a dropped player.
- `swapItems` and `createItem` hooks on the mapped items fire `aeterna_phonekit:devicesChanged` for each player involved (integer player inventory ids of connected players only, never a stash), on the next tick after ox_inventory applies the change.
- README section on adding phone items and images to ox_inventory.
- Self-tests registered with `aeterna_core` on start: `stash_id`, `use_state_machine`, `phone_item_map` (server headless), `stash_open`, `phone_two_items`, `phone_drop_active`, `phone_no_item` (ped), `item_use` (client mock, destructive; the server prepares it on `aeterna_core:selftestStarted` and cleans up on `aeterna_core:selftestEnd`) and `phone_device_save` (server mock, destructive), with their expect strings in en and th. Test writes go through `AeternaCore.selftest.mayWrite`; `phone_device_save` removes its phone by `phoneId` and skips with `needs a presser` on a run nobody pressed. `shared/logic/phone.lua` is now a shared script so the client can build the device list. Agent: Claude Code - Claude Opus 5.5 (agent engineer).
- `item_use` takes only the presser's item tagged with the run id (a use gate in the ox hook); other players' uses of the same item go to ox untouched. The delayed start asks the write guard again; preparation is undone when invkit itself stops; the phone rows report what the inventory shows. Agent: Claude Code - Claude Opus 5.5 (agent engineer).
- Self-test event handlers accept only `aeterna_core` as the invoking resource. When `aeterna_core` stops mid-test, the server removes its tagged test item and the test usable. Agent: Claude Code - Claude Opus 5.5 (agent engineer).
- Self-test instructions as `expect` for `stash_open`, `phone_two_items`, `phone_drop_active` and `phone_no_item` (en, th). Agent: Claude Code - Claude Opus 5.5 (agent engineer).

Agent: Claude Code - Claude Opus 5.5 (agent engineer)

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
