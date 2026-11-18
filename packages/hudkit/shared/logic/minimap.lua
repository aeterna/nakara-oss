-- shared/logic/minimap.lua -- natives-free minimap coordinate math and component positioning.
-- Proof of concept from Spike S3 (ADR 0004 decision 12).

MinimapLogic = MinimapLogic or {}

-- Default offsets measured in Spike S3 (clean FXServer Enhanced / GTA V b1604+, 1920x1080 default radar).
-- Native: SetMinimapComponentPosition(name, 'L', 'B', x, y, w, h)
MinimapLogic.DEFAULT_COMPONENTS = {
    minimap = { x = -0.0045, y = -0.0245, w = 0.150, h = 0.188888 },
    minimap_mask = { x = 0.0200, y = 0.0320, w = 0.111, h = 0.159000 },
    minimap_blur = { x = -0.0300, y = 0.0220, w = 0.266, h = 0.237000 },
}

MinimapLogic.SCALE_MIN = 0.75
MinimapLogic.SCALE_MAX = 1.5

--- Maps an aligned offset under ('L', 'B') alignment to screen fraction [0, 1].
function MinimapLogic.offsetToScreen(ox, oy, p0, p1)
    local sx = p0.x + ox * (p1.x - p0.x)
    local sy = p0.y + oy * (p1.y - p0.y)
    return sx, sy
end

--- Maps a screen fraction [0, 1] to aligned offset under ('L', 'B') alignment.
function MinimapLogic.screenToOffset(sx, sy, p0, p1)
    local ox = (sx - p0.x) / (p1.x - p0.x)
    local oy = (sy - p0.y) / (p1.y - p0.y)
    return ox, oy
end

--- Computes component size in screen pixels from native component size.
function MinimapLogic.screenSizeToPixels(w, h, p0, p1, screenW, screenH)
    local pxW = math.abs(w * (p1.x - p0.x) * screenW)
    local pxH = math.abs(h * (p1.y - p0.y) * screenH)
    return math.floor(pxW + 0.5), math.floor(pxH + 0.5)
end

--- Clamps scale within the valid visual range (0.75 to 1.5).
function MinimapLogic.clampScale(scale)
    local s = tonumber(scale) or 1.0
    if s < MinimapLogic.SCALE_MIN then s = MinimapLogic.SCALE_MIN end
    if s > MinimapLogic.SCALE_MAX then s = MinimapLogic.SCALE_MAX end
    return s
end

--- Computes moved component positions given a delta offset and scale.
--- All three components (minimap, minimap_mask, minimap_blur) move by the same delta,
--- preserving their relative offsets.
function MinimapLogic.computePositions(deltaX, deltaY, scale, defaults)
    local defs = defaults or MinimapLogic.DEFAULT_COMPONENTS
    local s = MinimapLogic.clampScale(scale)
    local dx = tonumber(deltaX) or 0.0
    local dy = tonumber(deltaY) or 0.0
    local positions = {}
    for name, def in pairs(defs) do
        positions[name] = {
            x = def.x + dx,
            y = def.y + dy,
            w = def.w * s,
            h = def.h * s,
        }
    end
    return positions
end

return MinimapLogic
