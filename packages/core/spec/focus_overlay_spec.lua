-- focus_overlay_spec.lua -- busted tests for the 0.2 focus overlay: the pure state machine, the client
-- focusPausedOwner export, focusPaused/focusResumed events, and the import.lua pause/resume helper.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local function load_logic(name)
    return assert(loadfile(DIR .. '/shared/logic/' .. name .. '.lua'))()
end

-- Fresh client aeterna_core (import.lua + client/main.lua) without a leftover AeternaCore table.
local function load_client(convars)
    natives.reset({ resource = 'aeterna_core', side = 'client', convars = convars })
    rawset(_G, 'AeternaCore', nil)
    resource.load_resource(DIR, 'client')
end

local function as(who)
    natives.stub('GetInvokingResource', function() return who end)
end

describe('aeterna_core focus overlay (pure state machine)', function()
    local focusLogic
    before_each(function()
        natives.reset()
        focusLogic = load_logic('focus')
    end)

    -- Holder 'aeterna_demo' (token tokH), then an overlay 'aeterna_card' (token tokO), all callbacks recorded.
    local function lock()
        local l = { lost = {}, paused = {}, resumed = {} }
        l.fm = focusLogic.new({
            onLost = function(owner, token, reason) l.lost[#l.lost + 1] = { owner = owner, token = token, reason = reason } end,
            onPaused = function(owner, token) l.paused[#l.paused + 1] = { owner = owner, token = token } end,
            onResumed = function(owner, token) l.resumed[#l.resumed + 1] = { owner = owner, token = token } end,
        })
        l.tokH = l.fm:request('aeterna_demo', { cursor = true })
        l.tokO = l.fm:request('aeterna_card', { overlay = true, cursor = true })
        return l
    end

    it('16a. an overlay pauses the holder: focusPaused, no focusLost, the holder keeps its token', function()
        local l = lock()
        assert.are.equal('aeterna_card', l.fm:owner())
        assert.are.equal('aeterna_demo', l.fm:pausedOwner())
        assert.are.equal(l.tokH, l.fm:pausedToken())
        assert.are.same({ { owner = 'aeterna_demo', token = l.tokH } }, l.paused)
        assert.are.equal(0, #l.lost)
    end)

    it('16b. releasing the overlay resumes the holder with the same token', function()
        local l = lock()
        assert.is_true(l.fm:release(l.tokO))
        assert.are.equal('aeterna_demo', l.fm:owner())
        assert.are.equal(l.tokH, l.fm:token())
        assert.is_nil(l.fm:pausedOwner())
        assert.are.same({ { owner = 'aeterna_demo', token = l.tokH } }, l.resumed)
        assert.are.equal(0, #l.lost)
    end)

    it('16c. a second overlay preempts the first and the holder stays paused', function()
        local l = lock()
        local tokO2 = l.fm:request('aeterna_card2', { overlay = true })
        assert.are.same({ { owner = 'aeterna_card', token = l.tokO, reason = 'preempted' } }, l.lost)
        assert.are.equal('aeterna_card2', l.fm:owner())
        assert.are.equal('aeterna_demo', l.fm:pausedOwner())
        assert.are.equal(1, #l.paused)
        assert.is_false(l.fm:release(l.tokO))
        assert.is_true(l.fm:release(tokO2))
        assert.are.equal(l.tokH, l.fm:token())
    end)

    it('16d. a normal request during an overlay preempts the overlay and the paused holder', function()
        local l = lock()
        local tokN = l.fm:request('aeterna_phonekit', { cursor = true })
        assert.are.same({
            { owner = 'aeterna_card', token = l.tokO, reason = 'preempted' },
            { owner = 'aeterna_demo', token = l.tokH, reason = 'preempted' },
        }, l.lost)
        assert.is_nil(l.fm:pausedOwner())
        assert.is_true(l.fm:release(tokN))
        assert.are.equal(0, #l.resumed)
    end)

    it('16e. an overlay with nobody holding focus acts like a normal request', function()
        local fm = focusLogic.new()
        local tok = fm:request('aeterna_card', { overlay = true })
        assert.are.equal('aeterna_card', fm:owner())
        assert.is_nil(fm:pausedOwner())
        assert.is_true(fm:release(tok))
    end)

    it('16f. the overlay owner stopping resumes the paused holder', function()
        local l = lock()
        l.fm:onResourceStop('aeterna_card', 'aeterna_core')
        assert.are.same({ { owner = 'aeterna_card', token = l.tokO, reason = 'owner_stopped' } }, l.lost)
        assert.are.equal(l.tokH, l.fm:token())
        assert.are.equal(1, #l.resumed)
    end)

    it('16g. the paused holder stopping: nothing resumes when the overlay ends', function()
        local l = lock()
        l.fm:onResourceStop('aeterna_demo', 'aeterna_core')
        assert.are.same({ { owner = 'aeterna_demo', token = l.tokH, reason = 'owner_stopped' } }, l.lost)
        assert.is_nil(l.fm:pausedOwner())
        assert.is_true(l.fm:release(l.tokO))
        assert.is_nil(l.fm:owner())
        assert.are.equal(0, #l.resumed)
    end)

    it('16h. a paused holder releases its own token and nothing resumes later', function()
        local l = lock()
        assert.is_true(l.fm:release(l.tokH))
        assert.is_false(l.fm:release(l.tokH))
        assert.is_nil(l.fm:pausedOwner())
        assert.is_true(l.fm:release(l.tokO))
        assert.are.equal(0, #l.resumed)
    end)

    it('16i. a paused holder requesting normally takes focus back with no focusLost to itself', function()
        local l = lock()
        local tok = l.fm:request('aeterna_demo', { cursor = true })
        assert.are.same({ { owner = 'aeterna_card', token = l.tokO, reason = 'preempted' } }, l.lost)
        assert.are.equal(tok, l.fm:token())
        assert.is_nil(l.fm:pausedOwner())
    end)

    it('16j. core stopping releases the paused holder and the overlay with released_by_core', function()
        local l = lock()
        l.fm:onResourceStop('aeterna_core', 'aeterna_core')
        assert.are.same({
            { owner = 'aeterna_demo', token = l.tokH, reason = 'released_by_core' },
            { owner = 'aeterna_card', token = l.tokO, reason = 'released_by_core' },
        }, l.lost)
        assert.is_nil(l.fm:owner())
        assert.is_nil(l.fm:pausedOwner())
    end)
end)

describe('aeterna_core client (resource integration)', function()
    it('16k. exports: an overlay pauses the holder by event and resumes it on release', function()
        load_client()
        as('aeterna_demo')
        local tokH = exports.aeterna_core:requestFocus({ cursor = true })
        as('aeterna_card')
        local tokO = exports.aeterna_core:requestFocus({ overlay = true, cursor = true })
        assert.are.equal('aeterna_demo', exports.aeterna_core:focusPausedOwner())
        assert.are.same({ n = 2, 'aeterna_demo', tokH }, natives.last_emitted('local', 'aeterna_core:focusPaused').args)
        assert.are.equal(0, #natives.emitted('local', 'aeterna_core:focusLost'))
        assert.is_true(exports.aeterna_core:releaseFocus(tokO))
        assert.are.same({ n = 2, 'aeterna_demo', tokH }, natives.last_emitted('local', 'aeterna_core:focusResumed').args)
        assert.are.equal('aeterna_demo', exports.aeterna_core:focusOwner())
    end)

end)

describe('aeterna_core import.lua helpers (client)', function()
    local function load_import(who)
        natives.reset({ resource = who, side = 'client' })
        rawset(_G, 'AeternaCore', nil)
        assert(loadfile(DIR .. '/import.lua'))()
    end

    it('16s. focusPaused clears the natives; focusResumed re-applies the remembered options', function()
        load_import('aeterna_uikit')
        local focusCalls = natives.spy('SetNuiFocus')
        local keepCalls = natives.spy('SetNuiFocusKeepInput')
        natives.stub_export('aeterna_core', 'requestFocus', function() return 'tok_ui' end)
        natives.stub_export('aeterna_core', 'releaseFocus', function() return true end)
        assert.are.equal('tok_ui', AeternaCore.requestFocus({ cursor = true, keyboard = true }))
        natives.fire('aeterna_core:focusPaused', 'aeterna_phonekit', 'tok_ui')
        assert.are.equal(1, #focusCalls)
        natives.fire('aeterna_core:focusPaused', 'aeterna_uikit', 'tok_ui')
        assert.are.same({ n = 2, false, false }, focusCalls[2])
        assert.are.same({ n = 1, false }, keepCalls[2])
        natives.fire('aeterna_core:focusResumed', 'aeterna_uikit', 'tok_other')
        assert.are.equal(2, #focusCalls)
        natives.fire('aeterna_core:focusResumed', 'aeterna_uikit', 'tok_ui')
        assert.are.same({ n = 2, true, true }, focusCalls[3])
        assert.are.same({ n = 1, false }, keepCalls[3])
    end)
end)
