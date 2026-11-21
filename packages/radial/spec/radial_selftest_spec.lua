-- spec/radial_selftest_spec.lua -- busted tests for the aeterna_radial 0.2 self-tests
-- (docs/specs/aeterna_radial.md § Self-tests (0.2); judging rules in docs/specs/aeterna_core.md § 0.2 additions).

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'
local CORE_DIR = DIR .. '/../core'
local CORE = { ['@aeterna_core/import.lua'] = CORE_DIR .. '/import.lua' }

local function load_logic(name)
    return assert(loadfile(DIR .. '/shared/logic/' .. name .. '.lua'))()
end

local function by_name(defs)
    local out = {}
    for _, d in ipairs(defs) do out[d.name] = d.meta end
    return out
end

-- Locale lookup with {name} replacement, as AeternaCore.t does it.
local function en(key, vars)
    local s = Locales.en[key] or key
    return (s:gsub('{(%w+)}', function(k) return vars and vars[k] ~= nil and tostring(vars[k]) or '{' .. k .. '}' end))
end

describe('aeterna_radial self-tests', function()
    local ST, L

    before_each(function()
        natives.reset()
        L = load_logic('radial')
        ST = load_logic('selftest')
        natives.stub('Locales', {})
        assert(loadfile(DIR .. '/locales/en.lua'))()
        assert(loadfile(DIR .. '/locales/th.lua'))()
    end)

    describe('registration rows', function()
        it('lists the buildable spec rows in spec order', function()
            local names = {}
            for i, d in ipairs(ST.definitions()) do names[i] = d.name end
            assert.are.same({ 'registry', 'conditions', 'open_pick', 'child_ring', 'gamepad' }, names)
        end)

        it('sets kind, side, players and destructive as the spec table says', function()
            local rules = assert(loadfile(CORE_DIR .. '/shared/logic/selftest.lua'))()
            local want = { registry = 'headless', conditions = 'headless', open_pick = 'eye', child_ring = 'eye',
                gamepad = 'eye' }
            local m = by_name(ST.definitions(en))
            for name, kind in pairs(want) do
                local test, err = rules.normalize(m[name])
                assert.is_nil(err, name)
                assert.are.equal(kind, test.kind, name)
                assert.are.equal(kind == 'headless' and 'server' or 'client', test.side, name)
                assert.are.equal(1, test.players, name)
                assert.is_false(test.destructive, name)
                assert.is_nil(test.ask, name)
                assert.is_nil(test.skipWhen, name)
            end
        end)

        it('takes every eye expect from the package locale, in en and th, within core limits', function()
            for _, lang in ipairs({ 'en', 'th' }) do
                local m = by_name(ST.definitions(function(key) return Locales[lang][key] end))
                for _, name in ipairs({ 'open_pick', 'child_ring', 'gamepad' }) do
                    assert.is_string(m[name].expect, lang .. ' ' .. name)
                    assert.is_true(utf8.len(m[name].expect) <= 240, lang .. ' ' .. name)
                end
                assert.is_nil(m.registry.expect)
                assert.is_nil(m.conditions.expect)
            end
        end)

        it('gives the eye tests time for the person to act before the card', function()
            local m = by_name(ST.definitions(en))
            for _, name in ipairs({ 'open_pick', 'child_ring', 'gamepad' }) do
                assert.is_true(m[name].timeout > ST.EYE_WATCH_MS, name)
            end
        end)

        it('maps full names to short names only for its own prefix', function()
            assert.are.equal('gamepad', ST.shortName('aeterna_radial.gamepad'))
            assert.is_nil(ST.shortName('aeterna_hudkit.gamepad'))
            assert.is_nil(ST.shortName('aeterna_radial.server_recheck'))
        end)
    end)

    describe('registry', function()
        it('passes with the shipped RadialLogic', function()
            local state, detail = ST.registryCheck(L)
            assert.are.equal('pass', state)
            assert.is_string(detail)
        end)

        it('fails when a child of a child is accepted', function()
            local real = L.createRegistry
            local broken = setmetatable({ createRegistry = function(cfg)
                local reg = real(cfg)
                local add = reg.addSlot
                reg.addSlot = function(self, owner, slot, side, rg)
                    local ok, err = add(self, owner, slot, side, rg)
                    if err == 'parent: depth' then return true end
                    return ok, err
                end
                return reg
            end }, { __index = L })
            local state, detail = ST.registryCheck(broken)
            assert.are.equal('fail', state)
            assert.truthy(detail:find('child of a child', 1, true))
        end)
    end)

    describe('conditions', function()
        it('passes with the shipped RadialLogic', function()
            assert.are.equal('pass', (ST.conditionsCheck(L)))
        end)

        it('fails when jobs pass without qbx_core', function()
            local broken = setmetatable({ evalCondition = function(cond, ctx)
                if cond and cond.jobs then return true end
                return L.evalCondition(cond, ctx)
            end }, { __index = L })
            local state, detail = ST.conditionsCheck(broken)
            assert.are.equal('fail', state)
            assert.truthy(detail:find('jobs', 1, true))
        end)
    end)

    describe('test slots', function()
        it('open_pick and gamepad use six root slots Test 1 … Test 6 in order', function()
            for _, name in ipairs({ 'open_pick', 'gamepad' }) do
                local slots = ST.testSlots(name, en)
                assert.are.equal(6, #slots)
                for i, s in ipairs(slots) do
                    assert.are.equal('selftest_' .. i, s.id)
                    assert.are.equal('Test ' .. i, s.label)
                    assert.are.equal(i, s.order)
                    assert.is_nil(s.parent)
                    assert.is_true(L.validateSlot(s, 'client'))
                end
            end
        end)

        it('child_ring uses one group with three children', function()
            local slots = ST.testSlots('child_ring', en)
            assert.are.equal(4, #slots)
            assert.are.equal('selftest_group', slots[1].id)
            for i = 2, 4 do
                assert.are.equal('selftest_group', slots[i].parent)
                assert.is_true(L.validateSlot(slots[i], 'client'))
            end
        end)

        it('Thai labels stay within the 20-character slot label limit', function()
            for _, name in ipairs({ 'open_pick', 'child_ring' }) do
                for _, s in ipairs(ST.testSlots(name, function(key, vars)
                    local str = Locales.th[key] or key
                    return (str:gsub('{(%w+)}', function(k) return tostring(vars and vars[k]) end))
                end)) do
                    assert.is_true(L.validateSlot(s, 'client'), s.id)
                end
            end
        end)

        it('says which label was picked', function()
            assert.are.equal('picked Test 3', ST.pickedLine(en, 'Test 3'))
        end)
    end)

    describe('eye watch (when to show the card)', function()
        it('open_pick is ready once a test slot was picked', function()
            local w = ST.newEyeWatch('open_pick')
            assert.is_false(w.observe({ type = 'state', open = true }))
            assert.is_false(w.observe({ type = 'pick', id = 'other' }))
            assert.is_true(w.observe({ type = 'pick', id = 'selftest_3' }))
        end)

        it('child_ring is ready once the child ring opened and back returned with the group highlighted', function()
            local w = ST.newEyeWatch('child_ring')
            assert.is_false(w.observe({ type = 'state', open = true }))
            assert.is_false(w.observe({ type = 'state', open = true, hoverId = 'selftest_group' }))
            assert.is_false(w.observe({ type = 'state', open = true, parentId = 'selftest_group' }))
            assert.is_true(w.observe({ type = 'state', open = true, hoverId = 'selftest_group' }))
        end)

        it('gamepad is ready once the ring closed after being open', function()
            local w = ST.newEyeWatch('gamepad')
            assert.is_false(w.observe({ type = 'state', open = false }))
            assert.is_false(w.observe({ type = 'state', open = true }))
            assert.is_true(w.observe({ type = 'state', open = false }))
        end)
    end)

    describe('server wrapper', function()
        it('registers the rows on start and answers the two headless rows', function()
            natives.reset({ resource = 'aeterna_radial', side = 'server', invoker = 'aeterna_radial' })
            natives.stub('GetResourceState', function() return 'missing' end)
            local added, reports = {}, {}
            natives.stub_export('aeterna_core', 'addSelftest', function(name, meta)
                added[#added + 1] = { name = name, meta = meta }
                return true
            end)
            natives.stub_export('aeterna_core', 'reportSelftest', function(runId, name, ok, detail)
                reports[#reports + 1] = { name = name, ok = ok, detail = detail }
                return true
            end)
            resource.load_resource(DIR, 'server', { externals = CORE })
            natives.advance(0)
            assert.are.equal(5, #added)
            assert.are.equal('registry', added[1].name)
            assert.are.equal('gamepad', added[5].name)
            assert.is_string(added[3].meta.expect)

            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_radial.registry', { kind = 'headless' })
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_radial.conditions', { kind = 'headless' })
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_notify.registry', { kind = 'headless' })
            natives.advance(0)
            assert.are.equal(2, #reports)
            assert.are.equal('pass', reports[1].ok)
            assert.are.equal('pass', reports[2].ok)
        end)
    end)

    describe('client wrapper', function()
        local function loadClient()
            natives.reset({ resource = 'aeterna_radial', side = 'client', invoker = 'aeterna_radial' })
            local env = { commands = {}, callbacks = {}, reports = {} }
            env.nui = natives.spy('SendNUIMessage')
            natives.spy('RegisterCommand', function(name, fn) env.commands[name] = fn end)
            natives.spy('RegisterNUICallback', function(name, fn) env.callbacks[name] = fn end)
            natives.spy('RegisterKeyMapping')
            natives.spy('SetNuiFocus')
            natives.spy('SetNuiFocusKeepInput')
            natives.spy('DisableControlAction')
            natives.stub('GetDisabledControlNormal', function() return 0 end)
            natives.stub('IsDisabledControlJustReleased', function() return false end)
            natives.stub('IsUsingKeyboard', function() return true end)
            natives.stub('GetVehiclePedIsIn', function() return 0 end)
            natives.stub('GetResourceState', function() return 'missing' end)
            natives.stub('IsEntityDead', function() return false end)
            natives.stub('IsPedRagdoll', function() return false end)
            env.feed = natives.spy('AddTextComponentSubstringPlayerName')
            natives.spy('BeginTextCommandThefeedPost')
            natives.spy('EndTextCommandThefeedPostTicker')
            natives.stub_export('aeterna_core', 'requestFocus', function() return 'tok_1' end)
            natives.stub_export('aeterna_core', 'releaseFocus', function() return true end)
            natives.stub_export('aeterna_core', 'themeHref', function() return '' end)
            natives.stub_export('aeterna_core', 'themePreset', function() return 'asphalt' end)
            natives.stub_export('aeterna_core', 'reportSelftest', function(runId, name, ok, detail)
                env.reports[#env.reports + 1] = { name = name, ok = ok, detail = detail }
                return true
            end)
            env.api = resource.load_resource(DIR, 'client', { externals = CORE }).exports
            natives.fire_net('aeterna_radial:cl:slots', 1, { slots = {} })
            natives.advance(0)
            return env
        end

        local function lastOfType(env, t)
            local found
            for _, call in ipairs(env.nui) do
                if type(call[1]) == 'table' and call[1].type == t then found = call[1] end
            end
            return found
        end

        it('open_pick opens a ring of six, reports ready after the pick with a picked line, and cleans up', function()
            local env = loadClient()
            natives.fire('aeterna_core:selftest', 'r2-abcd', 'aeterna_radial.open_pick', { kind = 'eye', role = 'A' })
            natives.advance(200)
            assert.is_true(env.api.isOpen())
            assert.are.equal(6, #lastOfType(env, 'ring:open').slots)
            assert.are.equal(0, #env.reports)

            env.callbacks.pick({ index = 3 }, function() end)
            natives.advance(500)
            assert.is_false(env.api.isOpen())
            assert.are.equal('picked Test 3', env.feed[#env.feed][1])
            assert.are.equal(1, #env.reports)
            assert.are.equal('ready', env.reports[1].ok)

            natives.fire('aeterna_core:selftestEnd', 'r2-abcd', 'aeterna_radial.open_pick')
            natives.advance(0)
            env.commands['aeterna_radial_open']()
            assert.are.equal(0, #lastOfType(env, 'ring:open').slots)
        end)

        it('child_ring reports ready after the child ring and back', function()
            local env = loadClient()
            natives.fire('aeterna_core:selftest', 'r3-abcd', 'aeterna_radial.child_ring', { kind = 'eye', role = 'A' })
            natives.advance(200)
            env.callbacks.pick({ index = 1 }, function() end)
            natives.advance(200)
            assert.are.equal(3, #lastOfType(env, 'ring:child').slots)
            env.callbacks.back({}, function() end)
            natives.advance(500)
            assert.are.equal(1, #env.reports)
            assert.are.equal('ready', env.reports[1].ok)
            natives.fire('aeterna_core:selftestEnd', 'r3-abcd', 'aeterna_radial.child_ring')
            natives.advance(0)
            assert.is_false(env.api.isOpen())
        end)

        it('reports fail when the ring cannot open', function()
            local env = loadClient()
            natives.stub('IsEntityDead', function() return true end)
            natives.fire('aeterna_core:selftest', 'r4-abcd', 'aeterna_radial.gamepad', { kind = 'eye', role = 'A' })
            natives.advance(500)
            assert.are.equal(1, #env.reports)
            assert.are.equal('fail', env.reports[1].ok)
        end)
    end)
end)
