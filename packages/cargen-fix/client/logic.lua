-- Pure decision logic for nakara_cargen_fix. No natives: loadable by stock Lua 5.1+ for unit tests.
--
-- Native used by client/main.lua:
--   SET_ALL_VEHICLE_GENERATORS_ACTIVE_IN_AREA(x1, y1, z1, x2, y2, z2, bActive, bNetworked)
-- The 8th argument is `bNetworked`, NOT "instantly" (this native has no such parameter). Passing true
-- publishes the change as network world state and allocates one CNetworkCarGenWorldStateData slot per
-- call from a pool fixed at 100 -- a re-assert loop would then fill the pool by itself. It must stay false.

local L = {}

L.DEFAULT_AREA = { -20000.0, -20000.0, -2000.0, 20000.0, 20000.0, 5000.0 }
L.DEFAULT_REASSERT_MS = 5000
L.MIN_REASSERT_MS = 1000

-- Never networked. Not configurable on purpose.
L.NETWORKED = false

--- Returns a valid area box: `area` when it is 6 numbers with min < max on every axis, else the default.
function L.resolveArea(area)
    if type(area) ~= 'table' then return L.DEFAULT_AREA end
    for i = 1, 6 do
        if type(area[i]) ~= 'number' or area[i] ~= area[i] then return L.DEFAULT_AREA end
    end
    for axis = 1, 3 do
        if area[axis] >= area[axis + 3] then return L.DEFAULT_AREA end
    end
    return { area[1], area[2], area[3], area[4], area[5], area[6] }
end

--- Returns a valid re-assert interval in ms: `ms` when it is a number >= MIN_REASSERT_MS, else the default.
function L.resolveInterval(ms)
    if type(ms) ~= 'number' or ms ~= ms or ms < L.MIN_REASSERT_MS then return L.DEFAULT_REASSERT_MS end
    return math.floor(ms)
end

--- bActive for the native: relief on -> generators inactive; relief off -> vanilla (active).
function L.activeFlag(reliefOn)
    return not reliefOn
end

--- Relief is lifted only when THIS resource stops (onResourceStop fires for every resource).
function L.shouldRestore(stoppedResource, selfResource)
    return stoppedResource == selfResource
end

CargenFixLogic = L
return L
