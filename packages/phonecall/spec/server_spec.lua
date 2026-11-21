-- spec/server_spec.lua -- loads the real server scripts of aeterna_phonecall against the devkit harness with a
-- fake aeterna_phonekit and fake voice natives: tiles, a text from A to B, and a call from A to B on Enhanced.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local function boot(gamename, pmaStarted)
    natives.reset({
        resource = 'aeterna_phonecall', side = 'server',
        convars = { gamename = gamename },
        players = { [1] = 'A', [2] = 'B' },
    })
    local kit = { tiles = {}, shown = {}, rings = {}, live = {}, activity = {}, notified = {}, badges = {} }
    natives.stub('GetResourceState', function(name)
        if name == 'pma-voice' and pmaStarted then return 'started' end
        if name == 'aeterna_phonekit' or name == 'aeterna_core' then return 'started' end
        return 'missing'
    end)
    natives.stub('GetPlayerIdentifierByType', function(src) return 'license:' .. tostring(src) end)
    natives.stub('IsPlayerAceAllowed', function() return false end)
    local commands = {}
    natives.stub('RegisterCommand', function(name, fn) commands[name] = fn end)
    local voice = { create = 0, add = {}, delete = {} }
    natives.stub('CreateVoiceChannel', function(mode) voice.create = voice.create + 1 voice.mode = mode return 3 end)
    natives.stub('AddPlayerToVoiceChannel', function(ch, src) voice.add[#voice.add + 1] = { ch, src } end)
    natives.stub('SetPlayerMutedInVoiceChannel', function() end)
    natives.stub('RemovePlayerFromVoiceChannel', function() end)
    natives.stub('DeleteVoiceChannel', function(ch) voice.delete[#voice.delete + 1] = ch end)
    local pmaCalls = {}
    natives.stub_export('pma-voice', 'setPlayerCall', function(src, ch) pmaCalls[#pmaCalls + 1] = { src, ch } end)
    natives.stub_export('aeterna_phonekit', 'addTile', function(app) kit.tiles[app.id] = app return true end)
    natives.stub_export('aeterna_phonekit', 'showApp', function(src, id, spec)
        kit.shown[#kit.shown + 1] = { src = src, id = id, spec = spec }
        return 's' .. #kit.shown
    end)
    natives.stub_export('aeterna_phonekit', 'updateApp', function() return true end)
    natives.stub_export('aeterna_phonekit', 'badge', function(src, id, n) kit.badges[src] = n return n end)
    natives.stub_export('aeterna_phonekit', 'notifyApp', function(src, id, opts)
        kit.notified[#kit.notified + 1] = { src = src, id = id, opts = opts }
        return true
    end)
    natives.stub_export('aeterna_phonekit', 'canCall', function() return true end)
    natives.stub_export('aeterna_phonekit', 'ring', function(src, id, opts)
        kit.rings[#kit.rings + 1] = { src = src, id = id, opts = opts }
        return 'ring_' .. #kit.rings
    end)
    natives.stub_export('aeterna_phonekit', 'stopRing', function() return true end)
    natives.stub_export('aeterna_phonekit', 'live', function(src, opts) kit.live[src] = opts return true end)
    natives.stub_export('aeterna_phonekit', 'activity', function(src, kind, on) kit.activity[src] = on return true end)
    local selftests = {}
    natives.stub_export('aeterna_core', 'addSelftest', function(name, meta)
        selftests[#selftests + 1] = { name = name, meta = meta }
        return true
    end)
    local reports = {}
    natives.stub_export('aeterna_core', 'reportSelftest', function(runId, name, state, detail, extra)
        reports[name] = { state = state, detail = detail, extra = extra }
        return true
    end)
    local res = resource.load_resource(DIR, 'server', {
        externals = { ['@aeterna_core/import.lua'] = DIR .. '/../core/import.lua' },
    })
    natives.advance(0)
    return { res = res, commands = commands, kit = kit, voice = voice, pmaCalls = pmaCalls, selftests = selftests, reports = reports }
end

local function lastSpec(kit, src, id)
    for i = #kit.shown, 1, -1 do
        local s = kit.shown[i]
        if s.src == src and s.id == id then return s.spec, 's' .. i end
    end
end

local function blockById(spec, id)
    for _, b in ipairs(spec.blocks) do
        if b.id == id then return b end
    end
end

describe('aeterna_phonecall server', function()
    it('registers the two tiles and exactly the spec self-tests in order', function()
        local w = boot('gta5enhanced')
        assert.are.equal('voice', w.kit.tiles.phone.needs)
        assert.are.same({ 'tel' }, w.kit.tiles.phone.handles)
        assert.are.same({ 'sms' }, w.kit.tiles.messages.handles)
        assert.are.equal(10, #w.selftests)
        assert.are.equal('aeterna_phonecall.number_format', w.selftests[1].name)
        assert.are.equal('aeterna_phonecall.call_busy', w.selftests[10].name)
    end)

    it('first open assigns a number; A texts B; B gets a toast and the stored copy', function()
        local w = boot('gta5enhanced')
        natives.fire('aeterna_phonekit:app', 1, { owner = 'aeterna_phonecall', id = 'messages' })
        natives.fire('aeterna_phonekit:app', 2, { owner = 'aeterna_phonecall', id = 'messages' })
        local numA = w.res.exports.getNumber(1)
        local numB = w.res.exports.getNumber(2)
        assert.is_truthy(numA:match('^555%-%d%d%d%d$'))
        assert.are_not.equal(numA, numB)
        assert.are.equal(2, w.res.exports.findByNumber(numB:gsub('%D', '')))

        natives.fire('aeterna_phonekit:action', 1, { owner = 'aeterna_phonecall', screenId = 's1', action = 'compose',
            values = {} })
        local _, composeId = lastSpec(w.kit, 1, 'messages')
        natives.fire('aeterna_phonekit:action', 1, { owner = 'aeterna_phonecall', screenId = composeId,
            action = 'send', values = { number = numB, body = 'hello\nthere' } })
        assert.are.equal(1, #w.kit.notified)
        assert.are.equal(2, w.kit.notified[1].src)
        assert.are.equal(numA, w.kit.notified[1].opts.title)
        local thread, threadId = lastSpec(w.kit, 1, 'messages')
        assert.are.equal('» hellothere', blockById(thread, 'm1').label)
        local stored = json.decode(natives.get_kvp('aeterna_phonecall:sms:v1:lic:license:2'))
        assert.are.equal('in', stored[1].dir)
        assert.is_false(stored[1].read)

        -- a second message at once is refused as too fast, and nothing is stored
        local shownBefore = #w.kit.shown
        natives.fire('aeterna_phonekit:action', 1, { owner = 'aeterna_phonecall', screenId = threadId,
            action = 'send', values = { body = 'again' } })
        assert.are.equal(1, #json.decode(natives.get_kvp('aeterna_phonecall:sms:v1:lic:license:2')))
        assert.are.equal(shownBefore, #w.kit.shown)
        natives.advance(2100)
        natives.fire('aeterna_phonekit:action', 1, { owner = 'aeterna_phonecall', screenId = threadId,
            action = 'send', values = { body = 'again' } })
        assert.are.equal(2, #json.decode(natives.get_kvp('aeterna_phonecall:sms:v1:lic:license:2')))

        -- the admin command moves B to a free number in the format and frees the old one
        w.commands.aeterna_phonecall_setnumber(0, { '2', '555-4321' })
        assert.are.equal('555-4321', w.res.exports.getNumber(2))
        assert.is_nil(natives.get_kvp('aeterna_phonecall:owner:v1:' .. numB:gsub('%D', '')))
        assert.are.equal(2, w.res.exports.findByNumber('5554321'))
    end)

    it('Enhanced: A calls B, B answers from the ring card, one mode-0 channel, A hangs up', function()
        local w = boot('gta5enhanced', true)
        natives.fire('aeterna_phonekit:app', 2, { owner = 'aeterna_phonecall', id = 'phone' })
        local numB = w.res.exports.getNumber(2)
        natives.fire('aeterna_phonekit:app', 1, { owner = 'aeterna_phonecall', id = 'phone' })
        local _, homeId = lastSpec(w.kit, 1, 'phone')
        natives.fire('aeterna_phonekit:action', 1, { owner = 'aeterna_phonecall', screenId = homeId, action = 'call',
            values = { number = numB } })
        assert.are.equal(1, #w.kit.rings)
        assert.are.equal(2, w.kit.rings[1].src)
        assert.are.equal('dialing', w.res.exports.callState(1).state)
        assert.are.equal('ringing', w.res.exports.callState(2).state)

        natives.fire('aeterna_phonekit:action', 2, { owner = 'aeterna_phonecall', screenId = 'ring_1',
            action = '__answer', values = {} })
        assert.are.equal('active', w.res.exports.callState(1).state)
        assert.are.equal(1, w.voice.create)
        assert.are.equal(0, w.voice.mode)
        assert.are.same({ { 3, 1 }, { 3, 2 } }, w.voice.add)
        assert.is_true(w.kit.activity[1])
        assert.are.equal(0, #w.pmaCalls)

        natives.fire_net('aeterna_phonecall:sv:hangup', 1)
        assert.is_nil(w.res.exports.callState(1))
        assert.are.same({ 3 }, w.voice.delete)
        assert.is_false(w.kit.activity[2])
        local ev = natives.last_emitted('client', 'aeterna_phonecall:cl:state')
        assert.are.equal('ended', ev.args[1].state)
        assert.are.equal('hangup', ev.args[1].reason)
        local log = json.decode(natives.get_kvp('aeterna_phonecall:calls:v1:lic:license:1'))
        assert.are.equal('out', log[1].dir)
        assert.are.equal('answered', log[1].result)
    end)

    it('Legacy without pma-voice: the dialer shows the unavailable line and a call ends unavailable', function()
        local w = boot('gta5', false)
        natives.fire('aeterna_phonekit:app', 2, { owner = 'aeterna_phonecall', id = 'phone' })
        local numB = w.res.exports.getNumber(2)
        natives.fire('aeterna_phonekit:app', 1, { owner = 'aeterna_phonecall', id = 'phone' })
        local home, homeId = lastSpec(w.kit, 1, 'phone')
        assert.are.equal('Calls are not available on this server', blockById(home, 'unavailable').label)
        natives.fire('aeterna_phonekit:action', 1, { owner = 'aeterna_phonecall', screenId = homeId, action = 'call',
            values = { number = numB } })
        assert.are.equal(0, #w.kit.rings)
        assert.are.equal(0, #w.pmaCalls)
        local ev = natives.last_emitted('client', 'aeterna_phonecall:cl:state')
        assert.are.equal('unavailable', ev.args[1].reason)
    end)

    it('server self-tests report pass, mock (restored) or skip', function()
        local w = boot('gta5enhanced')
        for _, n in ipairs({ 'number_format', 'number_unique', 'sms_store_cap', 'sms_rate_limit', 'voice_detect',
            'voice_channel' }) do
            natives.fire('aeterna_core:selftest', 'r1', 'aeterna_phonecall.' .. n, { kind = 'headless', side = 'server' })
        end
        assert.are.equal('pass', w.reports['aeterna_phonecall.number_format'].state)
        assert.are.equal('mock', w.reports['aeterna_phonecall.number_unique'].state)
        assert.is_true(w.reports['aeterna_phonecall.number_unique'].extra.restored)
        assert.are.equal('mock', w.reports['aeterna_phonecall.sms_store_cap'].state)
        assert.are.equal('pass', w.reports['aeterna_phonecall.sms_rate_limit'].state)
        assert.are.equal('backend: channels', w.reports['aeterna_phonecall.voice_detect'].detail)
        assert.are.equal('pass', w.reports['aeterna_phonecall.voice_channel'].state)
        for k in pairs(natives.kvp_table()) do
            assert.is_nil(k:find('test:', 1, true), 'left behind ' .. k)
        end

        local legacy = boot('gta5', true)
        natives.fire('aeterna_core:selftest', 'r2', 'aeterna_phonecall.voice_channel', { side = 'server' })
        assert.are.equal('skip', legacy.reports['aeterna_phonecall.voice_channel'].state)
    end)
end)
