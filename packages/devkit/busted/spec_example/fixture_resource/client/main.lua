CreateThread(function()
    Wait(500)
    TriggerServerEvent('fixture_counter:ping', 'hello')
end)
