# Changelog

All notable changes to `aeterna_radial` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- Initial `aeterna_radial` package for the AETERNA Starter Kit 0.2 (ADR 0005, spec `docs/specs/aeterna_radial.md`).
- A ring of 4–8 slots around the screen centre, one level of child rings for groups, sorted by `order`, owner and id; more than 8 visible slots show the first 8 and log one `warn` naming the owners cut.
- Client exports `addSlot`, `removeSlot`, `setFlag`, `isOpen`, `close`; client slots fire the client-local event `aeterna_radial:select` → `(owner, id)`.
- Server exports `addSlot`, `removeSlot`; server slots reach only the players who pass their `ace`, and every pick is re-checked on the server (`vehicle`, `jobs`/`grade`, `ace`) before the server-local event `aeterna_radial:select` → `(src, { owner, id })`.
- A server pick of a child also re-checks its group's conditions; an `ace` condition with no ACE check available fails closed.
- Conditions `vehicle`, `jobs` + `grade` (from `qbx_core` when started), `ace` (server slots) and owner-scoped `flags`; slots and flags of a resource are removed when it stops.
- Input: pointer, left stick, arrow keys / d-pad, accept, Backspace / B for back, Esc to close; `hold` and `toggle` modes; focus through `aeterna_core` with game input kept, paused while another resource holds overlay focus.
- Commands `aeterna_radial_open`, `+aeterna_radial_open`, `-aeterna_radial_open`, mapped for keyboard and gamepad with no default key; the label is English (`AeternaCore.keyLabel`) because the GTA key settings menu has no Thai glyphs.
- Asphalt theme (`html/theme.css`) with presets, inline Lucide icons (`html/icons.js`, `NOTICE`), the IBM Plex Sans Thai font (OFL-1.1), Thai and English locales, capability manifest (`oss.json`) and busted specs (`spec/radial_spec.lua`).
- Self-tests registered with `aeterna_core` on start: `registry`, `conditions` (server headless), `server_recheck` (ped; the server prepares a vehicle-only slot for the presser on `aeterna_core:selftestStarted` and removes it on `aeterna_core:selftestEnd`), `open_pick`, `child_ring` and `gamepad` (eye, with temporary slots under `aeterna_radial`; `gamepad` counts only a pad close and asks after 8 s with no pad input), with their expect strings and test labels in en and th. Agent: Claude Code - Claude Opus 5.5 (agent engineer).
- Focus event handlers accept only `aeterna_core` as the invoking resource; the self-test `aeterna_radial:select` listeners ignore other resources. Agent: Claude Code - Claude Opus 5.5 (agent engineer).
- Self-test event handlers accept only `aeterna_core` as the invoking resource. When `aeterna_core` stops mid-test, the server drops its temporary slot. Agent: Claude Code - Claude Opus 5.5 (agent engineer).

