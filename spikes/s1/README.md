# S1 Spike: Cross-Resource NUI Layout Dragging

A FiveM experimental spike exploring whether one resource (`kspike_layout`) can allow players to visually drag and reposition UI elements drawn by other independent resources (`kspike_a`, `kspike_b`) in their own separate NUI frames by exchanging normalized coordinates.

## Resources Overview

1. **`kspike_layout`** (Editor & Coordinator):
   - Maintains an in-memory element registry and saves element positions to client KVP (`kspike_layout:pos`).
   - Dispatches `kspike:layout:hello` on start so active element owners can re-register.
   - Provides `/kspike_edit` command to toggle edit mode (`SetNuiFocus(true, true)`).
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
2. **Open Editor**: Type `/kspike_edit` in chat/console. The screen cursor should appear along with a top toolbar and two dashed outline boxes overlaid directly on top of boxes A and B, labeled `kspike_a/box` and `kspike_b/box`.
3. **Drag Element**: Click and drag outline box A to the right. Notice that box A in `kspike_a` follows along smoothly in real time while dragging (updating every 100 ms at most) and snaps to the final drop position.
4. **Close Editor**: Click the "Done" button or press the `ESC` key. NUI input focus returns to the game, the dashed outlines disappear, clicks pass through normally to the game, and both boxes remain at their current positions.
5. **Reconnect**: Disconnect and rejoin the server (or restart the resources). Verify that the custom dragged position for box A is restored from KVP persistence rather than reverting to the default.
6. **Resolution / Window Resize**: Resize the game window or change screen resolution. Confirm that both boxes scale their pixel positions to maintain their relative fractional positions on screen.
