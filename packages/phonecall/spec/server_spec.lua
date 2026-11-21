-- spec/server_spec.lua -- loads the real server scripts of aeterna_phonecall against the devkit harness with a
-- fake aeterna_phonekit and fake voice natives: tiles, a text from A to B, and a call from A to B on Enhanced.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

-- opts = { qbx = true, createResult = n, ringError = 'busy', mayWrite = boolean }
local function boot(gamename, pmaStarted, opts)
    local o = opts or {}
    natives.reset({
        resource = 'aeterna_phonecall', side = 'server',
        convars = { gamename = gamename },
        players = { [1] = 'A', [2] = 'B' },
    })
    local kit = { tiles = {}, shown = {}, rings = {}, live = {}, activity = {}, activityCalls = {}, notified = {},
        badges = {}, updates = {}, stopped = {} }
    natives.stub('GetResourceState', function(name)
        if name == 'pma-voice' and pmaStarted then return 'started' end
        if name == 'qbx_core' and o.qbx then return 'started' end
        if name == 'aeterna_phonekit' or name == 'aeterna_core' then return 'started' end
        return 'missing'
    end)
    natives.stub('GetPlayerIdentifierByType', function(src) return 'license:' .. tostring(src) end)
    natives.stub('IsPlayerAceAllowed', function() return false end)
    local commands = {}
    natives.stub('RegisterCommand', function(name, fn) commands[name] = fn end)
    local voice = { create = 0, add = {}, remove = {}, delete = {} }
    natives.stub('CreateVoiceChannel', function(mode)
        voice.create = voice.create + 1
        voice.mode = mode
        return o.createResult or 3
    end)
    natives.stub('AddPlayerToVoiceChannel', function(ch, src) voice.add[#voice.add + 1] = { ch, src } end)
    natives.stub('SetPlayerMutedInVoiceChannel', function() end)
    natives.stub('RemovePlayerFromVoiceChannel', function(ch, src) voice.remove[#voice.remove + 1] = { ch, src } end)
    natives.stub('DeleteVoiceChannel', function(ch) voice.delete[#voice.delete + 1] = ch end)
    local pmaCalls = {}
    natives.stub_export('pma-voice', 'setPlayerCall', function(src, ch) pmaCalls[#pmaCalls + 1] = { src, ch } end)
    natives.stub_export('qbx_core', 'GetPlayer', function(src)
        return { PlayerData = { citizenid = 'CID' .. tostring(src), source = src } }
    end)
    natives.stub_export('aeterna_phonekit', 'addTile', function(app) kit.tiles[app.id] = app return true end)
    natives.stub_export('aeterna_phonekit', 'showApp', function(src, id, spec)
        kit.shown[#kit.shown + 1] = { src = src, id = id, spec = spec }
        return 's' .. #kit.shown
    end)
    natives.stub_export('aeterna_phonekit', 'updateApp', function(src, screenId, patch)
        kit.updates[#kit.updates + 1] = { src = src, screenId = screenId, patch = patch }
        return true
    end)
    natives.stub_export('aeterna_phonekit', 'badge', function(src, id, n) kit.badges[src] = n return n end)
    natives.stub_export('aeterna_phonekit', 'notifyApp', function(src, id, nopts)
        kit.notified[#kit.notified + 1] = { src = src, id = id, opts = nopts }
        return true
    end)
    natives.stub_export('aeterna_phonekit', 'canCall', function() return true end)
    natives.stub_export('aeterna_phonekit', 'ring', function(src, id, ropts)
        if o.ringError then return nil, o.ringError end
        kit.rings[#kit.rings + 1] = { src = src, id = id, opts = ropts }
        return 'ring_' .. #kit.rings
    end)
    natives.stub_export('aeterna_phonekit', 'stopRing', function(src, ringId)
        kit.stopped[#kit.stopped + 1] = { src, ringId }
        return true
    end)
    natives.stub_export('aeterna_phonekit', 'live', function(src, lopts) kit.live[src] = lopts return true end)
    natives.stub_export('aeterna_phonekit', 'activity', function(src, kind, on)
        kit.activity[src] = on
        kit.activityCalls[#kit.activityCalls + 1] = { src, on }
        return true
    end)
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
    local mayWriteCalls = {}
    natives.stub_export('aeterna_core', 'selftestMayWrite', function(runId, name)
        mayWriteCalls[#mayWriteCalls + 1] = { runId, name }
        return o.mayWrite == true
    end)
    local res = resource.load_resource(DIR, 'server', {
        externals = { ['@aeterna_core/import.lua'] = DIR .. '/../core/import.lua' },
    })
    natives.advance(0)
    return { res = res, commands = commands, kit = kit, voice = voice, pmaCalls = pmaCalls, selftests = selftests,
        reports = reports, mayWriteCalls = mayWriteCalls }
end

local function as(src, name, ...)
    rawset(_G, 'source', src)
    natives.fire(name, ...)
    rawset(_G, 'source', nil)
end

local function openApp(src, id)
    natives.fire('aeterna_phonekit:app', src, { owner = 'aeterna_phonecall', id = id })
end

local function act(src, screenId, action, values)
    natives.fire('aeterna_phonekit:action', src, { owner = 'aeterna_phonecall', screenId = screenId, action = action,
        values = values or {} })
end

local function kvpList(key)
    local raw = natives.get_kvp(key)
    return raw and json.decode(raw) or nil
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

-- A calls B from the Phone app. Returns B's number.
local function callB(w)
    openApp(2, 'phone')
    local numB = w.res.exports.getNumber(2)
    openApp(1, 'phone')
    local _, homeId = lastSpec(w.kit, 1, 'phone')
    act(1, homeId, 'call', { number = numB })
    return numB
end

local function stateTo(src)
    local list = natives.emitted('client', 'aeterna_phonecall:cl:state')
    for i = #list, 1, -1 do
        if list[i].target == src then return list[i].args[1] end
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

    describe('round 2', function()
        local LIC1, LIC2 = 'lic:license:1', 'lic:license:2'

        it('a refused dial shows the reason on the dialer and stores an unknown peer as digits', function()
            local w = boot('gta5enhanced')
            openApp(1, 'phone')
            local _, homeId = lastSpec(w.kit, 1, 'phone')
            act(1, homeId, 'call', { number = '555 99-99' })
            local up = w.kit.updates[#w.kit.updates]
            assert.are.equal(homeId, up.screenId)
            assert.are.equal('Number not available', up.patch.blocks.number.label)
            assert.are.equal('5559999', kvpList('aeterna_phonecall:calls:v1:' .. LIC1)[1].peer)
        end)

        it('a failed ring: the callee gets no ended state and no log entry, the caller gets the same reason', function()
            local w = boot('gta5enhanced', false, { ringError = 'busy' })
            callB(w)
            assert.are.equal('busy', stateTo(1).reason)
            assert.is_nil(stateTo(2))
            assert.is_nil(kvpList('aeterna_phonecall:calls:v1:' .. LIC2))
            assert.are.equal('busy', kvpList('aeterna_phonecall:calls:v1:' .. LIC1)[1].result)
        end)

        it('voice failing on answer: no answered log and no unmatched activity(false)', function()
            local w = boot('gta5enhanced', false, { createResult = 65535 })
            callB(w)
            act(2, 'ring_1', '__answer')
            assert.are.equal('voice_off', stateTo(1).reason)
            assert.are.equal(0, #w.kit.activityCalls)
            assert.are.equal('voice_off', kvpList('aeterna_phonecall:calls:v1:' .. LIC1)[1].result)
            assert.are.equal('voice_off', kvpList('aeterna_phonecall:calls:v1:' .. LIC2)[1].result)
        end)

        it('playerDropped during a call ends it dropped; the channel is deleted and only B is removed', function()
            local w = boot('gta5enhanced')
            callB(w)
            act(2, 'ring_1', '__answer')
            natives.remove_player(1)
            as(1, 'playerDropped', 'quit')
            assert.are.equal('dropped', stateTo(2).reason)
            assert.are.same({ { 3, 2 } }, w.voice.remove)
            assert.are.same({ 3 }, w.voice.delete)
            assert.is_nil(w.res.exports.callState(2))
        end)

        it('onResourceStop of this resource stops rings and deletes channels', function()
            local w = boot('gta5enhanced')
            callB(w)
            act(2, 'ring_1', '__answer')
            natives.add_player(3, 'C')
            natives.add_player(4, 'D')
            local s3 = w.kit.stopped
            openApp(4, 'phone')
            local numD = w.res.exports.getNumber(4)
            openApp(3, 'phone')
            local _, home3 = lastSpec(w.kit, 3, 'phone')
            act(3, home3, 'call', { number = numD })
            assert.are.equal(2, #w.kit.rings)
            natives.fire('onResourceStop', 'aeterna_phonecall')
            assert.are.same({ 4, 'ring_2' }, s3[#s3])
            assert.are.same({ 3 }, w.voice.delete)
        end)

        it('qbx: PlayerLoaded keys the character by citizenid; OnPlayerUnload ends a call dropped', function()
            local w = boot('gta5enhanced', false, { qbx = true })
            natives.fire('QBCore:Server:PlayerLoaded', { PlayerData = { source = 1, citizenid = 'CID1' } })
            natives.fire('QBCore:Server:PlayerLoaded', { PlayerData = { source = 2, citizenid = 'CID2' } })
            callB(w)
            assert.is_truthy(natives.get_kvp('aeterna_phonecall:number:v1:cid:CID2'))
            assert.is_nil(natives.get_kvp('aeterna_phonecall:number:v1:' .. LIC2))
            act(2, 'ring_1', '__answer')
            natives.fire('QBCore:Server:OnPlayerUnload', 2)
            assert.are.equal('dropped', stateTo(1).reason)
        end)

        it('sms_ab: A and B come from selftestStarted; the write waits for mayWrite', function()
            local w = boot('gta5enhanced', false, { mayWrite = true })
            local ctx = { kind = 'eye', side = 'client', a = 1, b = 2, destructive = true }
            natives.fire('aeterna_core:selftestStarted', 'r1', 'aeterna_phonecall.sms_ab', ctx)
            natives.advance(600)
            assert.are.same({ { 'r1', 'aeterna_phonecall.sms_ab' } }, w.mayWriteCalls)
            assert.are.equal('Self-test', kvpList('aeterna_phonecall:sms:v1:' .. LIC2)[1].body)
            assert.are.equal('Self-test', w.kit.notified[1].opts.body)

            local closed = boot('gta5enhanced', false, { mayWrite = false })
            natives.fire('aeterna_core:selftestStarted', 'r2', 'aeterna_phonecall.sms_ab', ctx)
            natives.advance(600)
            assert.is_nil(natives.get_kvp('aeterna_phonecall:sms:v1:' .. LIC2))
            assert.are.equal(0, #closed.kit.notified)
        end)

        it('call_busy and call_ab write no call log; selftestEnd clears the test before its delayed start', function()
            local w = boot('gta5enhanced')
            local ctx = { kind = 'ped', side = 'client', a = 1, b = 2, destructive = false }
            natives.fire('aeterna_core:selftestStarted', 'r1', 'aeterna_phonecall.call_busy', ctx)
            natives.advance(600)
            assert.are.equal('busy', stateTo(1).reason)
            natives.fire('aeterna_core:selftestEnd', 'r1', 'aeterna_phonecall.call_busy')

            natives.fire('aeterna_core:selftestStarted', 'r1', 'aeterna_phonecall.call_ab', ctx)
            natives.advance(600)
            assert.are.equal('ringing', stateTo(2).state)
            natives.fire_net('aeterna_phonecall:sv:hangup', 1)
            natives.fire('aeterna_core:selftestEnd', 'r1', 'aeterna_phonecall.call_ab')
            assert.is_nil(natives.get_kvp('aeterna_phonecall:calls:v1:' .. LIC1))
            assert.is_nil(natives.get_kvp('aeterna_phonecall:calls:v1:' .. LIC2))
            assert.are.equal(0, #w.mayWriteCalls)

            local rings = #w.kit.rings
            natives.fire('aeterna_core:selftestStarted', 'r2', 'aeterna_phonecall.call_ab', ctx)
            natives.fire('aeterna_core:selftestEnd', 'r2', 'aeterna_phonecall.call_ab')
            natives.advance(600)
            assert.are.equal(rings, #w.kit.rings)
        end)

        it('no longer accepts a selftest net event from clients', function()
            boot('gta5enhanced')
            assert.is_false(natives.is_net_event('aeterna_phonecall:sv:selftest'))
        end)
    end)
end)
