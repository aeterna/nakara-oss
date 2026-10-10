-- harness_spec.lua -- example spec for the devkit busted harness.
-- Loads fixture_resource/ through its fxmanifest.lua and drives it with the stubbed natives.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

-- Resolve the fixture next to this spec, whatever directory busted was started from.
local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local FIXTURE = HERE .. '/fixture_resource'

describe('devkit busted harness', function()
    before_each(function()
        natives.reset({ players = { [1] = 'Alice', [2] = 'Bob' } })
    end)

    describe('manifest parser', function()
        it('reads scalar and list keys and ignores commented-out entries', function()
            local m = resource.read_manifest(FIXTURE)
            assert.are.equal('fixture_counter', m.name)
            assert.are.equal('yes', m.lua54)
            assert.are.same({ 'shared/config.lua', 'shared/logic.lua' }, m.shared)
            assert.are.same({ 'server/main.lua' }, m.server)
            assert.are.same({ 'client/main.lua' }, m.client)
        end)

        it('handles double quotes, multi-line lists and long-bracket comments', function()
            local m = resource.parse_manifest([==[
                fx_version "cerulean"
                --[=[ server_script 'nope.lua' ]=]
                client_scripts {
                    "a.lua", -- first
                    'b.lua',
                }
                dependency 'ox_lib'
            ]==])
            assert.are.equal('cerulean', m.fx_version)
            assert.are.same({ 'a.lua', 'b.lua' }, m.client)
            assert.are.same({}, m.server)
            assert.are.same({ 'ox_lib' }, m.dependencies)
        end)
    end)

    describe('server side', function()
        local res
        before_each(function()
            res = resource.load_resource(FIXTURE, 'server')
        end)

        it('loads shared scripts before server scripts, in manifest order', function()
            assert.are.same({ 'shared/config.lua', 'shared/logic.lua', 'server/main.lua' }, res.loaded)
            assert.are.equal('fixture_counter', GetCurrentResourceName())
            assert.is_true(IsDuplicityVersion())
        end)

        it('only reaches handlers of net-registered events, with source set', function()
            assert.is_true(natives.is_net_event('fixture_counter:ping'))
            assert.are.equal(1, natives.fire_net('fixture_counter:ping', 2, 'hi'))
            assert.are.equal(0, natives.fire_net('fixture_counter:not_registered', 2))

            local pong = natives.last_emitted('client', 'fixture_counter:pong')
            assert.are.equal(2, pong.target)
            assert.are.same({ n = 3, 'hi', 1, 'Bob' }, pong.args)
        end)

        it('rate-limits per window using the controllable clock and convars', function()
            natives.set_convar('fixture_counter_max', 2)
            for _ = 1, 3 do natives.fire_net('fixture_counter:ping', 1, 'x') end
            assert.are.equal(2, #natives.emitted('client', 'fixture_counter:pong'))
            assert.are.equal(1, #natives.emitted('client', 'fixture_counter:limited'))

            natives.advance(10000) -- next window
            natives.fire_net('fixture_counter:ping', 1, 'x')
            assert.are.equal(3, #natives.emitted('client', 'fixture_counter:pong'))
        end)

        it('rejects bad argument types', function()
            natives.fire_net('fixture_counter:ping', 1, { not_a = 'string' })
            assert.are.equal(0, #natives.emitted('client'))
        end)

        it('registers exports callable with the colon syntax', function()
            natives.fire_net('fixture_counter:ping', 1, 'x')
            assert.are.equal(1, exports.fixture_counter:getCount(1))
            assert.are.equal(0, exports.fixture_counter:getCount(2))
            assert.has_error(function() exports.fixture_counter:missing() end)
        end)

        it('runs threads on the fake clock', function()
            assert.are.equal(0, #natives.emitted('local', 'fixture_counter:tick'))
            natives.advance(0)    -- thread starts, hits Wait(1000)
            natives.advance(3000) -- wakes at 1000, 2000, 3000
            local ticks = natives.emitted('local', 'fixture_counter:tick')
            assert.are.equal(3, #ticks)
            assert.are.equal(3000, GetGameTimer())
            assert.are.same({ players = 2 }, json.decode(ticks[3].args[1]))
        end)
    end)

    describe('client side', function()
        it('captures TriggerServerEvent after Wait()', function()
            resource.load_resource(FIXTURE, 'client')
            assert.is_false(IsDuplicityVersion())
            natives.advance(499)
            assert.are.equal(0, #natives.emitted('server'))
            natives.advance(1)
            assert.are.same({ n = 1, 'hello' }, natives.last_emitted('server', 'fixture_counter:ping').args)
            assert.are.equal(0, natives.thread_count())
        end)
    end)

    describe('natives', function()
        it('spies on arbitrary natives', function()
            local calls = natives.spy('SetSomething', function(a) return a * 2 end)
            assert.are.equal(4, SetSomething(2))
            assert.are.equal(1, #calls)
            assert.are.equal(2, calls[1][1])
        end)

        it('reset() removes spied natives and globals defined by loaded scripts', function()
            natives.spy('SetSomething')
            resource.load_resource(FIXTURE, 'server')
            assert.is_not_nil(rawget(_G, 'Config'))
            natives.reset()
            assert.is_nil(rawget(_G, 'SetSomething'))
            assert.is_nil(rawget(_G, 'Config'))
            assert.is_nil(rawget(_G, 'CounterLogic'))
        end)

        it('SetTimeout runs once when due and ClearTimeout cancels', function()
            local hits = 0
            SetTimeout(100, function() hits = hits + 1 end)
            local id = SetTimeout(100, function() hits = hits + 10 end)
            ClearTimeout(id)
            natives.advance(99)
            assert.are.equal(0, hits)
            natives.advance(1)
            assert.are.equal(1, hits)
        end)

        it('backs convars with a table and records writes', function()
            natives.set_convar('my_int', '42')
            assert.are.equal(42, GetConvarInt('my_int', 0))
            assert.are.equal('fallback', GetConvar('missing', 'fallback'))
            SetConvar('my_flag', 'true')
            assert.is_true(GetConvarBool('my_flag', false))
            assert.are.same({ { name = 'my_flag', value = 'true', kind = 'SetConvar' } }, natives.convar_writes())
        end)

        it('provides vector3 math', function()
            local d = vector3(3.0, 4.0, 0.0) - vector3(0.0, 0.0, 0.0)
            assert.are.equal(5.0, natives.length(d))
            assert.are.equal(vector3(2, 2, 2), vector3(1, 1, 1) + 1)
        end)

        it('round-trips json', function()
            assert.are.same({ a = { 1, 2 } }, json.decode(json.encode({ a = { 1, 2 } })))
        end)
    end)
end)
