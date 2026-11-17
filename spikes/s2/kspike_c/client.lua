-- spikes/s2/kspike_c/client.lua
-- Spike consumer resource client script

RegisterNUICallback('ready', function(data, cb)
    print('[kspike_c] NUI page ready')
    SetTimeout(2000, function()
        SendNUIMessage({
            type = 'theme',
            href = 'nui://kspike_theme/theme.css'
        })
    end)
    cb(data or {})
end)

RegisterNUICallback('result', function(data, cb)
    TriggerServerEvent('kspike:report', 'kspike_c', json.encode(data))
    cb(data or {})
end)

AddEventHandler('kspike:s2:rerun', function()
    SendNUIMessage({
        type = 'rerun',
        href = 'nui://kspike_theme/theme.css'
    })
end)

print('[kspike_c] started')
