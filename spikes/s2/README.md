# Kspike S2 Spikes

This directory contains throwaway FiveM spikes evaluating cross-resource NUI asset loading (stylesheets and web fonts loaded via `nui://` URLs from another resource).

## Resources

1. **`kspike_theme`**
   - Provides the shared theme CSS (`theme.css`) and declares `@font-face` pointing to `fonts/test.woff2`.
   - Contains a client script logging `[kspike_theme] started`.

2. **`kspike_c`**
   - The consumer resource containing an NUI UI page (`html/index.html`, `html/style.css`, `html/app.js`).
   - **Test A (Static Link):** `index.html` statically includes `<link rel="stylesheet" href="nui://kspike_theme/theme.css">` after style.css.
   - **Test B (Dynamic Link):** `app.js` listens for a NUI message from Lua (`{ type: 'theme', href: 'nui://kspike_theme/theme.css' }`) and dynamically appends a `<link>` element into `<head>` (id `dyn`).
   - Runs checks at 3s and 10s after link loading, testing `linkLoaded`, `cssRulesReadable`, `accentApplied`, `varApplied`, `fontLoaded`, `fontCheck`, `fontFaces`, and `location.origin`.
   - Reports results via NUI callback `result`, which Lua forwards via `TriggerServerEvent('kspike:report', 'kspike_c', ...)`.

## Setup & Configuration

1. Copy `test.woff2` into `spikes/s2/kspike_theme/fonts/test.woff2` by hand.
2. Add the following lines to your `server.cfg`:
   ```cfg
   ensure kspike_theme
   ensure kspike_c
   ```
3. Read test results in the server console (lines starting with `[kspike]`).
