-- example_spec.lua -- starting point for a package spec. Run from the repo root:
--   busted --config-file=.busted <path to this folder>

local natives = require('helpers.natives')
local resource = require('helpers.resource')

-- The package folder, wherever this template was copied to.
local DIR = (debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.') .. '/..'

describe('nakara_example', function()
    before_each(function()
        natives.reset()
    end)

    it('server: loads config before server scripts and exposes getGreeting', function()
        local res = resource.load_resource(DIR, 'server')
        assert.are.same({ 'config.lua', 'server/main.lua' }, res.loaded)
        assert.are.equal('hello', exports.nakara_example:getGreeting())
    end)

    it('server: registers no net events (oss.json declares none)', function()
        resource.load_resource(DIR, 'server')
        assert.is_false(natives.is_net_event('nakara_example:ping'))
    end)

    it('client: loads and handles its own start event only', function()
        local res = resource.load_resource(DIR, 'client')
        assert.are.same({ 'config.lua', 'client/main.lua' }, res.loaded)
        assert.are.equal(1, natives.handler_count('onClientResourceStart'))
        natives.fire('onClientResourceStart', 'nakara_example')
        natives.fire('onClientResourceStart', 'another_resource')
    end)
end)
