-- layout_spec.lua -- busted tests for aeterna_layout (pure logic in shared/logic/layout.lua + resource harness tests).

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

-- Fires one of core's local events as aeterna_core (the handlers drop the same event from anyone else).
local function fireCore(name, ...)
    local prev = rawget(_G, 'GetInvokingResource')
    rawset(_G, 'GetInvokingResource', function() return 'aeterna_core' end)
    natives.fire(name, ...)
    rawset(_G, 'GetInvokingResource', prev)
end

local function load_logic()
    return assert(loadfile(DIR .. '/shared/logic/layout.lua'))()
end

local function validDef(overrides)
    local d = {
        id = 'status',
        label = 'Status bars',
        w = 200,
        h = 60,
        x = 0.05,
        y = 0.9,
        ax = 0,
        ay = 1,
        scalable = true,
        hideable = true,
    }
    if type(overrides) == 'table' then
        for k, v in pairs(overrides) do
            d[k] = v
        end
    end
    return d
end

describe('aeterna_layout', function()
    describe('1. placement (shared/logic/layout.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = load_logic()
        end)

        it('computes left/top from x, y, ax, ay, scale for each anchor (0, 0.5, 1)', function()
            local screenW, screenH = 1920, 1080
            local w, h = 200, 100

            -- Anchor 0, 0 (top-left) at scale 1.0
            local l1, t1, sw1, sh1 = L.placeToPixels({ x = 0.25, y = 0.5, ax = 0, ay = 0, scale = 1.0 }, w, h, screenW, screenH)
            assert.are.equal(480, l1)
            assert.are.equal(540, t1)
            assert.are.equal(200, sw1)
            assert.are.equal(100, sh1)

            -- Anchor 0.5, 0.5 (centre) at scale 1.5
            local l2, t2, sw2, sh2 = L.placeToPixels({ x = 0.5, y = 0.5, ax = 0.5, ay = 0.5, scale = 1.5 }, w, h, screenW, screenH)
            assert.are.equal(960 - 150, l2)
            assert.are.equal(540 - 75, t2)
            assert.are.equal(300, sw2)
            assert.are.equal(150, sh2)

            -- Anchor 1, 1 (bottom-right) at scale 0.5
            local l3, t3, sw3, sh3 = L.placeToPixels({ x = 1.0, y = 1.0, ax = 1, ay = 1, scale = 0.5 }, w, h, screenW, screenH)
            assert.are.equal(1920 - 100, l3)
            assert.are.equal(1080 - 50, t3)
            assert.are.equal(100, sw3)
            assert.are.equal(50, sh3)
        end)

        it('round-trips drop -> place -> pixels within 1 px across screen positions', function()
            local screenW, screenH = 1920, 1080
            local w, h = 240, 80
            local drops = {
                { left = 32, top = 40, scale = 1.0 },
                { left = 800, top = 480, scale = 1.25 },
                { left = 1500, top = 900, scale = 0.75 },
            }
            for _, d in ipairs(drops) do
                local place = L.dropToPlace(d.left, d.top, w, h, d.scale, screenW, screenH, { snap = 0 })
                local rx, ry = L.placeToPixels(place, w, h, screenW, screenH)
                assert.is_true(math.abs(rx - d.left) <= 1, ('left drift %.4f for %d'):format(math.abs(rx - d.left), d.left))
                assert.is_true(math.abs(ry - d.top) <= 1, ('top drift %.4f for %d'):format(math.abs(ry - d.top), d.top))
            end
        end)
    end)

    describe('2. anchor choice (shared/logic/layout.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = load_logic()
        end)

        it('picks ax/ay = 0 in the first third, 0.5 in the middle third, and 1 in the last third', function()
            local screenW, screenH = 1920, 1080
            local w, h = 120, 60

            local pTopLeft = L.dropToPlace(100, 80, w, h, 1.0, screenW, screenH, { snap = 0 })
            assert.are.equal(0, pTopLeft.ax)
            assert.are.equal(0, pTopLeft.ay)

            local pCenter = L.dropToPlace(900, 500, w, h, 1.0, screenW, screenH, { snap = 0 })
            assert.are.equal(0.5, pCenter.ax)
            assert.are.equal(0.5, pCenter.ay)

            local pBottomRight = L.dropToPlace(1600, 900, w, h, 1.0, screenW, screenH, { snap = 0 })
            assert.are.equal(1, pBottomRight.ax)
            assert.are.equal(1, pBottomRight.ay)

            local pTopRight = L.dropToPlace(1650, 50, w, h, 1.0, screenW, screenH, { snap = 0 })
            assert.are.equal(1, pTopRight.ax)
            assert.are.equal(0, pTopRight.ay)

            local pBottomLeft = L.dropToPlace(40, 920, w, h, 1.0, screenW, screenH, { snap = 0 })
            assert.are.equal(0, pBottomLeft.ax)
            assert.are.equal(1, pBottomLeft.ay)
        end)
    end)

    describe('3. clamp (shared/logic/layout.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = load_logic()
        end)

        it('keeps the whole element on screen when dropped past any edge at every scale', function()
            local screenW, screenH = 1920, 1080
            local w, h = 300, 120
            local scales = { 0.5, 1.0, 1.5, 2.0 }

            for _, scale in ipairs(scales) do
                -- Past top-left
                local p1 = L.dropToPlace(-250, -180, w, h, scale, screenW, screenH, { snap = 0 })
                local l1, t1, sw1, sh1 = L.placeToPixels(p1, w, h, screenW, screenH)
                assert.is_true(l1 >= -1e-6)
                assert.is_true(t1 >= -1e-6)
                assert.is_true(l1 + sw1 <= screenW + 1e-6)
                assert.is_true(t1 + sh1 <= screenH + 1e-6)

                -- Past bottom-right
                local p2 = L.dropToPlace(2400, 1500, w, h, scale, screenW, screenH, { snap = 0 })
                local l2, t2, sw2, sh2 = L.placeToPixels(p2, w, h, screenW, screenH)
                assert.is_true(l2 >= -1e-6)
                assert.is_true(t2 >= -1e-6)
                assert.is_true(math.abs((l2 + sw2) - screenW) <= 1e-4)
                assert.is_true(math.abs((t2 + sh2) - screenH) <= 1e-4)
            end
        end)
    end)

    describe('4. snap (shared/logic/layout.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = load_logic()
        end)

        it('snaps positions to the grid step and keeps raw values when Shift is held or snap is 0', function()
            local sx, sy = L.snapPosition(21, 35, 8, false)
            assert.are.equal(24, sx)
            assert.are.equal(32, sy)

            local rawX, rawY = L.snapPosition(21, 35, 8, true)
            assert.are.equal(21, rawX)
            assert.are.equal(35, rawY)

            local zeroX, zeroY = L.snapPosition(21, 35, 0, false)
            assert.are.equal(21, zeroX)
            assert.are.equal(35, zeroY)

            -- Drop with snap = 8 vs shift = true
            local pSnapped = L.dropToPlace(21, 35, 100, 50, 1.0, 1920, 1080, { snap = 8, shift = false })
            local lx, ty = L.placeToPixels(pSnapped, 100, 50, 1920, 1080)
            assert.is_true(math.abs(lx - 24) < 1e-6)
            assert.is_true(math.abs(ty - 32) < 1e-6)

            local pRaw = L.dropToPlace(21, 35, 100, 50, 1.0, 1920, 1080, { snap = 8, shift = true })
            local rlx, rty = L.placeToPixels(pRaw, 100, 50, 1920, 1080)
            assert.is_true(math.abs(rlx - 21) < 1e-6)
            assert.is_true(math.abs(rty - 35) < 1e-6)
        end)
    end)

    describe('5. schema validation (shared/logic/layout.lua)', function()
        local L, warnings
        local function warnSpy(msg, fields)
            warnings[#warnings + 1] = { msg = msg, fields = fields }
        end

        before_each(function()
            natives.reset()
            L = load_logic()
            warnings = {}
        end)

        it('refuses bad id, size out of range, anchor 0.3, and scale outside range with a warn', function()
            -- Bad id (spaces / invalid chars / over 32 chars)
            local okId1, errId1 = L.validateDef(validDef({ id = 'bad id!' }), nil, warnSpy)
            assert.is_false(okId1)
            assert.is_truthy(errId1 and errId1:match('^id:'))
            assert.are.equal(1, #warnings)

            local okId2, errId2 = L.validateDef(validDef({ id = string.rep('a', 33) }), nil, warnSpy)
            assert.is_false(okId2)
            assert.is_truthy(errId2 and errId2:match('^id:'))
            assert.are.equal(2, #warnings)

            -- Size out of range (< 8 or > 2000)
            local okWLow, errWLow = L.validateDef(validDef({ w = 7 }), nil, warnSpy)
            assert.is_false(okWLow)
            assert.is_truthy(errWLow and errWLow:match('^w:'))
            assert.are.equal(3, #warnings)

            local okHHigh, errHHigh = L.validateDef(validDef({ h = 2001 }), nil, warnSpy)
            assert.is_false(okHHigh)
            assert.is_truthy(errHHigh and errHHigh:match('^h:'))
            assert.are.equal(4, #warnings)

            -- Anchor 0.3 (not in {0, 0.5, 1})
            local okAx, errAx = L.validateDef(validDef({ ax = 0.3 }), nil, warnSpy)
            assert.is_false(okAx)
            assert.is_truthy(errAx and errAx:match('^ax:'))
            assert.are.equal(5, #warnings)

            local okAy, errAy = L.validateDef(validDef({ ay = 0.3 }), nil, warnSpy)
            assert.is_false(okAy)
            assert.is_truthy(errAy and errAy:match('^ay:'))
            assert.are.equal(6, #warnings)

            -- Scale outside range (0.5..2.0) in def and in moved callback
            local okScaleLow, errScaleLow = L.validateDef(validDef({ scale = 0.4 }), nil, warnSpy)
            assert.is_false(okScaleLow)
            assert.is_truthy(errScaleLow and errScaleLow:match('^scale:'))
            assert.are.equal(7, #warnings)

            local okMovedScale, errMovedScale = L.validateMoved({
                owner = 'aeterna_hudkit',
                id = 'status',
                x = 0.5,
                y = 0.5,
                ax = 0.5,
                ay = 0.5,
                scale = 2.5,
            }, nil, warnSpy)
            assert.is_false(okMovedScale)
            assert.is_truthy(errMovedScale and errMovedScale:match('^scale:'))
            assert.are.equal(8, #warnings)
        end)
    end)

    describe('6. registry (shared/logic/layout.lua)', function()
        local L, warnings, applied
        before_each(function()
            natives.reset()
            L = load_logic()
            warnings = {}
            applied = {}
        end)

        it('replaces on re-adding same owner/id, removes only stopped owner elements, and enforces Config.maxElements', function()
            local reg = L.createRegistry({
                config = { maxElements = 3, snap = 8, scale = { min = 0.5, max = 2.0, step = 0.05 } },
                warn = function(msg, fields) warnings[#warnings + 1] = { msg = msg, fields = fields } end,
                onApply = function(owner, id, place)
                    applied[#applied + 1] = { owner = owner, id = id, place = place }
                end,
            })

            assert.is_true(reg:add('res_a', validDef({ id = 'box1', w = 100 })))
            assert.is_true(reg:add('res_a', validDef({ id = 'box2', w = 120 })))
            assert.is_true(reg:add('res_b', validDef({ id = 'box1', w = 140 })))
            assert.are.equal(3, reg:countElements())

            -- Re-adding the same owner/id replaces it and does not exceed maxElements
            assert.is_true(reg:add('res_a', validDef({ id = 'box1', w = 180, label = 'Updated' })))
            assert.are.equal(3, reg:countElements())
            local updated = reg:get('res_a', 'box1')
            assert.are.equal(180, updated.def.w)
            assert.are.equal('Updated', updated.def.label)
            assert.are.equal(0, #warnings)

            -- Adding a 4th distinct element is refused with a warn
            local okExtra, errExtra = reg:add('res_b', validDef({ id = 'box2' }))
            assert.is_false(okExtra)
            assert.is_truthy(errExtra and errExtra:match('^maxElements:'))
            assert.are.equal(1, #warnings)
            assert.are.equal(3, reg:countElements())

            -- Stopping res_a removes only res_a's elements
            local removed = reg:removeByOwner('res_a')
            assert.are.equal(2, removed)
            assert.are.equal(1, reg:countElements())
            assert.is_nil(reg:get('res_a', 'box1'))
            assert.is_nil(reg:get('res_a', 'box2'))
            assert.is_not_nil(reg:get('res_b', 'box1'))
        end)
    end)

    describe('7. storage (shared/logic/layout.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = load_logic()
        end)

        it('writes on Done, does not write on Cancel and restores places, and preserves unregistered elements', function()
            local savedStore = {
                ['unregistered_res/old_widget'] = {
                    x = 0.85,
                    y = 0.15,
                    ax = 1,
                    ay = 0,
                    scale = 1.25,
                    hidden = true,
                },
            }
            local writeCalls = 0
            local reg = L.createRegistry({
                initialPlaces = savedStore,
                savePlaces = function(newStore)
                    writeCalls = writeCalls + 1
                    savedStore = newStore
                end,
            })

            assert.is_true(reg:add('res_a', validDef({
                id = 'hud',
                x = 0.1,
                y = 0.9,
                ax = 0,
                ay = 1,
                scalable = true,
                hideable = true,
            })))

            -- Session 1: move element then Cancel -> does not write, reverts to snapshot
            reg:beginSession()
            assert.is_true(reg:move({
                owner = 'res_a',
                id = 'hud',
                x = 0.5,
                y = 0.5,
                ax = 0.5,
                ay = 0.5,
                scale = 1.5,
            }))
            assert.are.equal(0.5, reg:get('res_a', 'hud').place.x)

            reg:cancelSession()
            assert.are.equal(0, writeCalls)
            assert.are.equal(0.1, reg:get('res_a', 'hud').place.x)
            assert.are.equal(1.0, reg:get('res_a', 'hud').place.scale)

            -- Session 2: move element then Done -> writes to storage and keeps unregistered element
            reg:beginSession()
            assert.is_true(reg:move({
                owner = 'res_a',
                id = 'hud',
                x = 0.75,
                y = 0.25,
                ax = 1,
                ay = 0,
                scale = 1.4,
            }))
            assert.is_true(reg:hide({
                owner = 'res_a',
                id = 'hud',
                hidden = true,
            }))
            reg:commitSession()

            assert.are.equal(1, writeCalls)
            assert.are.same({
                x = 0.75,
                y = 0.25,
                ax = 1,
                ay = 0,
                scale = 1.4,
                hidden = true,
            }, savedStore['res_a/hud'])
            assert.are.same({
                x = 0.85,
                y = 0.15,
                ax = 1,
                ay = 0,
                scale = 1.25,
                hidden = true,
            }, savedStore['unregistered_res/old_widget'])
        end)

        it('keeps Reset all in the session, writes only on Done, and Cancel restores the opening places', function()
            local savedStore = {
                ['res_a/hud'] = {
                    x = 0.4,
                    y = 0.4,
                    ax = 0.5,
                    ay = 0.5,
                    scale = 1.5,
                    hidden = false,
                },
                ['unregistered_res/old_widget'] = {
                    x = 0.85,
                    y = 0.15,
                    ax = 1,
                    ay = 0,
                    scale = 1.25,
                    hidden = true,
                },
            }
            local writeCalls = 0
            local reg = L.createRegistry({
                initialPlaces = savedStore,
                savePlaces = function(newStore)
                    writeCalls = writeCalls + 1
                    savedStore = newStore
                end,
            })

            assert.is_true(reg:add('res_a', validDef({
                id = 'hud',
                x = 0.1,
                y = 0.9,
                ax = 0,
                ay = 1,
            })))

            reg:beginSession()
            assert.is_true(reg:reset({}))
            assert.are.equal(0, writeCalls)
            assert.are.equal(0.1, reg:get('res_a', 'hud').place.x)
            assert.are.equal(1.0, reg:get('res_a', 'hud').place.scale)

            reg:cancelSession()
            assert.are.equal(0, writeCalls)
            assert.are.equal(0.4, reg:get('res_a', 'hud').place.x)
            assert.are.equal(1.5, reg:get('res_a', 'hud').place.scale)

            reg:beginSession()
            assert.is_true(reg:reset({}))
            reg:commitSession()
            assert.are.equal(1, writeCalls)
            assert.is_nil(savedStore['res_a/hud'])
            assert.are.same({
                x = 0.85,
                y = 0.15,
                ax = 1,
                ay = 0,
                scale = 1.25,
                hidden = true,
            }, savedStore['unregistered_res/old_widget'])
        end)

        it('saves only elements moved from their def default and removes saved keys that match', function()
            local savedStore = {
                ['res_a/at_default'] = {
                    x = 0.2,
                    y = 0.2,
                    ax = 0,
                    ay = 0,
                    scale = 1.0,
                    hidden = false,
                },
                ['unregistered_res/old_widget'] = {
                    x = 0.85,
                    y = 0.15,
                    ax = 1,
                    ay = 0,
                    scale = 1.25,
                    hidden = true,
                },
            }
            local writeCalls = 0
            local reg = L.createRegistry({
                initialPlaces = savedStore,
                savePlaces = function(newStore)
                    writeCalls = writeCalls + 1
                    savedStore = newStore
                end,
            })

            assert.is_true(reg:add('res_a', validDef({
                id = 'at_default',
                x = 0.2,
                y = 0.2,
                ax = 0,
                ay = 0,
            })))
            reg:beginSession()
            reg:commitSession()

            assert.are.equal(1, writeCalls)
            assert.is_nil(savedStore['res_a/at_default'])
            assert.are.same({
                x = 0.85,
                y = 0.15,
                ax = 1,
                ay = 0,
                scale = 1.25,
                hidden = true,
            }, savedStore['unregistered_res/old_widget'])
        end)

        it('keeps the in-session place and snapshot when an existing element is re-added during a session', function()
            local reg = L.createRegistry({
                initialPlaces = {
                    ['res_a/hud'] = {
                        x = 0.6,
                        y = 0.6,
                        ax = 1,
                        ay = 1,
                        scale = 1.25,
                        hidden = false,
                    },
                },
            })
            assert.is_true(reg:add('res_a', validDef({
                id = 'hud',
                x = 0.1,
                y = 0.9,
                ax = 0,
                ay = 1,
            })))
            reg:beginSession()
            assert.is_true(reg:move({
                owner = 'res_a',
                id = 'hud',
                x = 0.4,
                y = 0.4,
                ax = 0.5,
                ay = 0.5,
                scale = 1.5,
            }))

            assert.is_true(reg:add('res_a', validDef({
                id = 'hud',
                x = 0.1,
                y = 0.9,
                ax = 0,
                ay = 1,
            })))
            local current = reg:get('res_a', 'hud')
            assert.are.equal(0.4, current.place.x)
            assert.are.equal(1.5, current.place.scale)

            reg:cancelSession()
            assert.are.equal(0.6, reg:get('res_a', 'hud').place.x)
            assert.are.equal(1.25, reg:get('res_a', 'hud').place.scale)
        end)
    end)

    describe('8. resource scripts under harness', function()
        it('server registers menu entry and opens client editor on aeterna_uikit:menu', function()
            natives.reset({ resource = 'aeterna_layout', side = 'server' })
            local addedEntries = {}
            natives.stub_export('aeterna_uikit', 'addMenuEntry', function(entry)
                addedEntries[#addedEntries + 1] = entry
                return true
            end)

            resource.load_resource(DIR, 'server', {
                externals = { ['@aeterna_core/import.lua'] = DIR .. '/../core/import.lua' },
            })

            assert.are.equal(1, #addedEntries)
            assert.are.equal('Edit HUD layout', addedEntries[1].label)
            -- 0.1 behaviour (the menu entry opens the editor); 0.2 menu panel is covered in layout_02_spec.lua
            Config.menuPanel = false

            -- Ignore other owners
            natives.fire('aeterna_uikit:menu', 3, { owner = 'other_res', id = addedEntries[1].id })
            assert.are.equal(0, #natives.emitted('client', 'aeterna_layout:cl:open'))

            -- Trigger for aeterna_layout
            natives.fire('aeterna_uikit:menu', 3, { owner = 'aeterna_layout', id = addedEntries[1].id })
            local openEvs = natives.emitted('client', 'aeterna_layout:cl:open')
            assert.are.equal(1, #openEvs)
            assert.are.equal(3, openEvs[1].target)
        end)

        it('client handles owner detection (GetInvokingResource + def.owner fallback), editor NUI callbacks and focusLost', function()
            natives.reset({ resource = 'aeterna_layout', side = 'client' })
            natives.spy('SetNuiFocus')
            natives.spy('SetNuiFocusKeepInput')
            local nuiCallbacks = {}
            local nuiMessages = natives.spy('SendNUIMessage')
            natives.spy('RegisterNUICallback', function(name, fn)
                nuiCallbacks[name] = fn
            end)
            natives.spy('RegisterCommand')
            natives.spy('RegisterKeyMapping')
            natives.spy('GetResourceState', function(resName)
                if resName == 'aeterna_hudkit' or resName == 'aeterna_notify' then
                    return 'started'
                end
                return 'missing'
            end)
            natives.stub_export('aeterna_core', 'requestFocus', function() return 'focus_tok_1' end)
            natives.stub_export('aeterna_core', 'releaseFocus', function() return true end)
            natives.stub_export('aeterna_core', 'themeHref', function() return nil end)

            resource.load_resource(DIR, 'client', {
                externals = { ['@aeterna_core/import.lua'] = DIR .. '/../core/import.lua' },
            })

            -- Announces aeterna_layout:hello on start
            local helloEvs = natives.emitted('local', 'aeterna_layout:hello')
            assert.are.equal(1, #helloEvs)

            -- Fallback when GetInvokingResource() is nil: requires def.owner matching a started resource
            natives.fire('aeterna_layout:add', validDef({ id = 'no_owner' }))
            assert.are.equal(0, #natives.emitted('local', 'aeterna_layout:apply'))

            natives.fire('aeterna_layout:add', validDef({ id = 'stopped_owner', owner = 'stopped_res' }))
            assert.are.equal(0, #natives.emitted('local', 'aeterna_layout:apply'))

            natives.fire('aeterna_layout:add', validDef({ id = 'toasts', owner = 'aeterna_notify' }))
            local applyEv = natives.last_emitted('local', 'aeterna_layout:apply')
            assert.is_truthy(applyEv)
            assert.are.equal('aeterna_notify', applyEv.args[1])
            assert.are.equal('toasts', applyEv.args[2])

            -- When GetInvokingResource() returns a resource name, it takes precedence
            natives.stub('GetInvokingResource', function() return 'aeterna_hudkit' end)
            natives.fire('aeterna_layout:add', validDef({ id = 'status' }))
            local applyHud = natives.last_emitted('local', 'aeterna_layout:apply')
            assert.are.equal('aeterna_hudkit', applyHud.args[1])
            assert.are.equal('status', applyHud.args[2])

            -- Open editor via client net event, move element, then lose focus -> reverts to snapshot
            natives.fire_net('aeterna_layout:cl:open', 1)
            assert.is_truthy(#nuiMessages >= 1)

            nuiCallbacks.moved({
                owner = 'aeterna_hudkit',
                id = 'status',
                x = 0.6,
                y = 0.4,
                ax = 0.5,
                ay = 0.5,
                scale = 1.25,
            }, function() end)
            local movedApply = natives.last_emitted('local', 'aeterna_layout:apply')
            assert.are.equal(0.6, movedApply.args[3].x)

            -- Focus lost acts as Cancel and reverts to 0.05
            fireCore('aeterna_core:focusLost', 'aeterna_layout', 'focus_tok_1', 'preempted')
            local revertApply = natives.last_emitted('local', 'aeterna_layout:apply')
            assert.are.equal('aeterna_hudkit', revertApply.args[1])
            assert.are.equal('status', revertApply.args[2])
            assert.are.equal(0.05, revertApply.args[3].x)
            assert.is_nil(natives.get_kvp('aeterna_layout:places:v1'))

            -- Open editor again, move and click Done -> persists to KVP
            natives.fire_net('aeterna_layout:cl:open', 1)
            nuiCallbacks.moved({
                owner = 'aeterna_hudkit',
                id = 'status',
                x = 0.7,
                y = 0.3,
                ax = 1,
                ay = 0,
                scale = 1.5,
            }, function() end)
            nuiCallbacks.done({}, function() end)

            local rawKvp = natives.get_kvp('aeterna_layout:places:v1')
            assert.is_string(rawKvp)
            local decoded = json.decode(rawKvp)
            assert.are.equal(0.7, decoded['aeterna_hudkit/status'].x)
            assert.are.equal(1.5, decoded['aeterna_hudkit/status'].scale)
        end)
    end)

    describe('9. locales (locales/*.lua)', function()
        it('adds layout keys without replacing the core locale tables', function()
            local previous = rawget(_G, 'Locales')
            rawset(_G, 'Locales', {
                en = { ['core.month.1'] = 'January' },
                th = { ['core.month.1'] = 'มกราคม' },
            })
            local ok, err = pcall(function()
                assert(loadfile(DIR .. '/locales/en.lua'))()
                assert(loadfile(DIR .. '/locales/th.lua'))()
            end)
            local loaded = rawget(_G, 'Locales')
            local enCore = loaded.en['core.month.1']
            local thCore = loaded.th['core.month.1']
            local enEntry = loaded.en['layout.menu.entry']
            local thEntry = loaded.th['layout.menu.entry']
            rawset(_G, 'Locales', previous)

            assert.is_true(ok, tostring(err))
            assert.are.equal('January', enCore)
            assert.are.equal('มกราคม', thCore)
            assert.are.equal('Edit HUD layout', enEntry)
            assert.are.equal('จัดวางหน้าจอ HUD', thEntry)
        end)
    end)

    describe('10. editor focus guard (client/main.lua)', function()
        it('does not open the editor when aeterna_core refuses focus', function()
            natives.reset({ resource = 'aeterna_layout', side = 'client' })
            natives.spy('SetNuiFocus')
            natives.spy('SetNuiFocusKeepInput')
            local nuiMessages = natives.spy('SendNUIMessage')
            natives.spy('RegisterNUICallback', function() end)
            natives.spy('RegisterCommand')
            natives.spy('RegisterKeyMapping')
            natives.spy('GetResourceState', function() return 'started' end)
            natives.stub_export('aeterna_core', 'requestFocus', function() return nil end)
            natives.stub_export('aeterna_core', 'releaseFocus', function() return true end)
            natives.stub_export('aeterna_core', 'themeHref', function() return nil end)

            resource.load_resource(DIR, 'client', {
                externals = { ['@aeterna_core/import.lua'] = DIR .. '/../core/import.lua' },
            })

            rawset(_G, 'source', 1)
            natives.fire_net('aeterna_layout:cl:open', 1)

            for i = 1, #nuiMessages do
                local msg = nuiMessages[i][1]
                assert.are_not.equal('editor:open', type(msg) == 'table' and msg.type or nil)
            end
            assert.is_nil(natives.get_kvp('aeterna_layout:places:v1'))
        end)
    end)
end)
