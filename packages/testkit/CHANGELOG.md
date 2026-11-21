# Changelog

All notable changes to `aeterna_testkit` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- Initial `aeterna_testkit` 0.1.0 package for the AETERNA Starter Kit (ADR 0005 decision 7): the menu and report layer on top of the `aeterna_core` 0.2 self-test runner.
- ACE-checked menu (`aeterna.testkit.run`) as an `aeterna_uikit` panel, opened by the key mapping `+aeterna_testkit_menu` (no default key) or the `aeterna_uikit` menu entry (`Config.menuEntry`), with kit versions, progress throttled to 4 updates a second, counts, suite rows, a suite detail panel and the busy line of another run.
- Eye-check card (own NUI, lower left, 360 px) on the `aeterna_core` focus overlay: Pass, Doesn't match, Skip; ESC = Skip; closes on `selftestEnd` and `focusLost` and releases its token once.
- Player B invite by server id (server-opened uikit panel) with consent, `Config.inviteSeconds` expiry, and the leave key mapping `+aeterna_testkit_leave` (no default key).
- Report `aeterna_testkit.report/1` (JSON, `schema/report-1.schema.json`) and Markdown, scrubbed of names (whole words, 3 characters or more), identifiers (closed prefix list plus `<letters>:` with 15 or more digits), IPs and paths (also after `(`, `=`, `@` and in stack frames), printed to the console (`Config.printReport`) and saved to `reports/latest.json` and `reports/latest.md`; server export `lastReport()`, client export `isOpen()`.
- Console command `aeterna_testkit_run [--json] [--only <name or prefix>]`, registered restricted and source 0 only.
- A run is cleared, player B released and roles reset when `aeterna_core` stops mid-run.
- Thai and English locales, capability manifest (`oss.json`), bundled IBM Plex Sans Thai (OFL-1.1, `NOTICE`), and busted specs (`spec/testkit_spec.lua`).
