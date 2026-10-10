-- nakara_cargen_fix -- vehicle-generator pool relief (client-only).
--
-- Problem: the network pool CNetworkCarGenWorldStateData has a fixed size of 100. It cannot be raised: it
-- is not in gameconfig.xml <PoolSizes> and it is not on the `increase_pool_size` allow-list. On OneSync
-- maps with more than 100 vehicle generators (ambient parked cars) the pool fills and the client logs
--     CNetworkCarGenWorldStateData Pool Full, Size == 100   (crash_hash net.dll+487A2)
-- about every 15 s while driving, which can escalate into a net.dll crash.
--
-- Fix: disable vehicle generators map-wide, locally. No networked car-gen world state is created, so the
-- pool never fills. Player- and script-spawned vehicles are not generators and are not affected.
--
-- The decision logic lives in client/logic.lua (unit-tested); this file only calls natives.

local L = CargenFixLogic
local area = L.resolveArea(Config and Config.Area)
local reassertMs = L.resolveInterval(Config and Config.ReassertMs)

-- on = true  -> disable generators in the area
-- on = false -> restore vanilla (active) when the resource stops, so a reload does not leave them off
local function applyRelief(on)
    SetAllVehicleGeneratorsActiveInArea(
        area[1], area[2], area[3], area[4], area[5], area[6],
        L.activeFlag(on), -- bActive
        false             -- bNetworked: must never be true (allocates a slot from the fixed 100 pool per call)
    )
end

-- Relief can be paused on THIS client only (exports below), e.g. by an admin test tool that needs a
-- vanilla baseline. Never persisted: every (re)start of the resource begins with relief on.
local reliefOn = true

-- The engine re-enables generators on zone change / respawn, so re-assert periodically.
CreateThread(function()
    applyRelief(true)
    while true do
        Wait(reassertMs)
        if reliefOn then applyRelief(true) end
    end
end)

--- exports.nakara_cargen_fix:setRelief(on) -- client-side, affects only the calling client.
--- false = restore vanilla generators and stop re-asserting · true = disable them again right away.
exports('setRelief', function(on)
    reliefOn = on ~= false
    applyRelief(reliefOn)
    return reliefOn
end)

--- exports.nakara_cargen_fix:isRelief() -> boolean
exports('isRelief', function()
    return reliefOn
end)

AddEventHandler('onResourceStop', function(res)
    if L.shouldRestore(res, GetCurrentResourceName()) then
        applyRelief(false)
    end
end)
