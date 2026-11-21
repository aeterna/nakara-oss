-- server/selftest.lua -- registers the aeterna_radial 0.2 self-tests with aeterna_core and answers the two
-- headless rows. The eye rows run in client/selftest.lua.

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
