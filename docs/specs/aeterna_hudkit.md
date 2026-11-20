# aeterna_hudkit

- Package: `packages/hudkit` · resource `aeterna_hudkit` · wave W3 · status released in 0.1.0
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
