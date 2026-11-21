-- spec/hudkit_02_spec.lua -- busted tests for the aeterna_hudkit 0.2 additions (docs/specs/aeterna_hudkit.md § 0.2).

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local function load_logic(name)
    return assert(loadfile(DIR .. '/shared/logic/' .. name .. '.lua'))()
end

local function near(expected, actual, eps)
    assert.is_true(math.abs(expected - actual) <= (eps or 1e-9),
        ('expected %s, got %s'):format(tostring(expected), tostring(actual)))
end

-- Config as config.lua ships it, so a test can change one key and skip config.lua.
local function shipped_config(overrides)
    local cfg = {
        tick = 200,
        low = 20,
        needs = { 'hunger', 'thirst', 'stress' },
        speedUnit = 'kmh',
        minimap = { mode = 'always' },
        hideBaseBars = true,
        barStyle = 'bar',
        compass = { enabled = true, span = 120 },
        voice = { enabled = true },
        seatbelt = { enabled = true },
    }
    for k, v in pairs(overrides or {}) do cfg[k] = v end
    return cfg
end

-- Loads the client side with stubs for the natives hudkit 0.2 reads. Returns a context table.
local function load_client(opts)
    opts = opts or {}
    natives.reset({ side = 'client', resource = 'aeterna_hudkit', invoker = opts.invoker })
    natives.spy('RegisterCommand')
    natives.spy('RegisterKeyMapping')
    natives.spy('ExecuteCommand')
    local ctx = { callbacks = {}, bagHandlers = {}, removedBagHandlers = {} }
    natives.spy('RegisterNUICallback', function(name, fn) ctx.callbacks[name] = fn end)
    ctx.ui = natives.spy('SendNUIMessage')

    ctx.resourceState = opts.voiceState or 'missing'
    natives.stub('GetResourceState', function(name)
        if name == 'pma-voice' then return ctx.resourceState end
        return 'started'
    end)
    local cookie = 0
    natives.stub('AddStateBagChangeHandler', function(key, bag, fn)
        cookie = cookie + 1
        ctx.bagHandlers[cookie] = { key = key, bag = bag, fn = fn }
        return cookie
    end)
    natives.stub('RemoveStateBagChangeHandler', function(c)
        ctx.removedBagHandlers[#ctx.removedBagHandlers + 1] = c
        ctx.bagHandlers[c] = nil
    end)
    natives.stub('GetPlayerServerId', function() return 7 end)
    ctx.playerState = opts.playerState or {}
    natives.stub('LocalPlayer', { state = ctx.playerState })
    ctx.talking = false
    natives.stub('NetworkIsPlayerTalking', function() return ctx.talking end)
    ctx.inVehicle = opts.inVehicle == true
    natives.stub('IsPedInAnyVehicle', function() return ctx.inVehicle end)
    natives.stub('GetVehiclePedIsIn', function() return ctx.inVehicle and 50 or 0 end)

    local loadOpts = {}
    if opts.config then
        natives.stub('Config', opts.config)
        loadOpts.skip = { ['config.lua'] = true }
    end
    ctx.res = resource.load_resource(DIR, 'client', loadOpts)

    function ctx.messages(msgType)
        local out = {}
        for _, call in ipairs(ctx.ui) do
            local msg = call[1]
            if type(msg) == 'table' and msg.type == msgType then out[#out + 1] = msg end
        end
        return out
    end

    function ctx.last(msgType)
        local list = ctx.messages(msgType)
        return list[#list]
    end

    function ctx.layoutCalls(eventName, id)
        local out = {}
        for _, e in ipairs(natives.emitted('local', eventName)) do
            local a = e.args[1]
            local eid = type(a) == 'table' and a.id or a
            if eid == id then out[#out + 1] = e end
        end
        return out
    end

    function ctx.fireBag(key, value)
        for _, h in pairs(ctx.bagHandlers) do
            if h.key == key then h.fn('player:7', key, value, 0, false) end
        end
    end

    return ctx
end

describe('aeterna_hudkit 0.2', function()
    describe('1. compass (shared/logic/compass.lua)', function()
        local C
        before_each(function()
            natives.reset()
            C = load_logic('compass')
        end)

        it('maps heading to tape offset for 0, 359, 360 and the wrap', function()
            -- Heading 0: north sits on the centre mark.
            near(0, C.offset(0, 0, 120))
            near(15 / 120, C.offset(15, 0, 120))
            near(-15 / 120, C.offset(345, 0, 120))

            -- Heading 359: north is 1 degree right of the centre.
            near(1 / 120, C.offset(0, 359, 120))
            near(-14 / 120, C.offset(345, 359, 120))

            -- Heading 360 is the same as 0.
            near(C.offset(0, 0, 120), C.offset(0, 360, 120))
            near(C.offset(90, 0, 120), C.offset(90, 360, 120))

            -- Wrap: heading 10 sees 350 on its left, heading 350 sees 10 on its right.
            near(-20 / 120, C.offset(350, 10, 120))
            near(20 / 120, C.offset(10, 350, 120))
        end)

        it('normalises headings to whole degrees 0-359 with 0 = N growing clockwise', function()
            assert.are.equal(0, C.normalize(0))
            assert.are.equal(0, C.normalize(360))
            assert.are.equal(359, C.normalize(359))
            assert.are.equal(0, C.normalize(359.6))
            assert.are.equal(350, C.normalize(-10))
            assert.are.equal(0, C.normalize(nil))

            -- GetGameplayCamRot z grows counter-clockwise: z = 90 faces west (270), z = -90 faces east (90).
            assert.are.equal(0, C.fromCamRot(0))
            assert.are.equal(270, C.fromCamRot(90))
            assert.are.equal(90, C.fromCamRot(-90))
            assert.are.equal(180, C.fromCamRot(180))
        end)

        it('labels the eight directions on the tape', function()
            local expected = { [0] = 'N', [45] = 'NE', [90] = 'E', [135] = 'SE',
                [180] = 'S', [225] = 'SW', [270] = 'W', [315] = 'NW' }
            for deg, code in pairs(expected) do
                assert.are.equal(code, C.label(deg))
                assert.are.equal('hudkit.dir.' .. code:lower(), C.labelKey(deg))
            end
            assert.is_nil(C.label(15))
            assert.is_nil(C.labelKey(30))

            -- Facing north with span 180: W at the left edge, N centre, E at the right edge.
            local ticks = C.visibleTicks(0, 180)
            local seen = {}
            for i, t in ipairs(ticks) do
                assert.is_true(t.offset >= -0.5 and t.offset <= 0.5)
                if i > 1 then assert.is_true(t.offset > ticks[i - 1].offset) end
                assert.are.equal(0, t.deg % 15)
                if t.label then seen[t.label] = t.offset end
            end
            near(-0.5, seen.W)
            near(-0.25, seen.NW)
            near(0, seen.N)
            near(0.25, seen.NE)
            near(0.5, seen.E)
            assert.are.equal(13, #ticks)

            -- Facing 350 the ticks wrap through 0 and keep degrees in 0-359.
            local wrapped = C.visibleTicks(350, 60)
            local degs = {}
            for _, t in ipairs(wrapped) do degs[#degs + 1] = t.deg end
            assert.are.same({ 330, 345, 0, 15 }, degs)
            near(-20 / 60, wrapped[1].offset)
            near(10 / 60, wrapped[3].offset)
            assert.are.equal('N', wrapped[3].label)
        end)

        it('clamps span outside 60-180', function()
            assert.are.equal(60, C.clampSpan(30))
            assert.are.equal(60, C.clampSpan(60))
            assert.are.equal(120, C.clampSpan(120))
            assert.are.equal(180, C.clampSpan(180))
            assert.are.equal(180, C.clampSpan(500))
            assert.are.equal(120, C.clampSpan(nil))
            assert.are.equal(120, C.clampSpan('wide'))
            -- A clamped span is what visibleTicks uses.
            assert.are.equal(#C.visibleTicks(0, 180), #C.visibleTicks(0, 999))
        end)
    end)

    describe('2. ring geometry (shared/logic/hud.lua)', function()
        local H
        before_each(function()
            natives.reset()
            H = assert(loadfile(DIR .. '/shared/logic/hud.lua'))()
        end)

        it('maps 0, 50, 100 and out-of-range values to the right arc', function()
            near(0, H.ringArc(0))
            near(0.5, H.ringArc(50))
            near(1, H.ringArc(100))
            near(0, H.ringArc(-10))
            near(1, H.ringArc(150))
            near(0, H.ringArc(nil))
            near(0, H.ringArc('x'))

            -- A circumference of 100 makes the dash length the percentage.
            local d0 = H.ringDash(0, 100)
            near(0, d0.length)
            near(100, d0.offset)
            local d50 = H.ringDash(50, 100)
            near(50, d50.length)
            near(50, d50.offset)
            local d100 = H.ringDash(100, 100)
            near(100, d100.length)
            near(0, d100.offset)
            local over = H.ringDash(250, 100)
            near(100, over.length)
            near(0, over.offset)

            local c = 2 * math.pi * 16
            near(c / 4, H.ringDash(25, c).length, 1e-9)
        end)

        it('turns --bad at Config.low; health keeps --accent', function()
            assert.are.equal('bad', H.barTone('armour', 20, 20))
            assert.are.equal('bad', H.barTone('hunger', 0, 20))
            assert.are.equal('normal', H.barTone('armour', 21, 20))
            assert.are.equal('normal', H.barTone('fuel', 80, 20))
            assert.are.equal('bad', H.barTone('fuel', 10, 20))
            assert.are.equal('accent', H.barTone('health', 5, 20))
            assert.are.equal('accent', H.barTone('health', 100, 20))
            -- The threshold defaults to 20 when it is missing.
            assert.are.equal('bad', H.barTone('stress', 20, nil))
        end)
    end)

    describe('3. voice detection (shared/logic/voice.lua and client)', function()
        it('detector: started registers, stopped removes, disabled never registers', function()
            natives.reset()
            local V = load_logic('voice')
            assert.are.equal('pma-voice', V.RESOURCE)

            local d = V.createDetector({ enabled = true })
            assert.is_false(d.isActive())
            assert.is_nil(d.update('stopped'))
            assert.are.equal('register', d.update('started'))
            assert.is_true(d.isActive())
            assert.is_nil(d.update('started'))
            assert.are.equal('remove', d.update('stopping'))
            assert.is_false(d.isActive())
            assert.is_nil(d.update('missing'))

            local off = V.createDetector({ enabled = false })
            assert.is_nil(off.update('started'))
            assert.is_nil(off.update('stopped'))
            assert.is_false(off.isActive())
        end)

        it('client: started registers the voice element and stopped removes it', function()
            local ctx = load_client({ voiceState = 'started', playerState = {
                proximity = { index = 2, distance = 7.0, mode = 'Normal' }, radioChannel = 0 } })

            local adds = ctx.layoutCalls('aeterna_layout:add', 'voice')
            assert.are.equal(1, #adds)
            local def = adds[1].args[1]
            assert.are.equal('aeterna_hudkit', def.owner)
            assert.is_true(def.hideable)
            local voiceMsg = ctx.last('hud:voice')
            assert.is_true(voiceMsg.available)
            assert.are.equal('Normal', voiceMsg.mode)
            assert.is_false(voiceMsg.radio)
            assert.is_false(voiceMsg.radioActive)

            -- Reading: proximity and radioChannel handlers are on.
            local keys = {}
            for _, h in pairs(ctx.bagHandlers) do keys[h.key] = true end
            assert.is_true(keys.proximity)
            assert.is_true(keys.radioChannel)

            -- pma-voice stops.
            ctx.resourceState = 'stopped'
            natives.fire('onClientResourceStop', 'pma-voice')
            local removes = ctx.layoutCalls('aeterna_layout:remove', 'voice')
            assert.are.equal(1, #removes)
            assert.is_false(ctx.last('hud:voice').available)
            keys = {}
            for _, h in pairs(ctx.bagHandlers) do keys[h.key] = true end
            assert.is_nil(keys.proximity)
            assert.is_nil(keys.radioChannel)

            -- It starts again.
            ctx.resourceState = 'started'
            natives.fire('onClientResourceStart', 'pma-voice')
            assert.are.equal(2, #ctx.layoutCalls('aeterna_layout:add', 'voice'))

            -- Other resources do not trigger a check.
            natives.fire('onClientResourceStop', 'some_other')
            assert.are.equal(1, #ctx.layoutCalls('aeterna_layout:remove', 'voice'))
        end)

        it('client: a state still reading starting is picked up by the 1 s watcher', function()
            local ctx = load_client({ voiceState = 'starting' })
            natives.fire('onClientResourceStart', 'pma-voice')
            assert.are.equal(0, #ctx.layoutCalls('aeterna_layout:add', 'voice'))
            ctx.resourceState = 'started'
            natives.advance(1100)
            assert.are.equal(1, #ctx.layoutCalls('aeterna_layout:add', 'voice'))
            assert.is_true(ctx.last('hud:voice').available)
            natives.advance(2000)
            assert.are.equal(1, #ctx.layoutCalls('aeterna_layout:add', 'voice'))
        end)

        it('client: pma-voice absent at start registers nothing and sends no remove', function()
            local ctx = load_client({ voiceState = 'missing' })
            assert.are.equal(0, #ctx.layoutCalls('aeterna_layout:add', 'voice'))
            assert.are.equal(0, #ctx.layoutCalls('aeterna_layout:remove', 'voice'))
        end)

        it('client: Config.voice.enabled = false registers nothing either way', function()
            local ctx = load_client({ voiceState = 'started', config = shipped_config({ voice = { enabled = false } }) })
            assert.are.equal(0, #ctx.layoutCalls('aeterna_layout:add', 'voice'))
            ctx.resourceState = 'stopped'
            natives.fire('onClientResourceStop', 'pma-voice')
            ctx.resourceState = 'started'
            natives.fire('onClientResourceStart', 'pma-voice')
            assert.are.equal(0, #ctx.layoutCalls('aeterna_layout:add', 'voice'))
            assert.are.equal(0, #ctx.layoutCalls('aeterna_layout:remove', 'voice'))
            assert.are.equal(0, #ctx.messages('hud:voice'))
        end)

        it('client: talking, radio channel and radioActive follow their sources', function()
            local ctx = load_client({ voiceState = 'started', playerState = {} })
            local first = ctx.last('hud:voice')
            assert.is_true(first.available)
            assert.is_nil(first.mode)
            assert.is_false(first.talking)

            ctx.talking = true
            natives.advance(250)
            assert.is_true(ctx.last('hud:voice').talking)

            ctx.fireBag('radioChannel', 3)
            assert.is_true(ctx.last('hud:voice').radio)
            natives.fire('pma-voice:radioActive', true)
            assert.is_true(ctx.last('hud:voice').radioActive)
            natives.fire('pma-voice:radioActive', false)
            assert.is_false(ctx.last('hud:voice').radioActive)

            -- Leaving the channel drops transmitting too.
            natives.fire('pma-voice:radioActive', true)
            ctx.fireBag('radioChannel', 0)
            local msg = ctx.last('hud:voice')
            assert.is_false(msg.radio)
            assert.is_false(msg.radioActive)

            -- Another player's bag is ignored.
            for _, h in pairs(ctx.bagHandlers) do
                if h.key == 'radioChannel' then h.fn('player:99', 'radioChannel', 5, 0, true) end
            end
            assert.is_false(ctx.last('hud:voice').radio)

            -- Identical values send no message.
            local count = #ctx.messages('hud:voice')
            natives.advance(250)
            assert.are.equal(count, #ctx.messages('hud:voice'))
        end)
    end)

    describe('4. voice mode label (shared/logic/voice.lua)', function()
        local V
        before_each(function()
            natives.reset()
            V = load_logic('voice')
        end)

        it('index 1-3 -> locale key; index 4 -> metres from distance; missing -> hidden', function()
            for i = 1, 3 do
                assert.are.same({ key = 'hudkit.voice.mode.' .. i }, V.modeLabel({ index = i, distance = 5.0, mode = 'x' }))
            end
            assert.are.same({ meters = '15' }, V.modeLabel({ index = 4, distance = 15.0, mode = 'Far' }))
            assert.are.same({ meters = '1.5' }, V.modeLabel({ index = 4, distance = 1.5 }))
            assert.are.same({ meters = '8' }, V.modeLabel({ distance = 8 }))

            assert.is_nil(V.modeLabel(nil))
            assert.is_nil(V.modeLabel('Normal'))
            assert.is_nil(V.modeLabel({}))
            assert.is_nil(V.modeLabel({ index = 4 }))
            assert.is_nil(V.modeLabel({ index = 4, distance = -2 }))
        end)

        it('a radio channel counts only when it is a number above 0', function()
            assert.is_true(V.radioOn(1))
            assert.is_true(V.radioOn('12'))
            assert.is_false(V.radioOn(0))
            assert.is_false(V.radioOn(nil))
            assert.is_false(V.radioOn('none'))
        end)

        it('client: the proximity label is translated or shown in metres', function()
            local ctx = load_client({ voiceState = 'started', playerState = {} })
            ctx.fireBag('proximity', { index = 1, distance = 1.5, mode = 'Whisper' })
            assert.are.equal('Whisper', ctx.last('hud:voice').mode)
            ctx.fireBag('proximity', { index = 4, distance = 20.0, mode = 'Custom' })
            assert.are.equal('20 m', ctx.last('hud:voice').mode)
            ctx.fireBag('proximity', nil)
            assert.is_nil(ctx.last('hud:voice').mode)
        end)

        it('client: the metres unit comes from the locale key hudkit.unit.m', function()
            local ctx = load_client({ voiceState = 'started', playerState = {} })
            natives.stub('AeternaCore', {
                log = { warn = function() end },
                t = function(k) return (Locales.th and Locales.th[k]) or k end,
            })
            ctx.fireBag('proximity', { index = 4, distance = 20.0 })
            assert.are.equal('20 ม.', ctx.last('hud:voice').mode)
            assert.are.equal('m', Locales.en['hudkit.unit.m'])
        end)
    end)

    describe('5. seatbelt (shared/logic/seatbelt.lua and client)', function()
        it('true, false, nil; hidden outside a vehicle; the owner stopping hides it', function()
            natives.reset()
            local S = load_logic('seatbelt')
            local warned = 0
            local belt = S.create({ warn = function() warned = warned + 1 end })

            -- Nobody fired yet: hidden even in a vehicle.
            assert.is_nil(belt.display(true))

            assert.is_true(belt.set('res_a', { on = true }))
            assert.is_true(belt.display(true))
            assert.is_nil(belt.display(false))

            assert.is_true(belt.set('res_a', { on = false }))
            assert.is_false(belt.display(true))

            -- nil from another resource is refused; only the owner may hide it.
            assert.is_false(belt.set('res_other', nil))
            assert.is_false(belt.display(true))
            assert.is_false(belt.set(nil, { on = true }))
            assert.is_false(belt.display(true))

            assert.is_true(belt.set('res_a', nil))
            assert.is_nil(belt.display(true))

            -- Invalid payloads are refused and keep the state.
            assert.is_true(belt.set('res_a', { on = true }))
            assert.is_false(belt.set('res_a', { on = 'yes' }))
            assert.is_false(belt.set('res_a', 'on'))
            assert.are.equal(4, warned)
            assert.is_true(belt.display(true))

            -- The last resource that fired owns it; only its stop hides it.
            assert.is_true(belt.set('res_b', { on = false }))
            assert.are.equal('res_b', belt.owner())
            assert.is_false(belt.ownerStopped('res_a'))
            assert.is_false(belt.display(true))
            assert.is_true(belt.ownerStopped('res_b'))
            assert.is_nil(belt.display(true))
            assert.is_nil(belt.owner())
        end)

        it('client: the local event drives hud:seatbelt and an owner stop hides it', function()
            local ctx = load_client({ invoker = 'belt_res', inVehicle = true })
            natives.fire('aeterna_hudkit:seatbelt', { on = true })
            assert.is_true(ctx.last('hud:seatbelt').state)
            natives.fire('aeterna_hudkit:seatbelt', { on = false })
            assert.is_false(ctx.last('hud:seatbelt').state)
            natives.fire('aeterna_hudkit:seatbelt', nil)
            assert.is_nil(ctx.last('hud:seatbelt').state)

            natives.fire('aeterna_hudkit:seatbelt', { on = true })
            assert.is_true(ctx.last('hud:seatbelt').state)

            -- Leaving the vehicle hides it on the next tick.
            ctx.inVehicle = false
            natives.advance(250)
            assert.is_nil(ctx.last('hud:seatbelt').state)
            ctx.inVehicle = true
            natives.advance(250)
            assert.is_true(ctx.last('hud:seatbelt').state)

            -- Another resource stopping changes nothing; the owner stopping hides it.
            local count = #ctx.messages('hud:seatbelt')
            natives.fire('onResourceStop', 'other_res')
            assert.are.equal(count, #ctx.messages('hud:seatbelt'))
            natives.fire('onResourceStop', 'belt_res')
            assert.is_nil(ctx.last('hud:seatbelt').state)
        end)

        it('client: an event with no invoking resource is refused, payload.owner is not trusted', function()
            local ctx = load_client({ inVehicle = true })
            natives.fire('aeterna_hudkit:seatbelt', { on = true })
            natives.fire('aeterna_hudkit:seatbelt', { on = false, owner = 'spoofed_res' })
            natives.advance(250)
            for _, msg in ipairs(ctx.messages('hud:seatbelt')) do
                assert.is_nil(msg.state)
            end
        end)

        it('client: Config.seatbelt.enabled = false never shows it', function()
            local ctx = load_client({ invoker = 'belt_res', inVehicle = true,
                config = shipped_config({ seatbelt = { enabled = false } }) })
            natives.fire('aeterna_hudkit:seatbelt', { on = true })
            natives.advance(250)
            for _, msg in ipairs(ctx.messages('hud:seatbelt')) do
                assert.is_nil(msg.state)
            end
        end)
    end)

    describe('6. settings 0.2 (shared/logic/hud.lua and client)', function()
        it('barStyle accepts only bar and ring', function()
            natives.reset()
            local H = assert(loadfile(DIR .. '/shared/logic/hud.lua'))()
            assert.is_true((H.validateSetting('barStyle', 'bar')))
            assert.is_true((H.validateSetting('barStyle', 'ring')))
            assert.is_false((H.validateSetting('barStyle', 'donut')))
            assert.is_false((H.validateSetting('barStyle', true)))
            assert.is_false((H.validateSetting('barStyle', nil)))
        end)

        it('a 0.1 KVP value without barStyle reads as the config default', function()
            natives.reset()
            local H = assert(loadfile(DIR .. '/shared/logic/hud.lua'))()
            local defaults = { numbers = false, speedUnit = 'kmh', minimapMode = 'always', barStyle = 'ring' }
            local old = json.decode(json.encode({ numbers = true, speedUnit = 'mph', minimapMode = 'never' }))
            local s = H.resolveSettings(old, defaults)
            assert.are.equal('ring', s.barStyle)
            assert.are.equal('mph', s.speedUnit)
            assert.are.equal('never', s.minimapMode)
            assert.is_true(s.numbers)

            assert.are.equal('bar', H.resolveSettings({ barStyle = 'bar' }, defaults).barStyle)
            assert.are.equal('ring', H.resolveSettings({ barStyle = 'hexagon' }, defaults).barStyle)
            assert.are.equal('bar', H.resolveSettings(nil, nil).barStyle)

            -- Round trip keeps barStyle.
            local saved = json.decode(json.encode(H.resolveSettings({ barStyle = 'bar' }, defaults)))
            assert.are.equal('bar', H.resolveSettings(saved, defaults).barStyle)
        end)

        it('client: settings:open carries barStyle and the callback stores it', function()
            local ctx = load_client({ config = shipped_config({ barStyle = 'ring' }) })
            local stored = nil
            natives.stub('AeternaCore', {
                log = { warn = function() end },
                t = function(k) return k end,
                kvp = {
                    get = function(_, _, default) return default end,
                    set = function(_, _, v) stored = v end,
                },
                requestFocus = function() return 'tok' end,
                releaseFocus = function() return true end,
            })
            natives.fire('aeterna_hudkit:cl:settings')
            local open = ctx.last('settings:open')
            assert.are.equal('ring', open.settings.barStyle)
            assert.are.equal(120, open.span)

            ctx.callbacks.settings({ key = 'barStyle', value = 'bar' }, function() end)
            assert.are.equal('bar', stored.barStyle)
            ctx.callbacks.settings({ key = 'barStyle', value = 'wheel' }, function() end)
            assert.are.equal('bar', stored.barStyle)
        end)

        it('client: while focus is paused the card stays open and ignores input', function()
            local ctx = load_client({})
            local released = 0
            local stored = nil
            natives.stub('AeternaCore', {
                log = { warn = function() end },
                t = function(k) return k end,
                kvp = {
                    get = function(_, _, default) return default end,
                    set = function(_, _, v) stored = v end,
                },
                requestFocus = function() return 'tok' end,
                releaseFocus = function() released = released + 1; return true end,
            })
            natives.fire('aeterna_hudkit:cl:settings')
            assert.are.equal(1, #ctx.messages('settings:open'))

            natives.fire('aeterna_core:focusPaused', 'aeterna_hudkit', 'tok')
            ctx.callbacks.settings({ key = 'barStyle', value = 'ring' }, function() end)
            ctx.callbacks.close({}, function() end)
            ctx.callbacks.layoutEditor({}, function() end)
            assert.is_nil(stored)
            assert.are.equal(0, released)
            assert.are.equal(0, #ctx.messages('settings:close'))

            natives.fire('aeterna_core:focusResumed', 'aeterna_hudkit', 'tok')
            ctx.callbacks.close({}, function() end)
            assert.are.equal(1, released)
            assert.are.equal(1, #ctx.messages('settings:close'))
        end)
    end)

    describe('8. extra bar label length counts characters (0.1 fix)', function()
        it('accepts 24 Thai characters, refuses 25 and invalid UTF-8', function()
            natives.reset()
            local H = assert(loadfile(DIR .. '/shared/logic/hud.lua'))()
            local reg = H.createBarsRegistry({})
            local thai24 = string.rep('ก', 24) -- 72 bytes, 24 characters
            local thai25 = string.rep('ก', 25)
            assert.is_true(reg.add('res', { id = 'th24', label = thai24, icon = 'activity', value = 50 }))
            assert.is_false(reg.add('res', { id = 'th25', label = thai25, icon = 'activity', value = 50 }))
            assert.is_false(reg.add('res', { id = 'bad', label = '\255\254', icon = 'activity', value = 50 }))
            assert.is_false(reg.add('res', { id = 'empty', label = '', icon = 'activity', value = 50 }))
            assert.is_false(reg.add('res', { id = 'none', icon = 'activity', value = 50 }))
        end)
    end)

    describe('7. compass and layout elements (client)', function()
        it('registers compass and sends hud:compass only when the whole degree changes', function()
            local ctx = load_client({})
            local camZ = 0.0
            natives.stub('GetGameplayCamRot', function() return { x = 0.0, y = 0.0, z = camZ } end)
            assert.are.equal(1, #ctx.layoutCalls('aeterna_layout:add', 'compass'))

            natives.advance(250)
            assert.are.equal(0, ctx.last('hud:compass').deg)
            local count = #ctx.messages('hud:compass')
            camZ = -0.2
            natives.advance(250)
            assert.are.equal(count, #ctx.messages('hud:compass'))
            camZ = -90.0
            natives.advance(250)
            assert.are.equal(90, ctx.last('hud:compass').deg)
        end)

        it('a compass-only thread follows the camera at about 50 ms and pauses while hidden', function()
            local ctx = load_client({})
            local camZ = 0.0
            natives.stub('GetGameplayCamRot', function() return { x = 0.0, y = 0.0, z = camZ } end)
            -- Before the first 200 ms tick, the compass thread has already sent.
            natives.advance(60)
            assert.are.equal(0, ctx.last('hud:compass').deg)
            camZ = -45.0
            natives.advance(60)
            assert.are.equal(45, ctx.last('hud:compass').deg)

            -- Hidden in the layout editor: no more compass messages.
            natives.fire('aeterna_layout:apply', 'aeterna_hudkit', 'compass',
                { x = 0.5, y = 0.02, ax = 0.5, ay = 0, scale = 1, hidden = true })
            local count = #ctx.messages('hud:compass')
            camZ = -90.0
            natives.advance(600)
            assert.are.equal(count, #ctx.messages('hud:compass'))

            -- Shown again: it resumes.
            natives.fire('aeterna_layout:apply', 'aeterna_hudkit', 'compass',
                { x = 0.5, y = 0.02, ax = 0.5, ay = 0, scale = 1, hidden = false })
            natives.advance(600)
            assert.are.equal(90, ctx.last('hud:compass').deg)
        end)

        it('Config.compass.enabled = false registers no compass and sends no hud:compass', function()
            local ctx = load_client({ config = shipped_config({ compass = { enabled = false, span = 120 } }) })
            natives.advance(500)
            assert.are.equal(0, #ctx.layoutCalls('aeterna_layout:add', 'compass'))
            assert.are.equal(0, #ctx.messages('hud:compass'))
        end)

        it('ready accepts sizes for compass and voice and ignores unknown ids', function()
            local ctx = load_client({ voiceState = 'started' })
            ctx.callbacks.ready({ sizes = {
                status = { w = 300, h = 90 },
                compass = { w = 410, h = 50 },
                voice = { w = 130, h = 30 },
                bogus = { w = 10, h = 10 },
            } }, function() end)
            local compassAdds = ctx.layoutCalls('aeterna_layout:add', 'compass')
            assert.are.equal(410, compassAdds[#compassAdds].args[1].w)
            local voiceAdds = ctx.layoutCalls('aeterna_layout:add', 'voice')
            assert.are.equal(130, voiceAdds[#voiceAdds].args[1].w)
            assert.are.equal(0, #ctx.layoutCalls('aeterna_layout:add', 'bogus'))
            -- ready resends the voice state.
            assert.is_true(ctx.last('hud:voice').available)
        end)
    end)
end)
