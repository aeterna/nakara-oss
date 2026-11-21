# Changelog

All notable changes to `aeterna_loading` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- Initial `aeterna_loading` package for the AETERNA Starter Kit 0.2 (ADR 0005).
- `loadscreen` page (`html/index.html`) with `loadscreen_manual_shutdown` and `loadscreen_cursor`: Map, Scripts (with a whole percentage) and Character stages from FiveM's loadscreen messages and the resource's own `SendLoadingScreenMessage`; a stage never goes back and a percentage never decreases; "Still loading" after 20 s without a message.
- Server name, tagline, background image, rotating tips, preset and optional audio from `html/config.json`, validated field by field (`shared/logic/loading.lua`, page twin `html/logic.js`); the server logs one `warn` per bad field.
- Client script that sends the Character stage once the session starts and closes the page on `playerSpawned` or after `shutdown.fallbackSeconds`, only while the loading screen is still active. A hard cap from resource start closes the page when the session never starts, and a missing `LoadingLogic` or unreadable config still ends in a close after the default 30 s.
- Its own copy of `html/theme.css`, the IBM Plex Sans Thai font (OFL-1.1), an empty `html/custom.css` for owner overrides, page strings in `html/locale.json` (Thai and English), console strings in `locales/th.lua` and `locales/en.lua`, capability manifest (`oss.json`), busted specs (`spec/loading_spec.lua`) and a `node --test` twin (`spec/logic.test.js`).
