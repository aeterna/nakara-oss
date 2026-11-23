-- spec/client_spec.lua -- aeterna_camera's client under the devkit harness: focus events are trusted only from
-- aeterna_core, and a stopped core ends the client halves of the eye tests.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

describe('aeterna_camera client under the harness', function()
    local invoker, nui, commands, reports, phones

    local function boot()
        natives.reset({ resource = 'aeterna_camera', side = 'client', convars = { aeterna_core_log_level = 'error' } })
        invoker, nui, commands, reports, phones = 'aeterna_core', {}, {}, {}, { created = 0, destroyed = 0 }
        natives.stub('GetInvokingResource', function() return invoker end)
        natives.stub('GetResourceState', function(name)
            return (name == 'screenshot-basic' or name == 'aeterna_core') and 'started' or 'missing'
        end)
        natives.stub('SendNUIMessage', function(msg) nui[#nui + 1] = msg end)
        natives.stub('RegisterNUICallback', function() end)
        natives.stub('RegisterCommand', function(name, fn) commands[name] = fn end)
        natives.stub('RegisterKeyMapping', function() end)
        for _, name in ipairs({ 'SetNuiFocus', 'SetNuiFocusKeepInput', 'CellCamActivate', 'CellCamActivateSelfieMode',
            'DisableControlAction', 'DisplayHud', 'DisplayRadar' }) do
            natives.stub(name, function() end)
        end
        natives.stub('CreateMobilePhone', function() phones.created = phones.created + 1 end)
        natives.stub('DestroyMobilePhone', function() phones.destroyed = phones.destroyed + 1 end)
        natives.stub('IsControlJustPressed', function() return false end)
        natives.stub('IsDisabledControlJustPressed', function() return false end)
        natives.stub('GetControlInstructionalButton', function() return 't_E' end)
        natives.stub('GetHashKey', function(s) return #s end) -- the harness returns the name; the client ORs a flag
        natives.stub('IsHudHidden', function() return false end)
        natives.stub('IsRadarHidden', function() return false end)
        natives.stub('GetCurrentServerEndpoint', function() return '127.0.0.1:30120' end)
        natives.stub_export('aeterna_core', 'requestFocus', function() return 'tok1' end)
        natives.stub_export('aeterna_core', 'releaseFocus', function() return true end)
        natives.stub_export('aeterna_core', 'reportSelftest', function(runId, name, ok, detail)
            reports[#reports + 1] = { runId = runId, name = name, ok = ok, detail = detail }
            return true
        end)
        natives.stub_export('aeterna_phonekit', 'activity', function() return true end)
        resource.load_resource(DIR, 'client', {
            externals = { ['@aeterna_core/import.lua'] = DIR .. '/../core/import.lua' },
        })
    end

    local function openViewfinder()
        natives.fire_net('aeterna_camera:cl:viewfinder', 0, { count = 0, cap = 60 })
        assert.are.equal(1, phones.created)
    end

    local function shoots()
        return #natives.emitted('server', 'aeterna_camera:sv:shoot')
    end

    it('ignores focusLost, focusPaused and focusResumed that aeterna_core did not fire', function()
        boot()
        openViewfinder()
        invoker = 'some_other_resource'
        natives.fire('aeterna_core:focusPaused', 'aeterna_camera', 'tok1')
        natives.fire('aeterna_core:focusLost', 'aeterna_camera', 'tok1', 'preempted')
        assert.are.equal(0, phones.destroyed)
        commands['+aeterna_camera_shutter']()
        assert.are.equal(1, shoots())
        -- core pauses: the shutter is ignored; a forged resume does not undo it
        invoker = 'aeterna_core'
        natives.fire('aeterna_core:focusPaused', 'aeterna_camera', 'tok1')
        invoker = 'some_other_resource'
        natives.fire('aeterna_core:focusResumed', 'aeterna_camera', 'tok1')
        natives.advance(5000)
        commands['+aeterna_camera_shutter']()
        assert.are.equal(1, shoots())
        invoker = 'aeterna_core'
        natives.fire('aeterna_core:focusLost', 'aeterna_camera', 'tok1', 'preempted')
        assert.are.equal(1, phones.destroyed)
    end)

    it('a stopped core ends the viewfinder eye test: viewfinder closed, no report afterwards', function()
        boot()
        natives.fire('aeterna_core:selftest', 'r1-x', 'aeterna_camera.viewfinder', { kind = 'eye' })
        natives.advance(100)
        assert.are.equal(1, phones.created)
        invoker = nil
        natives.fire('onResourceStop', 'aeterna_core')
        assert.are.equal(1, phones.destroyed)
        natives.advance(5000)
        assert.are.same({}, reports)
    end)

    it('a stopped core ends shoot_and_view: viewfinder closed, no shot, no report', function()
        boot()
        natives.fire('aeterna_core:selftest', 'r1-x', 'aeterna_camera.shoot_and_view', { kind = 'eye' })
        openViewfinder()
        invoker = nil
        natives.fire('onResourceStop', 'aeterna_core')
        assert.are.equal(1, phones.destroyed)
        natives.advance(20000)
        assert.are.equal(0, shoots())
        assert.are.same({}, reports)
    end)

    it('a viewfinder the player opened stays open when core stops outside a test', function()
        boot()
        openViewfinder()
        invoker = nil
        natives.fire('onResourceStop', 'aeterna_core')
        assert.are.equal(0, phones.destroyed)
    end)
end)
