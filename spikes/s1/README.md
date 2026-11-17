# S1 Spike: Cross-Resource NUI Layout Dragging

A FiveM experimental spike exploring whether one resource (`kspike_layout`) can allow players to visually drag and reposition UI elements drawn by other independent resources (`kspike_a`, `kspike_b`) in their own separate NUI frames by exchanging normalized coordinates.

## Resources Overview

1. **`kspike_layout`** (Editor, Coordinator & Test Menu):
   - Maintains an in-memory element registry and saves element positions to client KVP (`kspike_layout:pos`).
   - Dispatches `kspike:layout:hello` on start so active element owners can re-register.
   - Provides an on-screen test menu mapped to `F7` (`RegisterKeyMapping('kspike_menu', 'kspike test menu', 'keyboard', 'F7')`, also accessible via `/kspike_menu` command).
   - Menu buttons:
     - **"จัดตำแหน่งกล่อง (S1)"** — hint "ลากกรอบ A/B แล้วกด Done": Closes the menu and opens the drag editor overlay.
     - **"รีเซ็ตตำแหน่งกล่อง"** — hint "กลับตำแหน่งเริ่มต้น": Clears `savedPositions`, deletes KVP (`kspike_layout:pos`), restores default x/y coordinates for every registered element, triggers `kspike:layout:apply`, and reports reset to server (`TriggerServerEvent('kspike:report', 'layout', 'reset positions to defaults')`). Menu stays open and status displays "รีเซ็ตแล้ว".
     - **"ทดสอบธีมอีกครั้ง (S2)"** — hint "ดูผลที่มุมขวาบน": Dispatches local client event `kspike:s2:rerun` and closes the menu.
     - **"ปิด"** — hint "ปิดเมนู": Closes the menu.
   - Pressing `ESC` closes the menu (and closes edit mode).
   - Provides `/kspike_edit` command to directly toggle edit mode (`SetNuiFocus(true, true)`).
   - In edit mode, presents a transparent full-screen overlay drawing dashed outline boxes over each registered element.
   - Supports pointer dragging with throttled (100 ms) and on-drop NUI callbacks, broadcasting `kspike:layout:apply` client events.
   - Handles exit via `ESC` key or a visible "Done" button, returning focus and hiding the overlay.
   - Includes `server.lua` logging reports via net event `kspike:report`.

2. **`kspike_a`** (Element Owner A):
   - Renders a solid 220x80 px blue (`#2f6feb`) HUD box labeled "A".
   - Default position: `x = 0.05`, `y = 0.30` (normalized 0..1).
   - Measures bounding box on load, registers with `kspike:layout:register`, listens for `kspike:layout:apply`, and moves the box accordingly (`left = x * innerWidth`, `top = y * innerHeight`).
   - Reports applied position back to server log.

3. **`kspike_b`** (Element Owner B):
   - Renders a solid 220x80 px green (`#3fae6e`) HUD box labeled "B".
   - Default position: `x = 0.05`, `y = 0.45` (normalized 0..1).
   - Same coordinator handshake and listener protocol as `kspike_a`.

## Server Configuration

Add the following lines to your `server.cfg`:

```cfg
ensure kspike_layout
ensure kspike_a
ensure kspike_b
```

*(Note: Startup order is arbitrary; resources announce and synchronize via `kspike:layout:hello` and `kspike:layout:register`.)*

## Numbered Manual Test

Follow these steps to verify functionality:

1. **Join Server**: Connect to the server. Confirm that both boxes ("A" in blue and "B" in green) are visible at their default positions (left side: A at ~30% height, B at ~45% height).
2. **Open Test Menu**: Press `F7` (or type `/kspike_menu` in chat/console). The key can be rebound in GTA settings > Key Bindings > FiveM under "kspike test menu". A centered dark panel titled "kspike ทดสอบ" appears displaying the registered box count ("กล่องที่ลงทะเบียน: 2") and 4 buttons.
3. **Open Editor from Menu**: Click "จัดตำแหน่งกล่อง (S1)". The menu closes and the editor overlay opens with screen cursor and dashed outline boxes over boxes A and B. (The `/kspike_edit` command also remains available to open the editor directly).
4. **Drag Element**: Click and drag outline box A to the right. Notice that box A in `kspike_a` follows along smoothly in real time while dragging (updating every 100 ms at most) and snaps to the final drop position.
5. **Close Editor**: Click the "Done" button or press `ESC`. NUI focus returns to the game and the dashed outlines disappear.
6. **Reset Positions**: Press `F7` to open the test menu again. Click "รีเซ็ตตำแหน่งกล่อง". Notice that box A immediately snaps back to its initial default position (`x = 0.05`, `y = 0.30`), the KVP is cleared, the menu remains open, and its status line updates to "รีเซ็ตแล้ว".
7. **Close Menu**: Click "ปิด" or press `ESC` to close the test menu.
8. **Reconnect**: Rejoin the server or restart resources. Verify persistence and clean reset states across sessions.
9. **Resolution / Window Resize**: Resize the game window or change screen resolution. Confirm that both boxes scale their pixel positions to maintain their relative fractional positions on screen.
