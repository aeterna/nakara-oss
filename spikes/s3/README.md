# S3 Spike: Game-Drawn Minimap Repositioning via Layout Protocol

This spike evaluates whether the native, game-drawn GTA V radar (minimap) can participate as a draggable element managed by `kspike_layout`'s cross-resource layout protocol using FiveM natives instead of CSS styling.

## Question Answered

**Can the GAME-DRAWN minimap (radar) be one of those draggable elements, by the same protocol, using natives instead of CSS?**

**Yes.** By dynamically mapping between GTA V aligned coordinate space (`SetScriptGfxAlign`) and normalized screen fraction coordinates (0.0 to 1.0) without hard-coded aspect ratios, the minimap bounding box can be registered with `kspike_layout` and repositioned across the screen. Applying offset deltas to the three synchronized radar components (`minimap`, `minimap_mask`, `minimap_blur`) and forcing a redraw via `SetBigmapActive` moves the game radar in real time.

## Resources Overview

1. **`kspike_minimap`**
   - Calculates screen-fraction bounding rect and pixel dimensions from GTA V script graphics alignment.
   - Evaluates 'B' alignment readings: under bottom alignment, native offset `y` anchors the bottom edge of the minimap, so top-left in aligned space is `(x, y - h)`.
   - Registers with `kspike_layout` under `id = 'minimap'` with initial screen fractions and pixel dimensions derived from `GetActiveScreenResolution()`.
   - Listens to `kspike:layout:apply` events, translates normalized screen coordinates back into native aligned offsets, updates `minimap`, `minimap_mask`, and `minimap_blur` via `SetMinimapComponentPosition`, and refreshes the radar with `SetBigmapActive(true, false)` / `SetBigmapActive(false, false)`.
   - Reports applied position, component offsets, pixel dimensions, screen resolution, and safezone size to the server via `kspike:report`.
   - Polls resolution and safezone changes every 1000 ms, re-registering and re-applying positions dynamically.

## Server Configuration

Add the following lines to your `server.cfg` (ensuring `kspike_minimap` is started after `kspike_layout`):

```cfg
ensure kspike_layout
ensure kspike_a
ensure kspike_b
ensure kspike_minimap
```

## Numbered Manual Test

Follow these steps to verify functionality:

1. **Join Server**: Connect to the server. Confirm that the game-drawn minimap is visible at its normal default position at the bottom-left inside the safezone.
2. **Open Test Menu & Editor**: Press `F7` (or type `/kspike_menu` in chat/console) to open the test menu. Click **"จัดตำแหน่งกล่อง (S1)"**. The menu closes and the editor overlay opens. A third dashed box labeled `"kspike_minimap/minimap"` sits exactly over the real game minimap.
3. **Drag Minimap**: Click and drag the dashed `"kspike_minimap/minimap"` box to the top-right corner of the screen. The real game minimap follows along smoothly while dragging and stays at the new position after clicking **"Done"** (or pressing `ESC`).
4. **Reconnect**: Disconnect and rejoin the server (or restart the resources). The minimap keeps its custom saved position loaded from client KVP storage.
5. **Reset Positions**: Press `F7` to open the test menu again. Click **"รีเซ็ตตำแหน่งกล่อง"**. The minimap immediately snaps back to its initial default position at the bottom-left.
6. **Resolution / Safezone Adjustment**: Change the display resolution or adjust safezone size (**Settings > Display > Safezone Size**). Confirm that the minimap maintains its relative place and opening edit mode shows the dashed box still precisely covering the radar.
