-- server/selftest.lua -- registers the aeterna_hudkit 0.2 self-tests with aeterna_core and answers the two
-- server-side headless rows. The ped, eye and client mock rows run in client/selftest.lua.

local ST = HudSelftest

local function translate(key)
    if AeternaCore and type(AeternaCore.t) == 'function' then
        return AeternaCore.t(key)
    end
    if Locales and Locales.en and Locales.en[key] then
        return Locales.en[key]
    end
    return key
end

for _, row in ipairs(ST.definitions(translate)) do
    exports.aeterna_core:addSelftest(row.name, row.meta)
end

local SERVER_TESTS = {
    values_mapping = function() return ST.valuesMapping(HudLogic) end,
    compass_math = function() return ST.compassMath(CompassLogic) end,
}

AddEventHandler('aeterna_core:selftest', function(runId, name)
    local test = SERVER_TESTS[ST.shortName(name) or '']
    if not test then return end
    local state, detail = test()
    exports.aeterna_core:reportSelftest(runId, name, state, detail)
end)
