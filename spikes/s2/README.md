# Kspike S2 Spikes

This directory contains throwaway FiveM spikes evaluating cross-resource NUI asset loading (stylesheets and web fonts loaded via `nui://` URLs from another resource).

## Resources

1. **`kspike_theme`**
   - Provides the shared theme CSS (`theme.css`) and declares `@font-face` pointing to `fonts/test.woff2`.
   - Contains a client script logging `[kspike_theme] started`.

2. **`kspike_c`**
   - The consumer resource containing an NUI UI page (`html/index.html`, `html/style.css`, `html/app.js`).
   - **Test A (Static Link):** `index.html` statically includes `<link rel="stylesheet" href="nui://kspike_theme/theme.css">` after style.css.
   - **Test B (Dynamic Link):** `app.js` listens for a NUI message from Lua (`{ type: 'theme', href: 'nui://kspike_theme/theme.css' }` or `{ type: 'rerun', ... }`) and dynamically appends a `<link>` element into `<head>` (id `dyn`).
   - Runs checks at 3s and 10s after link loading, testing `linkLoaded`, `cssRulesReadable`, `accentApplied`, `varApplied`, `fontLoaded`, `fontCheck`, `fontFaces`, and `location.origin`.
   - Reports results via NUI callback `result`, which Lua forwards via `TriggerServerEvent('kspike:report', 'kspike_c', ...)`, including the `run` counter field.
   - The status panel at the top-right corner displays the latest run number and check results.

## Setup & Configuration

1. Copy `test.woff2` into `spikes/s2/kspike_theme/fonts/test.woff2` by hand.
2. Add the following lines to your `server.cfg`:
   ```cfg
   ensure kspike_theme
   ensure kspike_c
   ensure kspike_layout
   ```
3. Read test results in the server console (lines starting with `[kspike]`) and on-screen in the top-right panel.

## Running Tests via F7 Menu

Tests can be triggered and re-run on demand without chat commands via the on-screen test menu provided by `kspike_layout`:

1. Press `F7` (or execute `/kspike_menu` in console). The keybinding can be rebound in GTA settings > Key Bindings > FiveM under "kspike test menu".
2. The menu displays four buttons:
   - **"จัดตำแหน่งกล่อง (S1)"** — hint "ลากกรอบ A/B แล้วกด Done": Opens HUD drag editor.
   - **"รีเซ็ตตำแหน่งกล่อง"** — hint "กลับตำแหน่งเริ่มต้น": Resets layout positions to defaults.
   - **"ทดสอบธีมอีกครั้ง (S2)"** — hint "ดูผลที่มุมขวาบน": Dispatches client event `kspike:s2:rerun`, closing the menu. `kspike_c` catches this event, cleans up any existing dynamic theme link (`#dyn`), and re-executes Test A and Test B with an incremented run counter (`run = 2, 3, ...`), updating the top-right status panel and server logs.
   - **"ปิด"** — hint "ปิดเมนู": Closes the menu.
