# aeterna_hudkit

- Package: `packages/hudkit` · resource `aeterna_hudkit` · wave W3 · status released in 0.1.0 · spec 0.2.0
  ([0.2 additions](#02-additions) at the end, [ADR 0005](../adr/0005-starter-kit-0-2.md))
- Depends on: `aeterna_core` (focus, KVP, locale, keys), `aeterna_uikit` (menu entry), `aeterna_layout` (elements)
- The minimap part is proven by spike S3 (ADR 0004 decision 12, 2026-11-17)

## Purpose and limits

A plain player HUD that works on any server: status bars, a vehicle panel, the street name, and the game's own
minimap. Every part is a layout element, so each player can move, scale or hide it. Other resources can add their
own bars without editing hudkit.

Not in v0.1: a round minimap (needs a streamed mask texture), voice or radio indicators (they need a voice resource
that ADR 0004's table does not allow), seatbelt and engine damage, weapon and ammo display, cinematic mode.

## Install

```cfg
ensure aeterna_core
ensure aeterna_uikit
ensure aeterna_layout
ensure aeterna_hudkit
```

## Configuration

`config.lua` (shipped):

| Key | Default | Meaning |
| --- | --- | --- |
| `Config.tick` | `200` | ms between reads of player values. NUI gets a message only when a value changes |
| `Config.low` | `20` | A bar at or below this percent turns to the `--bad` colour |
| `Config.needs` | `{ 'hunger', 'thirst', 'stress' }` | State bag keys read as 0–100 bars (below) |
| `Config.speedUnit` | `'kmh'` | `kmh` or `mph`; the default for players who have not picked one |
| `Config.minimap.mode` | `'always'` | `always` · `vehicle` (shown only in a vehicle) · `never`; the default for players |
| `Config.hideBaseBars` | `true` | Hides the game's health and armour bars under the minimap, because hudkit draws its own |

No convars.

## Parts

Each part registers with `aeterna_layout` as an element (`aeterna_layout:add` on start and on
`aeterna_layout:hello`; it applies `aeterna_layout:apply` for its own ids).

| `id` | Shows | Default place | `hideable` |
| --- | --- | --- | --- |
| `status` | Health and armour, then one bar per need that has a value, then bars added by other resources | bottom-left, right of the minimap | `true` |
| `vehicle` | Speed (with unit), fuel, gear; only while the player drives | bottom-right | `true` |
| `street` | Street and zone name, compass heading (N, NE, …) | bottom-centre | `true` |
| `minimap` | The game's radar (below) | the game's own place | `false` (use `minimap.mode`) |

Values and where they come from:

| Value | Source |
| --- | --- |
| Health | `GetEntityHealth` of the player ped, mapped 100–200 → 0–100 % (the ped is dead at 100) |
| Armour | `GetPedArmour` |
| Needs | The player's state bag (`LocalPlayer.state[key]`, 0–100), read on change with `AddStateBagChangeHandler`. `qbx_core` 1.23 sets `hunger`, `thirst` and `stress` this way (checked in its `client/events.lua` on the kit-test server). Any framework that sets the same keys gets the same bars; a key with no value shows no bar |
| Speed | `GetEntitySpeed` of the vehicle × 3.6 (km/h) or × 2.236936 (mph) |
| Fuel | `GetVehicleFuelLevel` (the base-game value; servers with a fuel resource that keeps its own value can push a bar instead, below) |
| Gear | `GetVehicleCurrentGear`; `R` when moving backward, `N` at 0 |
| Street, zone | `GetStreetNameAtCoord`, `GetNameOfZone` → `GetLabelText` |
| Heading | `GetGameplayCamRot` z, eight directions |

Health uses `--accent` (ADR 0004 decision 6: the accent is for the primary action and the health bar). The other
bars use `--text-2` and turn `--bad` at `Config.low`. Each bar has an icon and, when the player turns on "Show
numbers", the percentage in tabular figures.

## Bars from other resources (client, local events)

Same rule as layout: local events, no exports or functions crossing resources, the owner filtered by
`GetCurrentResourceName()`.

| Event | Payload | Meaning |
| --- | --- | --- |
| `aeterna_hudkit:bar` | `{ id, label, icon, value, order = 100 }` | Add or update one bar in `status`. `id` ≤ 32 `^[%w_%-]+$`, `label` a locale key or text ≤ 24, `icon` from the uikit icon names, `value` 0–100 or `nil` to hide it for now |
| `aeterna_hudkit:removeBar` | `id` | Remove it |

At most 8 extra bars; the ninth is refused with a `warn`. Bars of a resource that stops are removed. How the owner
is learned follows the layout spec (`GetInvokingResource()` for a local event is checked first in W2).

## Minimap

The radar is drawn by the game, so hudkit moves it with natives. This is what spike S3 ran:

1. **Mapping.** With `SetScriptGfxAlign('L', 'B')` and `SetScriptGfxAlignParams(0, 0, 0, 0)`,
   `GetScriptGfxPosition(0, 0)` and `GetScriptGfxPosition(1, 1)` give two screen points. Aligned offset → screen
   fraction is linear between them, in both directions. No hard-coded aspect ratio or safe-zone maths.
2. **Three components move together.** `minimap`, `minimap_mask` and `minimap_blur` keep their sizes and move by the
   same delta from their default offsets, through `SetMinimapComponentPosition(name, 'L', 'B', x, y, w, h)`. The
   default offsets are constants in `shared/logic/minimap.lua` with a comment saying where each was measured.
3. **Re-render.** After moving, `SetBigmapActive(true, false)`, wait one frame, `SetBigmapActive(false, false)`;
   without it the radar layer does not move.
4. **Size for layout.** The stand-in size is the `minimap` component's rectangle in px at the current resolution.
5. **Watch.** Every 1000 ms, if `GetActiveScreenResolution()` or `GetSafeZoneSize()` changed: register again with
   the new size and apply the player's place again.
6. **Mode.** `always` keeps `DisplayRadar(true)`; `vehicle` shows it only while in a vehicle; `never` hides it.

`scale` from layout is applied to the three sizes for the minimap too, within 0.75–1.5 (outside that the mask no
longer lines up; S3 tested scale 1 only, so W3 measures the edges and narrows the range if needed).

Hiding the base health and armour bars uses the `minimap` scaleform's `SETUP_HEALTH_ARMOUR` method with type 3.
**Not verified yet**; the W3 smoke checks it, and if it fails `Config.hideBaseBars` is removed from the spec.

## Settings

Opened from the `aeterna_uikit` menu entry "HUD settings" or the command `aeterna_hudkit_settings` /
`+aeterna_hudkit_settings` (no default key). A small card in hudkit's own NUI, with focus from `aeterna_core`:

- Show numbers on bars (off)
- Speed unit (km/h · mph)
- Minimap (Always · In vehicle · Never)
- "Edit layout" button, which opens the `aeterna_layout` editor through its command
- Close (ESC)

Hiding a part is done in the layout editor (`hideable`), not here, so there is one place for it.

## Events (network)

| Event | Direction | Schema | Rate limit |
| --- | --- | --- | --- |
| `aeterna_hudkit:cl:settings` | server → client | none | — |

The server only answers the uikit menu entry (`aeterna_uikit:menu` with `owner == 'aeterna_hudkit'`). Nothing goes
from the client to the server.

## NUI messages

Lua → NUI: `aeterna:theme`, `locale`, `hud:values {status, vehicle, street}` (only changed fields),
`hud:bars {bars}`, `hud:place {id, x, y, ax, ay, scale, hidden}`, `hud:visible {id, visible}`, `settings:open {settings}`,
`settings:close`.
NUI → Lua callbacks: `ready {sizes: {id: {w, h}}}` (measured parts for layout), `settings {key, value}`, `layoutEditor {}`,
`close {}`. Each is validated (known keys, known values) before it is applied.

## Commands and keys

`aeterna_hudkit_settings` (chat or F8), `+aeterna_hudkit_settings` / `-aeterna_hudkit_settings` registered with literal names
and mapped through `AeternaCore.key` with no default key.

## Storage

KVP `aeterna_hudkit:settings:v1` = `{ numbers, speedUnit, minimapMode }`. Places live in `aeterna_layout`'s KVP, not
here.

## Locale keys

`hudkit.menu.entry`, `hudkit.key.settings`, `hudkit.bar.health`, `hudkit.bar.armour`, `hudkit.bar.hunger`,
`hudkit.bar.thirst`, `hudkit.bar.stress`, `hudkit.vehicle.fuel`, `hudkit.vehicle.gear`, `hudkit.unit.kmh`,
`hudkit.unit.mph`, `hudkit.part.status`, `hudkit.part.vehicle`, `hudkit.part.street`, `hudkit.part.minimap`,
`hudkit.settings.title`, `hudkit.settings.numbers`, `hudkit.settings.speedUnit`, `hudkit.settings.minimap`,
`hudkit.settings.minimap.always`, `hudkit.settings.minimap.vehicle`, `hudkit.settings.minimap.never`,
`hudkit.settings.layout`, `hudkit.settings.close`, `hudkit.dir.n` … `hudkit.dir.nw`.

## `oss.json` capabilities

```json
{ "http": [], "commands": [],
  "registeredCommands": ["aeterna_hudkit_settings", "+aeterna_hudkit_settings", "-aeterna_hudkit_settings"],
  "convars": { "read": [], "write": [] },
  "netEvents": { "server": [], "client": ["aeterna_hudkit:cl:settings"] },
  "nui": true, "db": { "tables": [], "ddl": false }, "files": { "write": [] } }
```

(Opening the layout editor uses `ExecuteCommand('aeterna_layout')` on the client; if the scanner counts it, the
command goes into `"commands"`. State bag handlers need no capability.)

## Tests

busted (pure logic in `shared/logic/`):

1. Health mapping: 100 → 0 %, 150 → 50 %, 200 → 100 %, values outside clamp.
2. Speed: m/s → km/h and mph, rounded to whole numbers; gear text for reverse, neutral and 1–8.
3. Heading: each of the eight sectors, including the wrap at 360°.
4. Minimap mapping: offset → screen → offset round trip within 0.0005 for both reference points used in S3
   (1920 × 1080, safe zone 0.97, and one ultrawide 3440 × 1440 case); moving by a delta keeps the three components'
   relative offsets.
5. Extra bars: add, update, `nil` hides, ninth refused, owner stop removes only its bars, sort by `order` then `id`.
6. Change detection: identical values send no NUI message.
7. Settings: unknown key or value refused; KVP round trip.

Smoke (kit-test server, driven from a button menu, not typed commands):

1. On foot: the health bar follows fall damage, the armour bar follows a vest; hunger and thirst bars follow qbx.
2. In a vehicle: speed, fuel and gear follow; the vehicle part disappears on exit.
3. Layout editor: all four stand-ins cover their parts; drag the minimap to the top-right and back (S3 again), scale
   the status part, hide the street part; reconnect keeps everything.
4. Minimap mode `vehicle` and `never`; resolution and safe-zone change keep the radar under its stand-in.
5. Base health and armour bars are hidden when `Config.hideBaseBars = true` (this step decides the open item above).
6. A test resource pushes two extra bars and removes one; stopping it removes the other.
7. Screenshots in Asphalt (normal and low values, numbers on) for the owner's visual gate; reduced motion stops all
   movement.

## Done when

All busted cases pass, `fivem-devkit safety` reports 0 errors and 0 over-declared items, the smoke steps pass on the
kit-test server, and the owner has passed the screenshots.

---

## 0.2 additions

- Version: 0.2.0 ([ADR 0005](../adr/0005-starter-kit-0-2.md) decision 1) · edges: `aeterna_core`, `aeterna_uikit`,
  `aeterna_layout` (unchanged), + `pma-voice` touched at run time only (ADR 0005 decision 4)
- Written by: Claude Code - Claude Opus 5.5 (helper)

Everything above stays valid. Already in 0.1, so not new here: the vehicle part's gear, speed and fuel; the street
part's eight-direction heading text; the four layout elements; extra bars from other resources.

| What | New in 0.2 |
| --- | --- |
| Bar style | ring or bar, a player setting |
| Compass | a tape compass, a new layout element |
| Voice | a voice indicator, shown only while `pma-voice` is started |
| Seatbelt | a seatbelt icon in the vehicle part, driven by a local event other resources fire |
| Round minimap | **not in 0.2**, deferred to 0.3 (ADR 0005 decision 11): it needs a streamed mask texture, which the safety scanner refuses as an opaque file |

The "Not in v0.1" line above that rules out voice indicators is superseded by ADR 0005 decision 4 for `pma-voice`
only. Seatbelt logic, engine damage, weapon display and cinematic mode stay out of the kit.

### Configuration (0.2)

| Key | Default | Meaning |
| --- | --- | --- |
| `Config.barStyle` | `'bar'` | `bar` or `ring`; the default for players who have not picked one |
| `Config.compass.enabled` | `true` | Register the `compass` element; `false` = no tape compass for anyone |
| `Config.compass.span` | `120` | Degrees visible on the tape, 60–180 |
| `Config.voice.enabled` | `true` | Show the voice indicator when `pma-voice` is started; `false` = never |
| `Config.seatbelt.enabled` | `true` | Show the seatbelt icon once a resource has set a state; `false` = never |

### Bar style

- `bar` is the 0.1 look. `ring` draws each status bar as a circular gauge (stroke `--track`, fill as in 0.1:
  `--accent` for health, `--text-2` for the others, `--bad` at or below `Config.low`), icon in the centre, the
  percentage under it when "Show numbers" is on.
- Extra bars from other resources follow the same style. The vehicle part's fuel follows it too.
- The `status` element's size changes with the style, so hudkit sends `aeterna_layout:add` again with the new
  `w`/`h`; layout keeps it on screen (see `aeterna_layout.md`, 0.2 clamp on size change).

### Compass tape

New layout element:

| `id` | Shows | Default place | `hideable` |
| --- | --- | --- | --- |
| `compass` | A horizontal tape centred on the camera heading: a tick every 15°, labels at N, NE, E, SE, S, SW, W, NW, and the heading in whole degrees under a centre mark | top-centre | `true` |

- Heading source is the 0.1 one (`GetGameplayCamRot` z), converted so 0° = N and degrees grow clockwise.
- Sent to NUI only when the whole-degree value changes; the tape moves with no transition (it follows the camera, so
  it is not decorative motion and stays under reduced motion).
- The `street` part keeps its heading text; a player who wants only the tape hides one of them in the layout editor.
- **Changed in 0.2** (the default screen gains an element). Upgrade note: servers that upgrade see a new element at
  the top centre. `Config.compass.enabled = false` keeps the
  0.1 screen.

### Voice indicator (`pma-voice`, optional)

New layout element:

| `id` | Shows | Default place | `hideable` |
| --- | --- | --- | --- |
| `voice` | A microphone icon: dim when silent, `--accent` while the player talks; the proximity mode label; a radio icon while the player is on a radio channel, highlighted while transmitting | above `status` | `true` |

Runtime detection, never a dependency:

- hudkit never lists `pma-voice` in `dependencies`, never calls `exports['pma-voice']`, and never loads its files.
- On start, and on `onClientResourceStart` / `onClientResourceStop` for `pma-voice`, it checks
  `GetResourceState('pma-voice') == 'started'`. Started → it registers the `voice` element and starts reading.
  Stopped → it sends `aeterna_layout:remove` for `voice` and stops reading.

What it reads (all on the client):

| Value | Source |
| --- | --- |
| Talking | `NetworkIsPlayerTalking(PlayerId())` (a game native; works for any voice resource that uses the game's voice chat) |
| Proximity mode | state bag `LocalPlayer.state.proximity` = `{ index, distance, mode }`, read with `AddStateBagChangeHandler`. Label = locale `hudkit.voice.mode.<index>` for index 1–3, else `distance` in metres |
| On a radio channel | state bag `LocalPlayer.state.radioChannel` (number; `0` or `nil` = none) |
| Transmitting on radio | the client-local event `pma-voice:radioActive` → `(boolean)` |

These state bag keys and the event name were checked against the `pma-voice` v7.0.2-rc3 source in the W0 spike
(2026-11-21): `proximity` is set as `{ index, distance, mode }`, `radioChannel` by the server, and
`pma-voice:radioActive` fired with `true` / `false`. A key that is absent leaves its part of the indicator hidden,
never an error. FiveM Enhanced has no Mumble (ADR 0005 decision 4), so whether the proximity mode and radio there
still mean anything is **not verified**; the W3 smoke checks it, and if they do not, hudkit hides those two parts
on Enhanced (talking still shows: it comes from a game native).

Reading another resource's state bag keys and listening to its local event needs no `oss.json` capability
(no `RegisterNetEvent`, no export).

### Seatbelt state (local event)

The kit has no seatbelt system. hudkit only shows a state that another resource sets:

| Event | Payload | Meaning |
| --- | --- | --- |
| `aeterna_hudkit:seatbelt` (client-local) | `{ on = boolean }` or `nil` | `true` / `false` shows the icon fastened or unfastened (`--bad`); `nil` hides it |

- The icon appears in the `vehicle` part only while the player is in a vehicle and only after some resource has
  fired the event. A seatbelt resource fires it when the state changes and when the player enters a vehicle.
- The last resource that fired it owns the state; when that resource stops, the icon is hidden. Owner detection
  follows the extra-bar rule above.
- hudkit does not fire this event itself, never blocks leaving the vehicle and never adds ejection.

### Settings (0.2)

While another resource holds `aeterna_core`'s focus overlay (core 0.2, [aeterna_core.md](aeterna_core.md) § Focus), the
settings card stays open and ignores input; a real focus loss closes it as in 0.1.

The settings card gains: **Bar style** (Bar · Ring). Voice, compass and seatbelt have no switch here; they are
hidden in the layout editor (`hideable`), which stays the one place for hiding.

### Storage (0.2)

KVP `aeterna_hudkit:settings:v1` gains the field `barStyle`. A saved 0.1 value has no `barStyle` and reads as
`Config.barStyle`, so the key keeps its name.

### NUI messages (0.2)

Lua → NUI adds `hud:compass {deg}`, `hud:voice {available, talking, mode, radio, radioActive}`,
`hud:seatbelt {state}` (`true`, `false` or `null`); `settings:open` carries `barStyle`.
NUI → Lua: `settings {key = 'barStyle', value}`; `ready` reports sizes for `compass` and `voice` too.

### Type tokens

0.1 sets pixel sizes in `style.css`. 0.2 uses the theme type tokens (ADR 0005 decision 9; `--fs-1` smallest …
`--fs-5` largest, line height `--lh`):

| Text | Token |
| --- | --- |
| Bar percentages, compass tick labels, speed unit, voice mode label | `--fs-1` |
| Street and zone name, compass degrees | `--fs-2` |
| Gear, fuel figure | `--fs-3` |
| Settings card title | `--fs-4` |
| Speed figure | `--fs-5` |

### Locale keys (0.2)

`hudkit.settings.barStyle`, `hudkit.settings.barStyle.bar`, `hudkit.settings.barStyle.ring`, `hudkit.part.compass`,
`hudkit.part.voice`, `hudkit.voice.mode.1`, `hudkit.voice.mode.2`, `hudkit.voice.mode.3`, `hudkit.voice.radio`,
`hudkit.vehicle.seatbelt.on`, `hudkit.vehicle.seatbelt.off`.

### `oss.json` (0.2)

No change: no new net event, command, convar or file.

### Tests (0.2, busted)

1. Compass: heading → tape offset for 0°, 359°, 360° and the wrap; labels at the eight directions; `span` outside
   60–180 clamps.
2. Ring geometry: value 0, 50, 100 and out-of-range values map to the right arc; `--bad` at `Config.low`.
3. Voice detection: `started` registers `voice`, `stopped` removes it, and with `Config.voice.enabled = false`
   nothing is registered either way.
4. Voice mode label: index 1–3 → locale key; index 4 → metres from `distance`; missing state → hidden.
5. Seatbelt: `true`, `false`, `nil`; hidden outside a vehicle; the owner stopping hides it.
6. Settings: `barStyle` accepts only `bar` and `ring`; a 0.1 KVP value without it reads as the config default.

### Self-tests (0.2)

Registered as `aeterna_hudkit.<name>`. "Skip when" is the only reason the test may report SKIP; a ped or eye test
with no person to run it reports GAP (ADR 0005 decision 7). A headless test needs no player and is listed as 1.

Kind `headless (client)` / `mock (client)` = `side = 'client'`: the test runs on the presser's client and is GAP
when there is no presser (ADR 0005 decision 7, W0 fix D3). Plain `headless` / `mock` run on the server.

| Name | Kind | Players | Destructive | Expect (what a person should see) | Skip when |
| --- | --- | --- | --- | --- | --- |
| `values_mapping` | headless | 1 | n | — | never |
| `compass_math` | headless | 1 | n | — | never |
| `bar_style` | eye | 1 | n | Switching Bar → Ring redraws every status bar as a ring; the status part stays on screen and its layout stand-in matches the new size | — |
| `compass_tape` | ped | 1 | n | Turning the camera a full circle moves the tape smoothly; N is at the centre mark when facing north | `Config.compass.enabled = false` |
| `voice_indicator` | ped | 1 | n | The microphone lights while the player talks; changing the proximity mode changes the label | `pma-voice` not started, or `Config.voice.enabled = false` |
| `voice_radio` | ped | 1 | n | The presser joins a radio channel: the radio icon shows; while the presser transmits it is highlighted | `pma-voice` not started, or `Config.voice.enabled = false` |
| `seatbelt_event` | mock (client) | 1 | n | — (the test fires `true`, `false` and `nil` on the presser's client in a vehicle, checks the NUI state, then fires `nil` to restore) | `Config.seatbelt.enabled = false` |
| `minimap_follows` | ped | 1 | n | The radar stays under its stand-in after dragging it to the top-right and back | — |

### Done when (0.2)

The 0.1 conditions, plus: the busted cases above pass, the `pma-voice` table above is verified and corrected, every
self-test above is registered and passes on the kit-test server (SKIP only for its listed reason), and the owner has
passed screenshots of bar and ring styles, the compass and the voice indicator in all three theme presets.
