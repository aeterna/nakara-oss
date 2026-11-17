-- spikes/s1/kspike_b/client.lua
-- Element owner B: displays HUD box "B" and coordinates with kspike_layout.

local DEFAULT_X = 0.05
local DEFAULT_Y = 0.45

local currentX = DEFAULT_X
local currentY = DEFAULT_Y
local boxW = 220
local boxH = 80
local isNuiReady = false

-- Register or re-register this element with layout coordinator
local function registerWithLayout()
    TriggerEvent('kspike:layout:register', {
        owner = GetCurrentResourceName(),
        id = 'box',
        w = boxW,
        h = boxH,
        x = currentX,
        y = currentY
    })
end

-- NUI callback: page ready and initial dimensions measured
RegisterNUICallback('ready', function(data, cb)
    isNuiReady = true
    if data and data.w and data.h then
        boxW = tonumber(data.w) or boxW
        boxH = tonumber(data.h) or boxH
    end

    registerWithLayout()
    cb('ok')
end)

-- Re-register when layout coordinator starts or restarts
AddEventHandler('kspike:layout:hello', function()
    if isNuiReady then
        registerWithLayout()
    end
end)

-- Apply position dispatched by layout coordinator
AddEventHandler('kspike:layout:apply', function(owner, id, x, y)
    if owner == GetCurrentResourceName() and id == 'box' then
        currentX = tonumber(x) or currentX
        currentY = tonumber(y) or currentY
        SendNUIMessage({
            type = 'pos',
            x = currentX,
            y = currentY
        })
    end
end)

-- NUI callback: position applied, report back to server log
RegisterNUICallback('applied', function(data, cb)
    local msg = ('applied x=%.4f y=%.4f left=%.1f top=%.1f'):format(
        tonumber(data.x) or 0.0,
        tonumber(data.y) or 0.0,
        tonumber(data.left) or 0.0,
        tonumber(data.top) or 0.0
    )
    TriggerServerEvent('kspike:report', GetCurrentResourceName(), msg)
    cb('ok')
end)
