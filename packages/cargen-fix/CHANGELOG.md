# Changelog

All notable changes to `nakara_cargen_fix` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-10

Initial public release.

### Added

- Client-side relief for `CNetworkCarGenWorldStateData Pool Full, Size == 100`: disables vehicle
  generators map-wide with `bNetworked = false`, re-asserted every 5 s, restored on resource stop.
- `config.lua` with `Config.Area` and `Config.ReassertMs` (validated; invalid values fall back to the
  defaults).
- Client exports `setRelief(on)` / `isRelief()` to pause relief on one client for A/B testing.
- `oss.json` capability manifest declaring no capabilities.
- README section "What we have verified", including an A/B test that could not reproduce the vanilla
  overflow (Enhanced, single player).
- busted specs for the decision logic, the real client scripts and the `bNetworked = false` pin.
