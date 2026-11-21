-- spec/client_spec.lua -- loads the real client script of aeterna_phonecall against the devkit harness: core's
-- self-test events are accepted only from aeterna_core.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local function boot()
    natives.reset({ resource = 'aeterna_phonecall', side = 'client' })
    local invoker = { name = 'aeterna_core' }
    natives.stub('GetInvokingResource', function() return invoker.name end)
    natives.stub('RegisterCommand', function() end)
    natives.stub('RegisterKeyMapping', function() end)
    local reports = {}
    natives.stub_export('aeterna_core', 'reportSelftest', function(runId, name, state, detail)
        reports[#reports + 1] = { runId = runId, name = name, state = state, detail = detail }
        return true
    end)
    resource.load_resource(DIR, 'client', {
        externals = { ['@aeterna_core/import.lua'] = DIR .. '/../core/import.lua' },
    })
    natives.advance(0)
    return { invoker = invoker, reports = reports }
end

describe('aeterna_phonecall client', function()
    it('answers core self-test events only when aeterna_core fired them', function()
        local w = boot()
        w.invoker.name = 'evil_resource'
        natives.fire('aeterna_core:selftest', 'r1', 'aeterna_phonecall.my_number', { kind = 'eye', role = 'A' })
        assert.are.equal(0, #w.reports)
        w.invoker.name = 'aeterna_core'
        natives.fire('aeterna_core:selftest', 'r1', 'aeterna_phonecall.my_number', { kind = 'eye', role = 'A' })
        assert.are.equal(1, #w.reports)
        assert.are.equal('ready', w.reports[1].state)
    end)

    it('a selftestEnd from another resource does not tear down a running test', function()
        local w = boot()
        natives.fire('aeterna_core:selftest', 'r1', 'aeterna_phonecall.sms_ab', { kind = 'eye', role = 'B' })
        w.invoker.name = 'evil_resource'
        natives.fire('aeterna_core:selftestEnd', 'r1', 'aeterna_phonecall.sms_ab')
        natives.advance(1600)
        assert.are.equal(1, #w.reports)
        assert.are.equal('ready', w.reports[1].state)
    end)
end)
