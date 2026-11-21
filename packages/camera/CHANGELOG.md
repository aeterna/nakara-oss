# Changelog

All notable changes to `aeterna_camera` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- Initial `aeterna_camera` package for the AETERNA Starter Kit 0.2 (ADR 0005, spec `docs/specs/aeterna_camera.md`).
- Camera and Gallery tiles on the phone through phonekit's App API; the viewfinder takes focus through `aeterna_core` (paused under an overlay) and reports `activity('media')` to phonekit; a phonekit power-off closes the viewfinder and the gallery.
- Base-game phone camera (back and selfie) with an overlay of key hints and a photo counter; shutter and switch from the phone controls and from `+aeterna_camera_shutter` / `+aeterna_camera_switch` (no default key).
- Photos: server shoot gate (viewfinder open, cooldown, per-character cap, total cap, `screenshot-basic` started), single-use 30 s tickets bound to source and character, client capture through `screenshot-basic` (detected at run time, never a dependency) and a latent upload; length cap before decoding, pure Lua base64 and JPEG start/end checks.
- Storage: `photos/<id>.jpg` written with `SaveResourceFile`, index in server resource KVP (`photo:v1`, `photos:v1`, `total:v1`), total repaired at start; delete overwrites the file with an empty one.
- HTTP handler for `GET p/<id>.jpg` only (404 for anything else, 429 over 60 requests in 10 s per address); every `writeHead` carries a header.
- Server exports `getPhoto`, `listPhotos`, `removePhoto`, `available`; server-local events `aeterna_camera:saved` and `aeterna_camera:removed`; command `aeterna_camera_remove` (ACE `aeterna.camera.admin`).
- Self-tests registered with `aeterna_core`: `id_and_path_guard`, `http_router`, `store_roundtrip`, `caps`, `saved_hook`, `screenshot_detect`, `viewfinder`.
- Asphalt theme (`html/theme.css`) with presets, inline Lucide icons (`html/icons.js`, `NOTICE`), the IBM Plex Sans Thai font (OFL-1.1), Thai and English locales, capability manifest (`oss.json`), `photos/README.txt` and busted specs.
