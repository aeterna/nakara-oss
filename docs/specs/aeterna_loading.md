# aeterna_loading

- Package: `packages/loading` · resource `aeterna_loading` · version 0.1.0 · wave W1 of Starter Kit 0.2 · status spec
- Depends on: nothing at run time; `aeterna_core` optional, local events only, for self-test registration
  ([ADR 0005](../adr/0005-starter-kit-0-2.md) decisions 2, 7 and 8). It carries its own copy of the theme and its own
  strings.

## Purpose and limits

A loading screen that tells the player what is actually happening while they join: the map loading, the scripts
starting (with a percentage), and the wait for their character. It shows the server's name, a background image and
rotating tips, all from a config file the server owner edits.

The page is the FiveM `loadscreen` of this resource. It runs **before any client script of any resource**, so it cannot
call `aeterna_core`, cannot read convars (`aeterna_locale`, `aeterna_theme`, `aeterna_theme_preset`) and cannot
load another resource's files. Everything it needs is inside this resource.

Not in 0.1: video backgrounds, remote images or music from other hosts, a player count or queue position, links that
open a browser, a mini-game.

## Install

```cfg
ensure aeterna_loading
```

Only one resource on a server should declare `loadscreen`; remove or stop any other loading screen resource. The
order among other `ensure` lines does not matter.

## Manifest

```lua
loadscreen 'html/index.html'
loadscreen_manual_shutdown 'yes'
loadscreen_cursor 'yes'
files { 'html/**' }
shared_script 'shared/logic/loading.lua'
client_script 'client/main.lua'
server_scripts { 'locales/en.lua', 'locales/th.lua', 'server/main.lua' }
```

How the shipped manifest differs from what this spec first said (all decided and built in 0.2):

- **Shared logic.** `shared/logic/loading.lua` is a `shared_script`, so the client script and the server script use the
  same config rules, stage reducer, tip and close timing (`LoadingLogic`). The page uses its JS twin, `html/logic.js`.
- **Server-only locale files.** `locales/en.lua` and `locales/th.lua` are loaded by the server script only; they hold
  the console `warn` line. The client script has no strings of its own, and the page reads `html/locale.json`.
- **Hard cap.** The client script closes the page `shutdown.fallbackSeconds` after its own start even when the game
  session never starts, so a manual-shutdown loading screen cannot stay up for ever (see Stages, step 4).
- **Empty `tips`.** `"tips": {}` is accepted and means no tips, the same as `[]`: the Lua JSON decoder cannot tell an
  empty object from an empty list, so both rule sets (`loading.lua` and `logic.js`) treat an empty object as an empty list.
  A non-empty object is refused. An empty list hides the tip line.

`loadscreen_manual_shutdown` keeps the page up after the game finishes loading, so it can show the character stage
(below). `loadscreen_cursor` lets the player press the audio button. The server script exists only to validate the
config at start and to register self-tests.

## Configuration

`html/config.json` (shipped with defaults, edited by the server owner):

```json
{ "version": 1,
  "serverName": "My Server",
  "tagline": "",
  "lang": "en",
  "preset": "asphalt",
  "background": "",
  "tips": ["Bind your keys in Settings → Key Bindings → FiveM"],
  "tipSeconds": 8,
  "audio": { "src": "", "autoplay": false, "volume": 0.3 },
  "shutdown": { "fallbackSeconds": 30 } }
```

| Key | Limit | Meaning |
| --- | --- | --- |
| `serverName` | ≤ 40 | Large title |
| `tagline` | ≤ 80, may be empty | Line under the title |
| `lang` | `th` · `en` | Language of the page's own strings (stage names, audio button); the page cannot read `aeterna_locale` |
| `preset` | `asphalt` · `paper` · `night-market` | Theme preset; the page sets it as `data-preset` on `<html>` |
| `background` | ≤ 120, relative path inside `html/`, ends in `.jpg`, `.png` or `.webp` | Empty = the preset's surface colour with a soft gradient |
| `tips` | ≤ 30 items, each ≤ 160 | Rotated in order; empty list hides the tip line |
| `tipSeconds` | 4–30 | |
| `audio.src` | ≤ 120, relative path inside `html/`, ends in `.ogg` or `.mp3`; empty = no audio | |
| `audio.autoplay` | boolean, default `false` | `false`: audio starts only when the player presses the audio button. `true` is the owner's explicit choice |
| `audio.volume` | 0–1 | |
| `shutdown.fallbackSeconds` | 10–120 | See § Stages, step 4 |

Rules:

- A path that starts with `/`, contains `..`, `:` or `//`, or does not match its extension list is refused: the page
  never requests anything outside its own resource, so this package declares no HTTP host.
- A config that fails validation is replaced field by field with the defaults above; the page never shows a blank
  screen. The server script reads the same file with `LoadResourceFile` at start and logs one `warn` per failing
  field, so the owner sees the mistake in the console.
- Strings are the owner's own text and are rendered with `textContent`, never as HTML.

## What a server owner can customise, and how

The page cannot be themed from outside, so everything is done inside this resource's folder:

| Want | Do |
| --- | --- |
| Name, tagline, tips, language, preset, audio | Edit `html/config.json` |
| Background image | Put the image under `html/custom/` and set `background` to `custom/<file>` |
| Colours, fonts, spacing beyond the presets | Edit `html/custom.css` (shipped empty, loaded after `theme.css`); override the same custom properties as `aeterna_theme` would, for example `:root, :root[data-preset] { --accent: #c2410c; }` (the second selector is needed so the override also beats a preset) |
| A font | Put an OFL `.woff2` under `html/custom/` with its licence and add an `@font-face` in `custom.css` |
| Wording of the stages | Edit `html/locale.json` (`th` and `en` blocks) |

`html/theme.css` is the identical copy every kit package carries (CI checks it); owners should not edit it, because
an upgrade replaces it. `html/custom/`, `html/custom.css` and `html/config.json` are the files an owner keeps across
upgrades; the README says so. The repository ships no image or audio file, so the package carries no media licence.

## Stages

The page listens to the loading messages FiveM posts to a loadscreen (`window` `message` events with an
`eventName`) and to messages from this resource's client script (`SendLoadingScreenMessage`).

| # | Stage shown | Starts on | Progress |
| --- | --- | --- | --- |
| 1 | Map | `startDataFileEntries` | `onDataFileEntry` count / the total from `startDataFileEntries` |
| 2 | Scripts | `startInitFunctionOrder` | `initFunctionInvoking` index / count, summed over init orders, as a whole percentage; `loadProgress.loadFraction` is used when it is higher |
| 3 | Character | `{ type: 'aeterna_loading:stage', stage: 'character' }` from the client script, sent once its client script starts and the game reports the session started | none (an indeterminate bar) |
| 4 | — (page closes) | Something calls `ShutdownLoadingScreenNui`: usually the framework's character screen; otherwise this resource's client script on `playerSpawned`, or `shutdown.fallbackSeconds` after the session started, or, when the session never starts, `shutdown.fallbackSeconds` after the client script started (the hard cap) | |

- A stage turns into a check mark when the next one starts; the current stage shows its percentage as text
  (`Scripts 64%`) and as a bar, so it reads without colour.
- A message the page does not know is ignored. A stage never goes backwards; a percentage never decreases.
- With no messages for 20 s the page keeps the last stage and adds the locale line "Still loading" (no spinner that
  pretends progress).
- The client script calls `ShutdownLoadingScreen()` and `ShutdownLoadingScreenNui()` only if the loading screen is
  still active (`GetIsLoadingScreenActive()`), so it never interferes with a framework that has already closed it. It
  first sends `aeterna_loading:closing`, waits 1 s for the audio fade, checks again, and then closes.
- The client script reads `html/config.json` itself for `shutdown.fallbackSeconds`. If the file is unreadable or
  `LoadingLogic` is missing, it uses 30 s; every failure still ends in a close.
- **Not verified yet:** the meaning of `idx` in `initFunctionInvoking` (0-based or 1-based). The reducer takes `idx` as
  the number of init functions done in the current order, clamped to 0..`count`, and the percentage is
  `(done so far across orders) / (total so far)`. If FiveM sends 1-based values the percentage runs one step ahead; it
  never decreases and never exceeds 100 either way.
- **Not verified yet:** whether `GetIsLoadingScreenActive()` stays true under `loadscreen_manual_shutdown` while the
  page is still up. If it returned false early, the client script would skip the close and the page would stay until
  something else shuts it down. The smoke step 5 (stop the framework's character resource) checks this.
- The exact message names and payloads come from FiveM's loadscreen messages; **on FXServer Enhanced they are not
  verified yet** (first W1 smoke step). A missing message leaves that stage without a percentage, never stuck.

## Audio

Off unless `audio.src` is set. With `autoplay = false` (the default) the page shows a play button and plays nothing
until it is pressed. The button toggles mute either way. Audio fades out over 1 s when the page closes.
`prefers-reduced-motion` stops the tip cross-fade and the bar animation; it does not affect audio.

## Exports

None. Other resources do not talk to the loading screen.

## Events

None over the network. The client script's only messages go to its own loadscreen page.

## NUI messages

Client script → loadscreen page (`SendLoadingScreenMessage`, JSON): `{ type: 'aeterna_loading:stage', stage:
'character' }`, `{ type: 'aeterna_loading:closing' }`. The page sends nothing back (a loadscreen page has no NUI
callbacks).

## Commands and keys

None. There are no command names to keep stable in this package.

## Storage

None. The page keeps the mute choice for this load only.

## Locale keys

In `html/locale.json` (the page cannot use Lua locale files): `loading.stage.map`, `loading.stage.scripts`,
`loading.stage.character`, `loading.still`, `loading.audio.play`, `loading.audio.mute`, `loading.tip`. The Lua
`locales/th.lua` and `locales/en.lua` hold only the server script's `warn` lines (`loading.config.bad`).

## `oss.json` capabilities

```json
{ "http": [], "commands": [], "registeredCommands": [],
  "convars": { "read": [], "write": [] },
  "netEvents": { "server": [], "client": [] },
  "nui": true, "db": { "tables": [], "ddl": false }, "files": { "write": [] } }
```

`nui: true` because the resource has a `loadscreen` page and calls `SendLoadingScreenMessage` and
`ShutdownLoadingScreenNui`. `LoadResourceFile` of its own `html/config.json` needs no capability.

### Scanner requirement (W0, plan row #4)

Today `fivem-devkit safety` reads the `loadscreen` manifest key only to check for a remote URL; its undeclared-NUI
check looks at `ui_page` alone (ADR 0005 context). Before this package lands, the scanner must:

1. count a local `loadscreen` page (and the natives `SendLoadingScreenMessage`, `ShutdownLoadingScreenNui`) as NUI
   use, so `nui: false` with a `loadscreen` is an error and `nui: true` is not reported as over-declared;
2. run the same NUI rules on the loadscreen page's files as on a `ui_page` (non-static `innerHTML`, remote
   `fetch`/`XMLHttpRequest`, remote `src` in `index.html`).

Each change comes with a scanner test (a fixture with a local `loadscreen` and `nui: false` fails; with `nui: true`
passes).

## Tests

busted (pure logic in `shared/logic/`, shared by the server script; the page has a JS twin of the same rules):

1. Config validation: every limit in the table fails its field only; a bad field falls back to its default; paths
   with `/x`, `..`, `http:`, `//` or a wrong extension are refused.
2. Stage reducer (a pure function over the message sequence): Map → Scripts → Character in order; out-of-order and
   unknown messages ignored; percentage never decreases; `loadFraction` used when higher.
3. Tip rotation: order, `tipSeconds` clamp, empty list hides the line.

JS twin tested with `node --test` in the package's `spec/` (no build step): the same cases 1–3 run against
`html/logic.js`, so the Lua and JS rules cannot drift.

Smoke (kit-test server):

1. Join with a fresh cache and a warm cache: Map and Scripts show real percentages, Character shows, the page closes
   when the framework's character screen opens (or on spawn without `qbx_core`). Records which message names arrived
   on Enhanced.
2. A config with a bad field: the page uses the default for that field; the console shows one `warn`.
3. `audio.src` set, `autoplay` false: nothing plays until the button is pressed; mute works.
4. Each preset and a `custom.css` override; screenshots at 1920×1080 and 1280×720 for the owner's visual gate.
5. Stop the framework's character resource: the fallback closes the page after `shutdown.fallbackSeconds`.

## Self-tests (0.2)

The loading screen is gone by the time anyone can press a test button, so the self-tests check what remains: the
config and the shutdown. The page itself is covered by smoke steps 1–5.

| name | kind | players | destructive | expect (eye) | skip-when |
| --- | --- | --- | --- | --- | --- |
| `aeterna_loading.config_valid` | headless | 1 | n | — | — |
| `aeterna_loading.local_paths_only` | headless | 1 | n | — | — |
| `aeterna_loading.shut_down` | ped | 1 | n | — | — |
| `aeterna_loading.page_looked_right` | eye | 1 | n | When you joined, the loading screen showed the server name, then Map, Scripts with a percentage, then Character, and closed by itself | — |

`shut_down` asks the presser's client whether `GetIsLoadingScreenActive()` is false.

Registration: `aeterna_loading` has an optional, local-events-only edge to `aeterna_core` (ADR 0005 decision 2), so
its server script registers these tests with the server-local event `aeterna_core:selftest:add` (carrying `owner`),
which core accepts like `addSelftest` ([aeterna_core](aeterna_core.md), 0.2 additions). When core is not started the
event goes nowhere and the loading screen still works.

- **Server side.** On start, `aeterna_core:selftest:add` → `(owner = 'aeterna_loading', name, opts)` for
  `config_valid` and `local_paths_only` (and for the client tests, which core runs on the presser's client). Results go
  back through the server-local `aeterna_core:selftest:report` → `(owner, runId, name, ok, detail)`.
- **Client side.** The client script answers `shut_down` and the `page_looked_right` card through the client-local
  events `aeterna_core:selftest:report` and `aeterna_core:selftest:answer`, carrying `owner = 'aeterna_loading'`;
  core accepts only events whose `owner` is the invoking resource.
- **Core restarts.** On `aeterna_core:hello` (server-local on the server, client-local on the client) the script
  registers again, so a core restart after `aeterna_loading` started does not leave it MISSING.
- `aeterna_loading` never calls an `aeterna_core` export, never lists it in `dependencies` and never loads its files
  (`check-kit-graph` checks this).

## Done when

All busted and `node --test` cases pass, the scanner change above is merged, `fivem-devkit safety` reports 0 errors
and 0 over-declared items, the smoke steps pass on the kit-test server, and the owner has passed the screenshots.
