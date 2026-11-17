-- [kspike_c] server script

RegisterNetEvent('kspike:report', function(tag, msg)
    print(('[kspike] %s %s %s'):format(GetPlayerName(source) or 'console', tag, tostring(msg):sub(1, 400)))
end)
