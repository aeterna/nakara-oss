# Starter Kit 0.2 handoff

Status 2026-11-23: **released and closed.** All 12 packages and `aeterna-starter-kit@0.2.0` are published from
`main` `8daafec5`, each with checksums and a provenance attestation. There is no open work on this release. Written by Claude Code - Claude Opus 5.5 (Orchestrator). Plan and live status table:
the owner's plan artifact (Kit 0.2 plan, v16+). ADR: [0005](../adr/0005-starter-kit-0-2.md); ADR 0004 decision 10 amended 2026-11-22.

## Where it stands

| Wave | What | State | Evidence |
|---|---|---|---|
| W0 | ADR 0005, specs, spikes on kit-test | done | #92, #95 merged |
| W1 | uikit, notify, layout, hudkit, phonekit, invkit 0.2; testkit, radial, loading 0.1.0 | done | #97 (went in with #99) |
| W2 | self-tests in every package, phonecall + camera 0.1.0, site + README | done | #99 merged (`febad729`) |
| W3 | one combined live test on kit-test + fixes | done: menu run FAIL 0 (`r1-kku4`); 3-preset visual pass (owner); player-B rows not run (owner's call) | reports below |
| W4 | release | **released** 2026-11-23: promotion #112 (`8daafec5`), 12 `release.yml` runs + `starter-kit`, all `success` | tags `aeterna_*@0.2.0` / `@0.1.0`, `aeterna-starter-kit@0.2.0` |

### W3 runs on kit-test (FXServer Enhanced b177, game build 3788, private, destructive gate on)

| Run | Build | Result | Notes |
|---|---|---|---|
| headless (console) | `38f868d9` | 103/106 | camera writes refused: `SaveResourceFile` returns `1` |
| headless | `3fae610a` | 106/106 | after the camera fix and the Q3 batch |
| menu `r2-mpkn` (owner) | `0dcc4704`+ | PASS 76 · FAIL 6 · SKIP 11 · GAP 4 · MOCK 9 | 3 eye timeouts, contacts_hooks error, 2 voice |
| menu `r2-dcgi` (owner) | `d86a051f` + testkit `07598a57` | PASS 76 · FAIL 2 · SKIP 14 · GAP 4 · MOCK 10 | only the two hudkit voice rows fail |
| menu `r2-1zd3` (owner, 2026-11-23) | `07598a57` + coverage config | PASS 83 · FAIL 4 · SKIP 5 · GAP 4 · MOCK 10 | voice rows ran before the tester acted; invkit test phone race |
| menu `r3-v5p2` | `0837ecef` (rows drive themselves) | PASS 83 · FAIL 4 · SKIP 3 · GAP 5 · MOCK 11 | test phone removal, vector3 stash point, tester dead (pma-voice blocks radio) |
| menu `r4-35d5` | `05f949f5` | PASS 84 · FAIL 1 · SKIP 3 · GAP 6 · MOCK 12 | voice_radio: tester still dead |
| menu `r5-ibfn` | `05f949f5` | PASS 86 · FAIL 0 · SKIP 3 · GAP 5 · MOCK 12 | GAP = 4 player B rows + `notify.motion_reduced` no answer |
| menu `r1-kku4` | `e206ad88` (after a restart) | **PASS 87 · FAIL 0 · SKIP 3 · GAP 4 · MOCK 12**, 120 s | GAP = the 4 player-B rows only; SKIP = items mode, sound off, no gamepad |

### Fixed in W3 (each with a spec that failed first, all on `feat/kit-02-w2`)

- `ec578b7d` camera: `SaveResourceFile` success is `1` on Enhanced.
- `dc38bea0` `aa02fc5c` `3fae610a`: Q3 security round by another model. Ignores for photos/reports, camera empty-file
  reuse + `Config.perAccountMB`, testkit scrub `cid:`/`lic:`. Not changed, with reasons in #99: phonekit hook events and
  `startRun` (server-only callers), phonecall unknown-number answer.
- `0dcc4704` key labels always English (the GTA key menu has no Thai glyphs).
- `cd827bc4` `76aba938` default keys for openers (F5 menu · M phone · F3 radial · F2 inventory panel · F9 test menu ·
  Y/U toast actions · PageUp/PageDown calls), owner switch `setr aeterna_keys` (owner decision 2026-11-22).
- `eee65d1f` BOOL natives return `1` on Enhanced: `AeternaCore.can` refused every admin; new `AeternaCore.yes`.
- `d86a051f` eye tests may skip or fail before `ready` (were timeouts); `AeternaCore.kvp.del` (phonekit deleted
  through a core module other resources do not load); hudkit `voice_radio` judged by its own rule.
- `07598a57` testkit reads the Enhanced build (`b177`) for the report.
- `21ac480c` invkit `phone_device_save` gives its phone with a battery (phonekit wrote its start battery after the save).
- `0837ecef` `bb721a5a` **no manual steps** (owner 2026-11-23): hudkit drives pma-voice (range cycle, radio channel 987,
  `+radiotalk`) and seats the tester in a test vehicle; invkit's server gives/takes/sets aside phones and moves the
  tester to the stash point; radial drives the ring; phonekit fold rows show the model they need. The tester only
  answers eye cards.
- `e206ad88` notify and uikit `motion_reduced` force the page's reduced-motion rules for the run (the card asked for a
  Windows setting nobody had turned on).
- `e4dd6bd4` uikit, hudkit and phonekit pages apply the theme preset; they got only the owner stylesheet, so paper and
  night-market never reached the menu, inventory panel, HUD or phone.
- `05f949f5` invkit removes test phones by slot (ox matches metadata whole); stash point read as vector3; hudkit
  `voice_radio` names a dead tester.

## For the next version

- Not verified on a live server: the four two-player rows (phonecall SMS and call between two players, a busy line,
  testkit's player-B card). Run them with a second account first.
- Release evidence: the combined zip and `aeterna_core-0.2.0.zip` pass `gh attestation verify` and `sha256sum -c`;
  the combined zip holds the 12 resources and `resources.cfg` under `[aeterna_kit]/`, and core's files in it match
  core's own zip.

Measured on kit-test: pma-voice works on Enhanced b177 (range, radio channel, radio transmit, the
`pma-voice:radioActive` event), but refuses radio while `LocalPlayer.state.isDead` (qbx_medical sets it; an idle
tester dies of hunger in about an hour, `/revive`). ox_inventory `RemoveItem` matches metadata as a whole.

## Rules for other sessions

- kit-test (pik-windows :30150) is back to a plain kit server: the W3 helpers (`kw3run`, `aeterna_w3probe`) are in
  `C:\aeterna-kit-test\parked\`, the coverage configs are restored, the W3-only cfg lines and the theme preset line
  are gone. It keeps the three kit ACE lines 0.2 needs and the 0.2 test builds in `[kit]`.
- Check players.json is empty before any restart.
- Measured FXServer facts live in [live-test.md](../maintainers/live-test.md) (BOOL natives return `1`, Enhanced
  version string, no Thai glyphs in the key menu).

## Way back

- kit-test: `C:\aeterna-kit-test\backup-kit-20261122-131146` holds the 0.1 `[kit]`; `parked\` holds the 0.1 demo harness
  and the W3 helpers.
- Withdraw a bad package by marking its GitHub release as withdrawn and publishing a fixed patch version. Tags stay.

## Log

- 2026-11-22 W3 started (owner "Start W3 now"); kit-test lent to the Rongroi and tickets sessions in gaps.
- Headless 106/106 after the camera fix; Q3 round fixed; owner asked for default keys (ADR 0004 d10 amended).
- Owner menu runs `r2-mpkn` (FAIL 6) and `r2-dcgi` (FAIL 2: hudkit voice only).
- 2026-11-23: W4 prepared (versions, combined zip job checked offline, docs); owner chose to release without the
  player-B run.
- 2026-11-23: coverage config on; voice probe; owner "too manual, make it auto" → every action row drives itself;
  runs `r2-1zd3` → `r5-ibfn` (FAIL 4 → 0); motion_reduced fixed → `r1-kku4` FAIL 0, GAP only player B. Owner passed asphalt (in game) and paper +
  night-market (local preview of the real NUI pages with the self-tests' messages) after the preset fix `e4dd6bd4`.
- 2026-11-23: owner merged by order: #92, #95, #99 (with #97) into `dev`, promotion #112 into `main`; 12 packages and
  `aeterna-starter-kit@0.2.0` released and checked; kit-test cleaned; lane worktrees and branches closed out.
