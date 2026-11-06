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
    gate = true,
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
    show('settings', data)
end)

RegisterNUICallback('close', function(data, cb)
    close()
    cb(data or {})
end)

local function forward(name)
    RegisterNUICallback(name, function(data, cb)
        cb(data or {})
    end)
end

for _, name in ipairs({ 'copy', 'openCase', 'selectCase', 'saveSettings', 'savePolicy', 'deleteCase' }) do
    forward(name)
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
