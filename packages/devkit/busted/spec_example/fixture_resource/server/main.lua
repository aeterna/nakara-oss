local counts, windowStart = {}, {}

RegisterNetEvent('fixture_counter:ping', function(label)
    local src = source
    if type(label) ~= 'string' then return end
    local now = GetGameTimer()
    if not windowStart[src] or now - windowStart[src] >= Config.WindowMs then
        windowStart[src], counts[src] = now, 0
    end
    if CounterLogic.overLimit(counts[src], GetConvarInt('fixture_counter_max', Config.MaxPings)) then
        TriggerClientEvent('fixture_counter:limited', src)
        return
    end
    counts[src] = counts[src] + 1
    TriggerClientEvent('fixture_counter:pong', src, label, counts[src], GetPlayerName(src))
end)

exports('getCount', function(src) return counts[src] or 0 end)

CreateThread(function()
    while true do
        Wait(1000)
        TriggerEvent('fixture_counter:tick', json.encode({ players = #GetPlayers() }))
    end
end)
