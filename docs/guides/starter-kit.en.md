# AETERNA Starter Kit guide

Twelve MIT-licensed FiveM resources (0.2) for your own server. They are templates: read them, change them, and keep what you need.

## What you need

Tested together on FXServer Enhanced (game build 3788) with `qbx_core` 1.23.0, `ox_lib` 3.30.6, `oxmysql` 2.14.3 and
`ox_inventory` 2.44.0. Other versions may work; they are not tested. Three things are optional and only switch a
feature on: `ox_inventory` (`aeterna_invkit`), `pma-voice` (calls in `aeterna_phonecall` on Legacy, the voice indicator in
`aeterna_hudkit`) and `screenshot-basic` (taking photos in `aeterna_camera`). Without one, the feature that needs it
reports itself unavailable.

| Resource | Needs |
| --- | --- |
| `aeterna_core` | nothing |
| `aeterna_uikit` | `aeterna_core` |
| `aeterna_notify` | `aeterna_core` (`aeterna_layout` if you want toasts to be movable) |
| `aeterna_layout` | `aeterna_core`, `aeterna_uikit` |
| `aeterna_hudkit` | `aeterna_core`, `aeterna_uikit`, `aeterna_layout` |
| `aeterna_phonekit` | `aeterna_core`, `aeterna_uikit`, `aeterna_notify` (`aeterna_layout` if you want the phone to be movable) |
| `aeterna_invkit` | `aeterna_core`, `aeterna_uikit`, `ox_inventory` |
| `aeterna_testkit` | `aeterna_core`, `aeterna_uikit` |
| `aeterna_radial` | `aeterna_core`, `aeterna_uikit` |
| `aeterna_loading` | nothing (`aeterna_core` if you want its self-test registered) |
| `aeterna_phonecall` | `aeterna_core`, `aeterna_uikit`, `aeterna_phonekit` |
| `aeterna_camera` | `aeterna_core`, `aeterna_uikit`, `aeterna_phonekit`, `aeterna_notify` |

## Install

1. Download `aeterna-starter-kit-0.2.0.zip` from
   [Releases](https://github.com/aeterna/nakara-oss/releases/tag/aeterna-starter-kit%400.2.0) (tag
   `aeterna-starter-kit@0.2.0`). Check it first: `gh attestation verify <zip> --repo aeterna/nakara-oss`.
2. Unpack it into `resources/`. You get `resources/[aeterna_kit]/` with all 12 resources and `resources.cfg`. Prefer to pick? Download single packages
   from [Releases](https://github.com/aeterna/nakara-oss/releases?q=aeterna_) and unpack them into
   `resources/[aeterna_kit]/`. Each folder keeps its name, for example `aeterna_core`.
3. Copy [`kits/starter/resources.cfg`](../../kits/starter/resources.cfg) (it is in the zip too) into `server.cfg`, after
   your framework.
4. Restart the server, join as an account with ACE `aeterna.testkit.run`, press F9 and choose **Run all**. Every row
   should pass or skip. The report is saved under `aeterna_testkit/reports/` and can be attached to an issue as it is.
   `aeterna_core_selftest` in the server console still runs the core tests alone.

## Default keys

The kit suggests keys for its openers: F5 menu, M phone, F3 radial menu (keyboard), F2 inventory panel, F9 test menu,
Y and U for toast actions, PageUp and PageDown to answer and hang up a call. A key a player sets in Settings → Key
Bindings → FiveM always wins. Owners change or turn off the defaults with one convar:

```
setr aeterna_keys ""                                           # kit defaults
setr aeterna_keys "off"                                        # no defaults
setr aeterna_keys "+aeterna_phonekit_open=F1, +aeterna_testkit_menu="   # change one, clear one
```

| Command | Key mapping | Does |
| --- | --- | --- |
| `aeterna_uikit_menu` | `+aeterna_uikit_menu` | Opens the kit menu |
| `aeterna_layout` | `+aeterna_layout_edit` | Opens the layout editor |
| `aeterna_hudkit_settings` | `+aeterna_hudkit_settings` | Opens HUD settings |
| `aeterna_phonekit_open` | `+aeterna_phonekit_open` | Opens the phone |
| none | `+aeterna_radial_open` | Opens the radial menu |
| none | `+aeterna_testkit_menu` | Opens the test menu, needs ACE `aeterna.testkit.run` |
| `aeterna_stash` | `+aeterna_invkit_open` | Opens the personal stash, when enabled in config |
| `aeterna_announce <text>` | none | Sends an announcement, needs ACE `aeterna.notify.announce` |
| `aeterna_core_selftest` | none | Runs the core self tests, needs ACE `aeterna.core.selftest` |

## Settings

| Convar | Meaning |
| --- | --- |
| `aeterna_locale` | `en` or `th`. Use `setr` |
| `aeterna_timezone` | Clock offset such as `+07:00`. Use `setr` |
| `aeterna_theme` | Your stylesheet, below. Use `setr` |
| `aeterna_theme_preset` | `asphalt` (default), `paper` or `night-market`. Use `setr` |
| `aeterna_keys` | Change or turn off the default keys, above. Use `setr` |
| `aeterna_core_log_level` | How much the kit logs |
| `aeterna_uikit_menu_title` | Title of the kit menu |

Each package also has a `config.lua`. Player settings and layouts stay on the player's machine; the kit creates no
database tables.

## Change the look

Pick a ready-made look with `setr aeterna_theme_preset asphalt`, `paper` (light) or `night-market` (dark, orange). To go
further, every screen reads the colours in `html/theme.css`. To restyle all of them at once, make a small resource:

```lua
-- my_theme/fxmanifest.lua
fx_version 'cerulean'
game 'gta5'
files { 'theme.css' }
```

```css
/* my_theme/theme.css */
:root {
    --accent: #0f9d76;
    --surface: #17191c;
    --raised: #202328;
    --radius-m: 6px;
}
```

Then add `ensure my_theme` before the kit and `setr aeterna_theme "nui://my_theme/theme.css"`. Your file loads after the
default one, so set only what you want to change. A font file can live in the same resource with an `@font-face` rule.

`ox_inventory` has its own interface and its own GPL-3.0 licence. The kit does not restyle it or include any of its
files. If you change its web files, your changes follow its licence.

## Build on it

- Panels and prompts: [`aeterna_uikit`](../specs/aeterna_uikit.md)
- Toasts and announcements: [`aeterna_notify`](../specs/aeterna_notify.md)
- Making your own UI movable: [`aeterna_layout`](../specs/aeterna_layout.md)
- Extra HUD bars: [`aeterna_hudkit`](../specs/aeterna_hudkit.md)
- Phone apps: [`aeterna_phonekit`](../specs/aeterna_phonekit.md)
- Stash and item use: [`aeterna_invkit`](../specs/aeterna_invkit.md)
- Adding slots to the radial menu: [`aeterna_radial`](../specs/aeterna_radial.md)
- Loading screen: [`aeterna_loading`](../specs/aeterna_loading.md)
- Registering your own self-tests: [`aeterna_testkit`](../specs/aeterna_testkit.md)
- Phone numbers, messages and calls: [`aeterna_phonecall`](../specs/aeterna_phonecall.md)
- Camera and gallery: [`aeterna_camera`](../specs/aeterna_camera.md)

## Limits

Not yet checked on a live server: an SMS between two players, a call between two players, a busy line, and the test
menu's player B card (see [CHANGELOG](../../kits/starter/CHANGELOG.md)). The phone has no banking. The kit was tested
with one player on FXServer Enhanced b177 with `qbx_core`. It is offered as is under the MIT licence: open an issue
with your versions and the error (the test menu's report has both) if something breaks.
