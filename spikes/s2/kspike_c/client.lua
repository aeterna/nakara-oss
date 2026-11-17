-- [kspike_c] client script

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

print('[kspike_c] started')
