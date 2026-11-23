# Changelog

All notable changes to `aeterna_camera` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

## [0.1.0] - 2026-11-23

### Added

- Initial `aeterna_camera` package for the AETERNA Starter Kit 0.2 (ADR 0005, spec `docs/specs/aeterna_camera.md`).
- Camera and Gallery tiles on the phone through phonekit's App API; the viewfinder takes focus through `aeterna_core` (paused under an overlay) and reports `activity('media')` to phonekit; a phonekit power-off closes the viewfinder and the gallery.
- Base-game phone camera (back and selfie) with an overlay of key hints and a photo counter; shutter and switch from the phone controls and from `+aeterna_camera_shutter` / `+aeterna_camera_switch` (no default key).
- Photos: server shoot gate (viewfinder open, cooldown, per-character cap, total cap, `screenshot-basic` started), single-use 30 s tickets bound to source and character, client capture through `screenshot-basic` (detected at run time, never a dependency) and a latent upload; length cap before decoding, pure Lua base64 and JPEG start/end checks.
- Ticket and photo ids from two separately seeded streams that mix `math.random`, a counter, the game timer and `os.clock` into every draw.
- Deletes limited to one per `Config.cooldownMs` per player; the zero-byte file a delete leaves is reused by the next photo (free list `free:v1`, at most 5000 ids).
- `Config.perAccountMB` (default 200): one byte cap over all characters of a player (by license), so one player cannot fill `maxTotalMB` for everyone.
- Storage: `photos/<id>.jpg` written with `SaveResourceFile`, index in server resource KVP (`photo:v1`, `photos:v1`, `total:v1`, `acct:v1`, `free:v1`), totals repaired at start; delete overwrites the file with an empty one.
- HTTP handler for `GET p/<id>.jpg` only (404 for anything else, 429 over 60 requests in 10 s per address); every `writeHead` carries a header.
- Server exports `getPhoto`, `listPhotos`, `removePhoto`, `available`; server-local events `aeterna_camera:saved` and `aeterna_camera:removed`; command `aeterna_camera_remove` (ACE `aeterna.camera.admin`).
- `SaveResourceFile` success accepted as `true` or `1` (FXServer Enhanced b177 returns the number 1; measured on a live server).
- Self-tests registered with `aeterna_core`: `id_and_path_guard`, `http_router`, `store_roundtrip`, `caps`, `saved_hook`, `screenshot_detect`, `viewfinder`, `shoot_and_view` (destructive; asks core's write guard before it saves the photo).
- Asphalt theme (`html/theme.css`) with presets, inline Lucide icons (`html/icons.js`, `NOTICE`), the IBM Plex Sans Thai font (OFL-1.1), Thai and English locales, capability manifest (`oss.json`), `photos/README.txt` and busted specs.
