# Changelog

All notable changes to `aeterna_phonecall` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

## [0.1.0] - 2026-11-23

### Added

- Initial `aeterna_phonecall` 0.1.0 package for the AETERNA Starter Kit 0.2 (ADR 0005 decisions 2, 3, 4 and 6, spec `docs/specs/aeterna_phonecall.md`).
- Phone and Messages apps drawn through phonekit's App API (`addTile` with `needs = 'voice'` on Phone and `handles = { 'tel' }` / `{ 'sms' }` for contact intents); tiles registered again on `aeterna_phonekit:hello`.
- Phone numbers from `Config.number.format` (reserved and taken numbers skipped, 50 tries, digits-only comparison), assigned on first open or on load, kept in server-side resource KVP keyed by character (`cid:` with `qbx_core`, else `lic:`).
- Messages written into both lists (offline recipients included), capped at `Config.sms.keep`, cleaned to one line of `Config.sms.maxLen` visible characters; threads (50), last 50 messages per thread (the screen draws the newest 34, phonekit's 40-block limit), read state, unread badge; limits 1 / 2 s, 15 / 60 s and 6 / 60 s per pair.
- Calls: dialing, ringing (phonekit ring screen, `stopRing` at `Config.call.ringSeconds`, at most 60 s), active, ended with `hangup`, `declined`, `missed`, `busy`, `unavailable`, `dropped`, `limit` or `voice_off`; status-bar pill and battery activity while active; dead battery ends the call `dropped`. Voice connects before a call turns active; a refused dial shows its reason on the dialer; rings stop and voice channels are deleted when the resource stops.
- Voice backends chosen from `gamename`: FXServer voice channels on Enhanced (one mode-0 channel per call, every call wrapped in `pcall`), `pma-voice` call channels on Legacy, detected at run time and never a dependency.
- Server exports `getNumber`, `findByNumber`, `sendSms`, `endCall`, `callState`; server-local events `aeterna_phonecall:sms` and `aeterna_phonecall:call`.
- Key mappings `+aeterna_phonecall_answer` and `+aeterna_phonecall_hangup` with no default key; admin commands `aeterna_phonecall_number` and `aeterna_phonecall_setnumber` (ACE `aeterna.phonecall.admin`).
- Self-tests registered with `aeterna_core`: `number_format`, `number_unique`, `sms_store_cap`, `sms_rate_limit`, `voice_detect`, `voice_channel`, `my_number`, `sms_ab`, `call_ab`, `call_busy`. Two-player tests take A and B from core's `aeterna_core:selftestStarted` and end on `aeterna_core:selftestEnd`; `sms_ab` assigns numbers and writes only after `AeternaCore.selftest.mayWrite`; call tests use existing numbers and write nothing (no number, no call log); a missing number or character fails the test with a reason instead of a timeout. Core's self-test events (`aeterna_core:selftest`, `selftestStarted`, `selftestEnd`) are accepted only from `aeterna_core`, on both sides, and its stop clears the test state.
- The client sends the names map at most once per 5.2 s, coalescing changes into one trailing send.
- Thai and English locales, capability manifest (`oss.json`) and busted specs (`spec/phonecall_spec.lua`, `spec/server_spec.lua`).
