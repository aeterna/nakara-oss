# ADR 0005 — Starter Kit 0.2: a realistic phone, five new packages, and a test kit anyone can run

- Status: proposed (the owner answered every open question on 2026-11-21; accepted when the owner merges it)
- Date: 2026-11-21
- Related: ADR 0004 (all decisions stay in force unless this ADR names one it changes); this repo's `AGENTS.md` hard rules
  3, 4, 5 and 7; `docs/handoffs/starter-kit.md`; plan "Starter Kit 0.2" (owner's review copy, findings in its §8)
- Written by: Claude Code - Claude Opus 5.5

## Context

The seven `aeterna_*` packages shipped as 0.1.0 on 2026-11-18. The owner wants three things next:

1. the basics polished so a server can install them and use them as they are, while staying easy to edit;
2. the phone the team runs privately, with its device models, folding screens, battery and lock screen, released as
   part of the kit;
3. a way for anyone who installs the kit to test their own server with one button.

A review of the first plan against this repo (`f44986a9`, two independent read-only reviewers, 2026-11-21) found
facts that shape the decisions below:

- A package that calls `exports.<x>` needs a hard edge to `<x>` (ADR 0004 decision 2). If every package registered its
  tests with a new test package, every package would depend on it.
- Decision 8 of ADR 0004 forbids database tables before 0.4. Rule 5 lets a package touch `oxmysql` only for its own
  storage, only when it is started, and only when its ADR names it. `pma-voice` and `screenshot-basic` are named
  nowhere.
- The safety scanner never allows reading a convar whose name contains `token`, `secret`, `password`, `apikey` or
  `webhook`. Any built-in upload to a webhook or a paid image host would need such a convar.
- The first name proposed for the loading screen equals a resource the team runs privately. Decision 1 forbids
  reusing it, so the package is `aeterna_loading`.
- The 0.1 phone frame is 320 × 640 and its spec says it shows no battery. The private phone's frames are larger, and
  its widest open screen is 780 px.
- The private phone stores its battery in the phone item's metadata. A player can edit client KVP, so client KVP is the
  wrong place for anything a player must not change.
- The scanner reads the `loadscreen` manifest key but checks undeclared NUI only for `ui_page`.
- `release.yml` releases one package per run, and each run waits for the owner's approval.
- The kit-test server is a container on the Windows host, outside the heavy WSL host the fleet tools reach. It has no
  stdin, so the console is reached through temporary rcon (`docs/maintainers/live-test.md`).

## Decision

1. **Versions.** The seven existing packages go to 0.2.0. Five new packages start at 0.1.0: `aeterna_testkit`,
   `aeterna_radial`, `aeterna_loading`, `aeterna_phonecall` and `aeterna_camera`. The maintainer checked each new name
   against the private resource list on 2026-11-21. 0.1 contracts stay valid: specs add to them and mark every change
   as "Changed in 0.2" with an upgrade note.

2. **Edges.** ADR 0004 decision 2's table becomes:

   | Package | May depend on |
   | --- | --- |
   | `aeterna_core` | — (`ox_lib` optional) |
   | `aeterna_uikit` | `aeterna_core` |
   | `aeterna_notify` | `aeterna_core`; `aeterna_layout` optional, local events only |
   | `aeterna_layout` | `aeterna_core`, `aeterna_uikit` |
   | `aeterna_hudkit` | `aeterna_core`, `aeterna_uikit`, `aeterna_layout` (+ `pma-voice`, decision 4) |
   | `aeterna_phonekit` | `aeterna_core`, `aeterna_uikit`, `aeterna_notify`; `aeterna_layout` optional, local events only |
   | `aeterna_invkit` | `aeterna_core`, `aeterna_uikit` (+ `ox_inventory`); `aeterna_phonekit` optional, local events only |
   | `aeterna_testkit` | `aeterna_core`, `aeterna_uikit` |
   | `aeterna_radial` | `aeterna_core`, `aeterna_uikit` |
   | `aeterna_loading` | `aeterna_core` optional, local events only (self-test registration, decision 7) |
   | `aeterna_phonecall` | `aeterna_core`, `aeterna_uikit`, `aeterna_phonekit` (+ `pma-voice`, decision 4) |
   | `aeterna_camera` | `aeterna_core`, `aeterna_uikit`, `aeterna_phonekit`, `aeterna_notify` (+ `screenshot-basic`, decision 4) |

   `.github/scripts/check-kit-graph.mjs` gets the same rows. No edge points from `aeterna_notify` to
   `aeterna_phonekit`: the phone pulls notification history through a notify export. Decision 6 of ADR 0004 still holds:
   no package loads files from another resource, so apps from other packages draw inside the phone through panel specs
   only.

3. **Storage.** Decision 8 of ADR 0004 stays: no database tables in 0.2. Player preferences stay client KVP.
   Anything a player must not change (battery level, phone numbers, messages, device state) is server-side resource
   KVP, keyed by the character id from `qbx_core` when it is started and by the license identifier otherwise. In the
   phone's item mode the battery lives in the item's metadata.

4. **Rule 5 gains three optional resources.** `pma-voice` (read voice state; place and end calls) may be touched by
   `aeterna_hudkit` and `aeterna_phonecall`. `screenshot-basic` (take a screenshot) may be touched by `aeterna_camera`.
   Same conditions as `oxmysql` today: only when `GetResourceState` says it is started, never listed in
   `dependencies`, and the feature that needs it reports itself unavailable (and its self-test reports SKIP) when it is
   absent. `AGENTS.md` rule 5 changes with this ADR.
   **Calls on FiveM Enhanced (owner, 2026-11-21, after the W0 spike).** Enhanced has no Mumble: `pma-voice`'s call
   export runs and sets its state (`callChannel` 20001 → 0 on the kit-test server), but per-player call targets carry
   no audio there. On Enhanced (`gamename` convar `gta5enhanced`) `aeterna_phonecall` therefore puts both players in a
   voice channel of its own with FXServer's server-side voice-channel natives (`CreateVoiceChannel`,
   `AddPlayerToVoiceChannel`, `RemovePlayerFromVoiceChannel`, `SetPlayerMutedInVoiceChannel`, `DeleteVoiceChannel`), and
   never calls `pma-voice`. On Legacy it uses `pma-voice` as above. Natives are part of FXServer, not a resource, so
   this adds no dependency. Nakara City's own voice resource uses the same natives for calls on Enhanced.

5. **The phone (phonekit 0.2).** The App API, KVP keys and events of 0.1 stay. The look changes:
   - eight models: keypad, burner, qwerty, slab (default), fold (vertical clamshell with a cover screen), pro, book
     (opens into a wide two-pane screen) and pad (no calls);
   - display names are neutral by default (Keypad, Burner, Qwerty, Slab, Fold, Pro, Book, Pad), with an optional preset
     of names from the game's own universe in config; no real product names;
   - the layout element `phone` is added again with the held model's size whenever it changes, and is kept on screen
     when it grows (an unfolding book);
   - a lock screen, a control centre, a status bar with battery, a home bar and a cover screen;
   - a battery the server counts while the screen is on (decision 3); `Config.battery = false` turns it off;
   - `Config.devices = 'single'` (everyone holds one configurable model) or `'items'` (the model comes from an
     inventory item; `aeterna_invkit` or any resource answers the existing open gate);
   - fold and open use key mappings with no default key; the held prop stays `prop_npc_phone_02` and becomes
     configurable.
   Device rules come from the private phone as behaviour statements in the spec. Its shell, colours, fonts and app
   list are not ported.

6. **Calls and photos are add-ons.** `aeterna_phonecall` (numbers, contacts, messages; calls through FXServer's voice
   channels on Enhanced, or through `pma-voice` on Legacy when it is started) and `aeterna_camera` (viewfinder and
   gallery; photos when `screenshot-basic` is started) are apps inside
   the phone. Photos are saved on the server's disk with `SaveResourceFile` under the resource's own folder and served by
   its own HTTP handler. The kit never uploads anywhere: a local event `aeterna_camera:saved` lets a server owner's own
   resource forward photos where they like. The kit never reads a webhook or API-key convar.

7. **Tests register with `aeterna_core`; `aeterna_testkit` is the menu and the report.** Core's self-test registry
   gains, per test: `kind` (headless, ped, eye, mock), `players` (1 or 2), `destructive`, `expect` (what a person should
   see), `timeout` and a skip condition. Results are PASS, FAIL, SKIP (counts as passing, with a reason), GAP (needs a
   person or a second player who is not there), MOCK (must restore the state it changed) and MISSING (a started kit
   resource registered nothing). Ped and eye tests run on the presser's client and report back; the server judges.
   - One run at a time, with a lock that says who holds it.
   - The console entry accepts only source 0. The menu needs the ACE `aeterna.testkit.run`. Every net event is rate
     limited.
   - Destructive tests run only when `aeterna_core_allow_destructive` is true and the server is not listed
     publicly. A destructive test that does not declare itself fails.
   - The report (JSON and Markdown) carries versions, builds and results, never player names, identifiers, IPs,
     convar values or file paths.
   - Where tests run: `headless` and `mock` tests take `side = 'server'` (default) or `'client'` (runs on the presser's
     client; GAP when nobody pressed). A test that gives a real player items or writes a real player's stored data is
     destructive.
   - Focus: the eye card takes focus in a new core overlay mode. The resource that held focus is paused, not
     cancelled, and gets its focus back when the card closes, so the screen being checked stays open.
   A resource with only an optional edge to core (`aeterna_loading`) registers through the server-local events
   `aeterna_core:selftest:add` and `aeterna_core:selftest:none`, carrying `owner`; core treats them like the exports.
   Its client side reports and answers eye cards through client-local events of the same family, and it registers
   again when core fires `aeterna_core:hello` (core started after it).
   This reverses the 0.1 handoff's "the test menu is not part of the kit". The maintainer's own run scripts for the
   kit-test server and their results still stay outside the repo.

8. **Two new standalone packages.** `aeterna_radial`: a radial menu that other resources add slots to by export, with
   focus through `aeterna_core` and no default key. `aeterna_loading`: a loading screen that shows real loading
   stages. It runs before any client script, so it carries its own copy of the theme and cannot read
   `aeterna_theme`. The scanner learns to treat the `loadscreen` manifest key as NUI.

9. **Theme.** Every `html/theme.css` copy (still identical, checked in CI) gains type tokens (`--fs-1` smallest … `--fs-5`
   largest, `--lh`) and three presets: `asphalt` (default), `paper` (light) and `night-market` (dark, orange accent), selected
   by `setr aeterna_theme_preset`. Each page sets `data-preset="<name>"` on `<html>`, and the presets are written as
   `:root[data-preset="paper"] { … }` rules. When the `aeterna_theme` override is set, pages set no `data-preset`, so the override wins and the preset is
   ignored.

10. **One combined zip (owner, 2026-11-21).** `release.yml` gains a job that builds
    `aeterna-starter-kit-<version>.zip` from the per-package zips already released for one commit, plus
    `kits/starter/resources.cfg`, with its own provenance attestation. Each package is still released by its own run,
    which the owner approves.

11. **Deferred to 0.3.** A round minimap needs a streamed mask texture, which the scanner refuses as an opaque file.
    The kit has no seatbelt system; hudkit only shows a state that other resources set.

## Consequences

- The kit grows from 7 to 12 packages. Each new package follows ADR 0004's per-package checklist.
- The scanner, `check-kit-graph.mjs`, `oss.schema.json` (if a new capability field is needed) and `release.yml` change
  first. They are maintainer paths (rule 7), so the owner reviews them.
- A server that upgrades from 0.1 sees a larger phone. The upgrade note in each changed spec and in the guide covers
  saved layout scales and the new convars.
- Photos, and calls on Legacy, depend on resources this repo does not publish. They degrade to "unavailable" with a
  reason, never to an error.
- The scanner changes in W0 cover: the `loadscreen` manifest key counted as NUI, and `SaveResourceFile` paths built
  from a literal prefix that matches a glob declared in `oss.json` (`photos/*`, needed by `aeterna_camera`).
- Measured in the W0 spike on the kit-test server (Enhanced, 2026-11-21):
  - the `pma-voice` call export runs but carries no audio (decision 4);
  - `screenshot-basic`'s server-requested capture builds a malformed URL on Enhanced, and an upload to a resource's
    own HTTP handler is dropped: FXServer b177 closes any HTTP request with a body over about 8 KB before the
    handler runs (it worked on b170). The client export `requestScreenshot` plus a latent server event works and uses
    no HTTP request, so `aeterna_camera` uses that with a server-issued single-use ticket (camera spec § Taking a
    photo);
  - `SaveResourceFile` and `LoadResourceFile` keep JPEG bytes intact;
  - a NUI page loads an image from the resource's HTTP handler over `http://` (not `https://`), once the scheme and
    trailing slash are removed from `GetCurrentServerEndpoint()`, which returned `https://127.0.0.1:30150/`;
  - CEF 103 reports `prefers-reduced-motion: no-preference` with the Windows animation setting untouched; whether it
    follows that setting when switched off is not measured.
- Calls on Legacy are not tested by the kit-test server, which runs Enhanced only. The `pma-voice` path stays
  unverified in game until a Legacy server is available.
- A combined zip means one more attested asset per release and one more workflow job to keep pinned and linted.
