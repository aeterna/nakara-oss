-- spikes/s3/kspike_minimap/client.lua
-- Draggable game-drawn minimap coordinating with kspike_layout coordinator.

-- Default component offsets under ('L', 'B') alignment
local DEF_MINIMAP = { x = -0.0045, y = 0.002, w = 0.150, h = 0.188888 }
local DEF_MASK    = { x = 0.020,  y = 0.032, w = 0.111, h = 0.159 }
local DEF_BLUR    = { x = -0.030, y = 0.022, w = 0.266, h = 0.237 }

-- Aligned coordinate mapping reference points
local p0x, p0y = 0.0, 0.0
local p1x, p1y = 1.0, 1.0

-- Last tracked resolution, safezone, and applied position
local lastResX, lastResY = 0, 0
local lastSafezone = 0.0
local lastAppliedX = nil
local lastAppliedY = nil

-- Update linear mapping points using script gfx alignment
local function updateGfxAlignment()
    SetScriptGfxAlign(string.byte('L'), string.byte('B'))
    SetScriptGfxAlignParams(0.0, 0.0, 0.0, 0.0)
    p0x, p0y = GetScriptGfxPosition(0.0, 0.0)
    p1x, p1y = GetScriptGfxPosition(1.0, 1.0)
    ResetScriptGfxAlign()
end

-- Convert aligned offset (ax, ay) to screen fraction (sx, sy)
local function alignedToScreen(ax, ay)
    local sx = p0x + ax * (p1x - p0x)
    local sy = p0y + ay * (p1y - p0y)
    return sx, sy
end

-- Convert screen fraction (sx, sy) to aligned offset (ax, ay)
local function screenToAligned(sx, sy)
    local ax = (sx - p0x) / (p1x - p0x)
    local ay = (sy - p0y) / (p1y - p0y)
    return ax, ay
end

-- Chosen formula: Under GTA V 'B' (Bottom) alignment, the native offset y anchors
-- the bottom edge of the component. The top-left in aligned space is therefore
-- (x, y - h). This places the element inside the safe zone at bottom-left with
-- its bottom edge near (1 - safezone margin).
local function getMinimapScreenRect(alignedX, alignedY, w, h)
    local tlX, tlY = alignedToScreen(alignedX, alignedY - h)
    local brX, brY = alignedToScreen(alignedX + w, alignedY)
    return {
        x = tlX,
        y = tlY,
        w = math.abs(brX - tlX),
        h = math.abs(brY - tlY),
        bottom = brY
    }
end

-- Convert top-left screen fraction back to minimap native offset (x, y)
local function screenToMinimapOffset(sx, sy)
    local ax, ayTop = screenToAligned(sx, sy)
    local x = ax
    local y = ayTop + DEF_MINIMAP.h
    return x, y
end

-- Evaluate both readings of 'B' alignment and print rect comparisons
local function evaluateReadings()
    -- Reading A: top-left is (x, y - h)
    local rectA = getMinimapScreenRect(DEF_MINIMAP.x, DEF_MINIMAP.y, DEF_MINIMAP.w, DEF_MINIMAP.h)

    -- Reading B: top-left is (x, y)
    local tlB_x, tlB_y = alignedToScreen(DEF_MINIMAP.x, DEF_MINIMAP.y)
    local brB_x, brB_y = alignedToScreen(DEF_MINIMAP.x + DEF_MINIMAP.w, DEF_MINIMAP.y + DEF_MINIMAP.h)
    local rectB = {
        x = tlB_x,
        y = tlB_y,
        w = math.abs(brB_x - tlB_x),
        h = math.abs(brB_y - tlB_y),
        bottom = brB_y
    }

    print(string.format('[kspike_minimap] Reading A (top-left is x, y - h): x=%.4f y=%.4f w=%.4f h=%.4f bottom=%.4f',
        rectA.x, rectA.y, rectA.w, rectA.h, rectA.bottom))
    print(string.format('[kspike_minimap] Reading B (top-left is x, y):     x=%.4f y=%.4f w=%.4f h=%.4f bottom=%.4f',
        rectB.x, rectB.y, rectB.w, rectB.h, rectB.bottom))
end

-- Register element with kspike_layout coordinator
local function registerWithLayout()
    local resX, resY = GetActiveScreenResolution()
    local defRect = getMinimapScreenRect(DEF_MINIMAP.x, DEF_MINIMAP.y, DEF_MINIMAP.w, DEF_MINIMAP.h)
    local pxW = math.floor(defRect.w * resX + 0.5)
    local pxH = math.floor(defRect.h * resY + 0.5)

    TriggerEvent('kspike:layout:register', {
        owner = GetCurrentResourceName(),
        id = 'minimap',
        w = pxW,
        h = pxH,
        x = defRect.x,
        y = defRect.y
    })
end

-- Apply new top-left screen fraction to all 3 minimap components
local function applyPosition(fracX, fracY)
    local x = tonumber(fracX) or lastAppliedX
    local y = tonumber(fracY) or lastAppliedY
    if not x or not y then
        return
    end

    lastAppliedX = x
    lastAppliedY = y

    local mmX, mmY = screenToMinimapOffset(x, y)
    local dx = mmX - DEF_MINIMAP.x
    local dy = mmY - DEF_MINIMAP.y

    local newMinimapX = DEF_MINIMAP.x + dx
    local newMinimapY = DEF_MINIMAP.y + dy

    local newMaskX = DEF_MASK.x + dx
    local newMaskY = DEF_MASK.y + dy

    local newBlurX = DEF_BLUR.x + dx
    local newBlurY = DEF_BLUR.y + dy

    SetMinimapComponentPosition('minimap', 'L', 'B', newMinimapX, newMinimapY, DEF_MINIMAP.w, DEF_MINIMAP.h)
    SetMinimapComponentPosition('minimap_mask', 'L', 'B', newMaskX, newMaskY, DEF_MASK.w, DEF_MASK.h)
    SetMinimapComponentPosition('minimap_blur', 'L', 'B', newBlurX, newBlurY, DEF_BLUR.w, DEF_BLUR.h)

    CreateThread(function()
        SetBigmapActive(true, false)
        Wait(0)
        SetBigmapActive(false, false)
    end)

    DisplayRadar(true)

    local resX, resY = GetActiveScreenResolution()
    local sz = GetSafeZoneSize()
    local rect = getMinimapScreenRect(newMinimapX, newMinimapY, DEF_MINIMAP.w, DEF_MINIMAP.h)
    local pxW = math.floor(rect.w * resX + 0.5)
    local pxH = math.floor(rect.h * resY + 0.5)

    local msg = string.format('frac=(%.4f,%.4f) mm=(%.4f,%.4f) mask=(%.4f,%.4f) blur=(%.4f,%.4f) px=(%dx%d) res=(%dx%d) sz=%.2f',
        x, y, newMinimapX, newMinimapY, newMaskX, newMaskY, newBlurX, newBlurY, pxW, pxH, resX, resY, sz)
    TriggerServerEvent('kspike:report', 'kspike_minimap', msg)
end

-- Handle position updates from layout coordinator
AddEventHandler('kspike:layout:apply', function(owner, id, x, y)
    if owner == GetCurrentResourceName() and id == 'minimap' then
        applyPosition(x, y)
    end
end)

-- Re-register when layout coordinator starts or restarts
AddEventHandler('kspike:layout:hello', function()
    updateGfxAlignment()
    registerWithLayout()
end)

-- Startup initialization
CreateThread(function()
    Wait(500)
    local resX, resY = GetActiveScreenResolution()
    lastResX = resX
    lastResY = resY
    lastSafezone = GetSafeZoneSize()

    updateGfxAlignment()
    evaluateReadings()

    local defRect = getMinimapScreenRect(DEF_MINIMAP.x, DEF_MINIMAP.y, DEF_MINIMAP.w, DEF_MINIMAP.h)
    lastAppliedX = defRect.x
    lastAppliedY = defRect.y

    registerWithLayout()
end)

-- Monitor resolution and safezone changes every 1000 ms
CreateThread(function()
    while true do
        Wait(1000)
        local resX, resY = GetActiveScreenResolution()
        local sz = GetSafeZoneSize()
        if resX ~= lastResX or resY ~= lastResY or math.abs(sz - lastSafezone) > 0.0001 then
            lastResX = resX
            lastResY = resY
            lastSafezone = sz
            updateGfxAlignment()
            registerWithLayout()
            if lastAppliedX and lastAppliedY then
                applyPosition(lastAppliedX, lastAppliedY)
            end
        end
    end
end)
