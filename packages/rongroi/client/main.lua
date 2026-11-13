-- nakara_rongroi — Rongroi Server Kit
-- SPDX-License-Identifier: MIT

-- Thin client shell: focus, the three server events, NUI forwarding and callbacks. Every screen decision
-- lives in web/ui; this file only moves messages and closes on Escape.

local SCREENS = {
    code = true,
    cases = true,
    case = true,
    settings = true,
    policy = true,
    error = true,
}

local isOpen = false

local function setOpen(on)
    isOpen = on
    SetNuiFocus(on, on)
end

local function close()
    if not isOpen then return end
    setOpen(false)
    SendNUIMessage({ type = 'hide' })
end

local function show(screen, data)
    if not SCREENS[screen] then return end
    setOpen(true)
    SendNUIMessage({ type = 'show', screen = screen, data = data })
end

RegisterNetEvent('nakara_rongroi:showCode', function(data)
    if type(data) ~= 'table' then return end
    show('code', data)
end)

RegisterNetEvent('nakara_rongroi:panel:data', function(data)
    if type(data) ~= 'table' or type(data.screen) ~= 'string' then return end
    show(data.screen, data)
end)

RegisterNetEvent('nakara_rongroi:settings:data', function(data)
    if type(data) ~= 'table' then return end
    show(data.screen == 'policy' and 'policy' or 'settings', data)
end)

RegisterNUICallback('close', function(data, cb)
    close()
    cb(data or {})
end)

local function answer(name)
    RegisterNUICallback(name, function(data, cb)
        cb(data or {})
    end)
end

answer('copy')

-- Keep the shell thin: each screen sends its data straight to the matching server event.
local FORWARDS = {
    { 'openCase', 'nakara_rongroi:panel:openCase' },
    { 'selectCase', 'nakara_rongroi:panel:case' },
    { 'openSettings', 'nakara_rongroi:settings:open' },
    { 'saveSettings', 'nakara_rongroi:settings:save' },
    { 'savePolicy', 'nakara_rongroi:settings:save' },
    { 'rotateKey', 'nakara_rongroi:settings:rotateKey' },
    { 'deleteCase', 'nakara_rongroi:case:delete' },
    { 'deletePlayer', 'nakara_rongroi:player:delete' },
    { 'back', 'nakara_rongroi:panel:open' },
}

local function forward(name, event)
    RegisterNUICallback(name, function(data, cb)
        TriggerServerEvent(event, data or {})
        cb(data or {})
    end)
end

for _, entry in ipairs(FORWARDS) do
    forward(entry[1], entry[2])
end

CreateThread(function()
    while true do
        if isOpen then
            if IsControlJustPressed(0, 322) or IsDisabledControlJustPressed(0, 322) then
                close()
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)
