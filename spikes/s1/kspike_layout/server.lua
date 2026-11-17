-- Server-side reporter for kspike layout events.
RegisterNetEvent('kspike:report', function(tag, msg)
    print(('[kspike] %s %s %s'):format(GetPlayerName(source), tag, tostring(msg):sub(1, 200)))
end)
