-- nakara_example -- server side.

exports('getGreeting', function()
    return Config.Greeting
end)

--[[ Example: a rate-limited net event the server accepts from clients.

Before enabling it, declare the event in oss.json:  "netEvents": { "server": ["nakara_example:ping"] }
`fivem-devkit safety` fails when a server net event is registered without being declared. Every server
net event must (1) validate the type of each argument and (2) be rate-limited per player.

local RATE_WINDOW_MS, RATE_MAX = 10000, 5
local hits = {} -- [src] = { start = ms, count = n }

local function allow(src)
    local now = GetGameTimer()
    local h = hits[src]
    if not h or now - h.start >= RATE_WINDOW_MS then
        hits[src] = { start = now, count = 1 }
        return true
    end
    if h.count >= RATE_MAX then return false end
    h.count = h.count + 1
    return true
end

RegisterNetEvent('nakara_example:ping', function(label)
    local src = source
    if type(label) ~= 'string' or #label > 32 then return end -- validate every argument
    if not allow(src) then return end                         -- drop floods silently
    TriggerClientEvent('nakara_example:pong', src, label)
end)

AddEventHandler('playerDropped', function()
    hits[source] = nil
end)
]]
