-- spikes/s1/kspike_layout/client.lua
-- Layout coordinator and editor for external NUI HUD elements.

local registry = {}
local savedPositions = {}
local isEditing = false

-- Load stored positions from resource KVP
local function loadStoredPositions()
    local raw = GetResourceKvpString('kspike_layout:pos')
    if raw and raw ~= '' then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            savedPositions = decoded
        end
    end
end

loadStoredPositions()

-- Register element handler
AddEventHandler('kspike:layout:register', function(data)
    if type(data) ~= 'table' or not data.owner or not data.id then
        return
    end

    local owner = tostring(data.owner)
    local id = tostring(data.id)
    local key = owner .. ':' .. id

    local elem = {
        owner = owner,
        id = id,
        w = tonumber(data.w) or 100,
        h = tonumber(data.h) or 100,
        x = tonumber(data.x) or 0.0,
        y = tonumber(data.y) or 0.0
    }

    -- If a stored position exists for owner+id, immediately apply it
    if savedPositions[key] then
        elem.x = savedPositions[key].x
        elem.y = savedPositions[key].y
        TriggerEvent('kspike:layout:apply', elem.owner, elem.id, elem.x, elem.y)
    end

    -- Re-registering replaces existing entry
    registry[key] = elem
end)

-- Helper to convert registry map to a list for NUI
local function getRegistryList()
    local list = {}
    for _, elem in pairs(registry) do
        table.insert(list, {
            owner = elem.owner,
            id = elem.id,
            w = elem.w,
            h = elem.h,
            x = elem.x,
            y = elem.y
        })
    end
    return list
end

-- Command to toggle edit mode
RegisterCommand('kspike_edit', function()
    isEditing = not isEditing

    if isEditing then
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = 'open',
            elements = getRegistryList()
        })
    else
        SetNuiFocus(false, false)
        SendNUIMessage({
            action = 'close'
        })
        TriggerServerEvent('kspike:report', 'layout', 'editor closed via command')
    end
end, false)

-- NUI callback: moved element
RegisterNUICallback('moved', function(data, cb)
    if data and data.owner and data.id and data.x and data.y then
        local owner = tostring(data.owner)
        local id = tostring(data.id)
        local x = tonumber(data.x) or 0.0
        local y = tonumber(data.y) or 0.0
        local key = owner .. ':' .. id

        if registry[key] then
            registry[key].x = x
            registry[key].y = y
        end

        savedPositions[key] = { x = x, y = y }
        SetResourceKvp('kspike_layout:pos', json.encode(savedPositions))

        TriggerEvent('kspike:layout:apply', owner, id, x, y)
        TriggerServerEvent('kspike:report', 'layout', ('moved %s/%s to x=%.4f y=%.4f'):format(owner, id, x, y))
    end
    cb('ok')
end)

-- NUI callback: close editor
RegisterNUICallback('close', function(data, cb)
    if isEditing then
        isEditing = false
        SetNuiFocus(false, false)
        SendNUIMessage({
            action = 'close'
        })
        TriggerServerEvent('kspike:report', 'layout', 'editor closed via NUI')
    end
    cb('ok')
end)

-- Announce presence so already-started owner resources can re-register
TriggerEvent('kspike:layout:hello')
