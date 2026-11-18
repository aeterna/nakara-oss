# AETERNA Starter Kit guide

Seven MIT-licensed FiveM resources for your own server. They are templates: read them, change them, and keep what you need.

## What you need

Tested together on FXServer Enhanced (game build 3788) with `qbx_core` 1.23.0, `ox_lib` 3.30.6, `oxmysql` 2.14.3 and
`ox_inventory` 2.44.0. Other versions may work; they are not tested. `aeterna_invkit` is the only package that needs
`ox_inventory`.

| Resource | Needs |
| --- | --- |
| `aeterna_core` | nothing |
| `aeterna_uikit` | `aeterna_core` |
| `aeterna_notify` | `aeterna_core` (`aeterna_layout` if you want toasts to be movable) |
| `aeterna_layout` | `aeterna_core`, `aeterna_uikit` |
| `aeterna_hudkit` | `aeterna_core`, `aeterna_uikit`, `aeterna_layout` |
| `aeterna_phonekit` | `aeterna_core`, `aeterna_uikit`, `aeterna_notify` (`aeterna_layout` if you want the phone to be movable) |
| `aeterna_invkit` | `aeterna_core`, `aeterna_uikit`, `ox_inventory` |

## Install

1. Download the zips from [Releases](https://github.com/aeterna/nakara-oss/releases?q=aeterna_). Check each one first:
   `gh attestation verify <zip> --repo aeterna/nakara-oss`.
2. Unpack them into `resources/[aeterna_kit]/`. Each folder keeps its name, for example `aeterna_core`.
3. Copy [`kits/starter/resources.cfg`](../../kits/starter/resources.cfg) into `server.cfg`, after your framework.
4. Restart the server. As an admin, run `aeterna_core_selftest` in the server console. Every line should pass.

No package sets a default key, so nothing clashes with your other resources. Players bind keys in
Settings → Key Bindings → FiveM.

| Command | Key mapping | Does |
| --- | --- | --- |
| `aeterna_uikit_menu` | `+aeterna_uikit_menu` | Opens the kit menu |
| `aeterna_layout` | `+aeterna_layout_edit` | Opens the layout editor |
| `aeterna_hudkit_settings` | `+aeterna_hudkit_settings` | Opens HUD settings |
| `aeterna_phonekit_open` | `+aeterna_phonekit_open` | Opens the phone |
| `aeterna_stash` | `+aeterna_invkit_open` | Opens the personal stash, when enabled in config |
| `aeterna_announce <text>` | none | Sends an announcement, needs ACE `aeterna.notify.announce` |
| `aeterna_core_selftest` | none | Runs the self tests, needs ACE `aeterna.core.selftest` |

## Settings

| Convar | Meaning |
| --- | --- |
| `aeterna_locale` | `en` or `th`. Use `setr` |
| `aeterna_timezone` | Clock offset such as `+07:00`. Use `setr` |
| `aeterna_theme` | Your stylesheet, below. Use `setr` |
| `aeterna_core_log_level` | How much the kit logs |
| `aeterna_uikit_menu_title` | Title of the kit menu |

Each package also has a `config.lua`. Player settings and layouts stay on the player's machine; the kit creates no
database tables.

## Change the look

Every screen reads the colours in `html/theme.css`. To restyle all of them at once, make a small resource:

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

## Limits

The phone has no calls, messages between players, camera or banking; add them as apps. The HUD has no voice indicator
and no round minimap. The kit is offered as is under the MIT licence: open an issue with your versions and the error
if something breaks.
