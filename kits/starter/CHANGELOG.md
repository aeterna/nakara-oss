# Changelog: AETERNA Starter Kit

The kit as a whole. Each package keeps its own changelog in `packages/<name>/CHANGELOG.md`.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.2.0] - 2026-11-23

Versions: `aeterna_core`, `aeterna_uikit`, `aeterna_layout`, `aeterna_notify`, `aeterna_invkit`, `aeterna_hudkit` and
`aeterna_phonekit` 0.2.0; new at 0.1.0: `aeterna_testkit`, `aeterna_radial`, `aeterna_loading`, `aeterna_phonecall`
and `aeterna_camera`.

### Added

- Five new packages, taking the kit from 7 to 12 resources:
  - `aeterna_testkit`: an in-game self-test menu (F9, ACE `aeterna.testkit.run`) that runs every package's
    self-tests, asks a person to check what only eyes can judge, and writes a JSON and Markdown report.
  - `aeterna_radial`: a radial menu other resources add slots to (F3 on keyboard).
  - `aeterna_loading`: a loading screen that shows the real loading stages.
  - `aeterna_phonecall`: phone numbers, text messages and voice calls, as apps inside `aeterna_phonekit`. Calls use
    `pma-voice` where it is started.
  - `aeterna_camera`: camera and gallery apps inside the phone. Taking photos needs `screenshot-basic`.
- Default keys for the kit's openers: F5 menu, M phone, F3 radial (keyboard), F2 inventory panel, F9 test menu, Y/U
  toast actions, PageUp/PageDown answer or hang up a call. Players' own bindings always win. Owners change or turn
  them off with `setr aeterna_keys` (see `resources.cfg`).
- Theme presets: `setr aeterna_theme_preset asphalt|paper|night-market`.
- Self-tests in every package, registered with `aeterna_core` and run from `aeterna_testkit`.
- A combined release, `aeterna-starter-kit-0.2.0.zip` (tag `aeterna-starter-kit@0.2.0`), holding all 12 resources and
  `resources.cfg`. Unzip into `resources/` (you get `resources/[aeterna_kit]/`), then copy `[aeterna_kit]/resources.cfg` into `server.cfg`. Packages can still be
  downloaded one by one.
- Optional dependencies, detected at run time and never listed in a manifest: `ox_inventory`, `pma-voice`,
  `screenshot-basic`.

### Changed

- `resources.cfg` lists all 12 resources and the ACE lines for announcements, self-tests, calls, camera and the test
  menu.
- Keys: the 0.1 advice to bind every key yourself is replaced by the defaults above.

### Tested

- FXServer Enhanced b177 with `qbx_core`, one player.

### Not verified on a live server

- `aeterna_phonecall`: an SMS between two players.
- `aeterna_phonecall`: a call between two players.
- `aeterna_phonecall`: a busy line.
- `aeterna_testkit`: the player B card.

These four rows need two players and were not run. Until someone runs them, expect them to be the first place a
problem shows up; the test menu reports them as GAP without a second player.
