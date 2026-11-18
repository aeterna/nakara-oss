# Changelog

All notable changes to `aeterna_core` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- Shared `@aeterna_core/import.lua` API (`log`, `on`/`off`/`emit`, Thai-aware `text`, `t`/`lang`, `time`, `validate`, `rateLimit`, `can`, `kvp`, and `key`).
- Client NUI focus coordinator (`requestFocus`, `releaseFocus`, `focusOwner`, and `aeterna_core:focusLost`) and `themeHref` export.
- Server self-test registry and runner (`addSelftest`, `reportSelftest`, `runSelftests`, and `aeterna_core_selftest`).
- English and Thai locale tables (`locales/en.lua`, `locales/th.lua`) and busted test suite (`spec/core_spec.lua`).
