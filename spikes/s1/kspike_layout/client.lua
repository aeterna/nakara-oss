-- spikes/s1/kspike_layout/client.lua
-- Layout coordinator and editor for external NUI HUD elements.

local registry = {}
local savedPositions = {}
local defaultPositions = {}
local isEditing = false
local isMenuOpen = false

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

-- Helper to count registered elements
local function getRegistryCount()
    local count = 0
    for _ in pairs(registry) do
        count = count + 1
    end
    return count
end

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

-- Open editor mode
local function openEditor()
    isMenuOpen = false
    isEditing = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        elements = getRegistryList()
    })
end

-- Open menu mode
local function openMenu()
    isEditing = false
    isMenuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'menu',
        count = getRegistryCount()
    })
end

-- Close any open UI
local function closeAll()
    local wasOpen = isEditing or isMenuOpen
    isEditing = false
    isMenuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'close'
    })
    return wasOpen
end

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

    -- Store default position from the first register call before saved position is applied
    if not defaultPositions[key] then
        defaultPositions[key] = {
            x = elem.x,
            y = elem.y
        }
    end

    -- If a stored position exists for owner+id, immediately apply it
    if savedPositions[key] then
        elem.x = savedPositions[key].x
        elem.y = savedPositions[key].y
        TriggerEvent('kspike:layout:apply', elem.owner, elem.id, elem.x, elem.y)
    end

    -- Re-registering replaces existing entry
    registry[key] = elem
end)

-- Command to toggle edit mode
RegisterCommand('kspike_edit', function()
    if isEditing then
        closeAll()
        TriggerServerEvent('kspike:report', 'layout', 'editor closed via command')
    else
        openEditor()
    end
end, false)

-- Command to open or toggle test menu
RegisterCommand('kspike_menu', function()
    if isMenuOpen then
        closeAll()
    else
        openMenu()
    end
end, false)

-- Key mapping for F7 test menu
RegisterKeyMapping('kspike_menu', 'kspike test menu', 'keyboard', 'F7')

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

-- NUI callback: close editor or menu
RegisterNUICallback('close', function(data, cb)
    local wasEditing = isEditing
    closeAll()
    if wasEditing then
        TriggerServerEvent('kspike:report', 'layout', 'editor closed via NUI')
    end
    cb('ok')
end)

-- NUI callback: open edit mode from menu button (a)
RegisterNUICallback('menu_edit', function(data, cb)
    openEditor()
    cb('ok')
end)

-- NUI callback: reset positions to default from menu button (b)
RegisterNUICallback('menu_reset', function(data, cb)
    savedPositions = {}
    DeleteResourceKvp('kspike_layout:pos')

    for key, elem in pairs(registry) do
        local def = defaultPositions[key]
        local defX = def and def.x or elem.x
        local defY = def and def.y or elem.y
        elem.x = defX
        elem.y = defY
        TriggerEvent('kspike:layout:apply', elem.owner, elem.id, defX, defY)
    end

    TriggerServerEvent('kspike:report', 'layout', 'reset positions to defaults')
    cb('ok')
end)

-- NUI callback: rerun S2 theme tests from menu button (c)
RegisterNUICallback('menu_rerun_s2', function(data, cb)
    closeAll()
    TriggerEvent('kspike:s2:rerun')
    cb('ok')
end)

-- Announce presence so already-started owner resources can re-register
TriggerEvent('kspike:layout:hello')
