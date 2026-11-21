-- server/selftest.lua -- registers the aeterna_radial 0.2 self-tests with aeterna_core, answers the two
-- headless rows and prepares server_recheck. The ped and eye rows report from client/selftest.lua.

local ST = RadialSelftest

for _, row in ipairs(ST.definitions(AeternaCore.t)) do
    exports.aeterna_core:addSelftest(row.name, row.meta)
end

local SERVER_TESTS = {
    registry = function() return ST.registryCheck(RadialLogic) end,
    conditions = function() return ST.conditionsCheck(RadialLogic) end,
}

AddEventHandler('aeterna_core:selftest', function(runId, name)
    local test = SERVER_TESTS[ST.shortName(name) or '']
    if not test then return end
    exports.aeterna_core:reportSelftest(runId, name, test())
end)

-- server_recheck: a vehicle-only server slot for the presser alone, while the client test runs. The client judges
-- the pick; the server never reports for it. An accepted pick takes the slot back, which the client can see.
local RESOURCE = GetCurrentResourceName()
local hooks = RadialServerSelftestHooks
local recheck = {} -- [runId|name] = presser src

AddEventHandler('aeterna_core:selftestStarted', function(runId, name, ctx)
    if ST.shortName(name) ~= 'server_recheck' then return end
    local src = type(ctx) == 'table' and tonumber(ctx.a) or nil
    if not src then return end
    local slot = ST.recheckSlot(AeternaCore.t)
    if not hooks.registry:addSlot(RESOURCE, slot, 'server') then return end
    hooks.setPrivate(slot.id, true)
    recheck[runId .. '|' .. name] = src
    local stored = hooks.registry:getSlot(RESOURCE, slot.id, 'server')
    hooks.sendSlot(src, { op = 'add', owner = RESOURCE, slot = RadialLogic.publicSlot(stored, false) })
end)

AddEventHandler('aeterna_radial:select', function(src, data)
    if type(data) ~= 'table' or data.owner ~= RESOURCE or data.id ~= ST.RECHECK_ID then return end
    hooks.sendSlot(src, { op = 'remove', owner = RESOURCE, id = ST.RECHECK_ID })
end)

AddEventHandler('aeterna_core:selftestEnd', function(runId, name)
    local key = tostring(runId) .. '|' .. tostring(name)
    local src = recheck[key]
    if not src then return end
    recheck[key] = nil
    hooks.registry:removeSlot(RESOURCE, ST.RECHECK_ID, 'server')
    hooks.setPrivate(ST.RECHECK_ID, false)
    hooks.sendSlot(src, { op = 'remove', owner = RESOURCE, id = ST.RECHECK_ID })
end)
