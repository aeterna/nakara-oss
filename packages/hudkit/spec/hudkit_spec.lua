-- spec/hudkit_spec.lua -- busted tests for aeterna_hudkit (pure logic + harness tests).

local natives = require('helpers.natives')
local resource = require('helpers.resource')

natives.registered_commands = natives.registered_commands or function()
    local cmds = {}
    for _, call in ipairs(natives.calls('RegisterCommand')) do
        cmds[call[1]] = call[2] or true
    end
    return cmds
end

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local function load_hud_logic()
    return assert(loadfile(DIR .. '/shared/logic/hud.lua'))()
end

local function load_minimap_logic()
    return assert(loadfile(DIR .. '/shared/logic/minimap.lua'))()
end

describe('aeterna_hudkit', function()
    describe('1. health mapping (shared/logic/hud.lua)', function()
        local H
        before_each(function()
            natives.reset()
            H = load_hud_logic()
        end)

        it('maps 100 -> 0 %, 150 -> 50 %, 200 -> 100 %, and clamps outside', function()
            -- Ped dies at 100 in FiveM (0 %), 200 is full health (100 %)
            assert.are.equal(0, H.mapHealth(100))
            assert.are.equal(50, H.mapHealth(150))
            assert.are.equal(100, H.mapHealth(200))

            -- Clamping below 100
            assert.are.equal(0, H.mapHealth(90))
            assert.are.equal(0, H.mapHealth(0))
            assert.are.equal(0, H.mapHealth(-50))

            -- Clamping above 200
            assert.are.equal(100, H.mapHealth(210))
            assert.are.equal(100, H.mapHealth(500))

            -- Intermediate values
            assert.are.equal(25, H.mapHealth(125))
            assert.are.equal(75, H.mapHealth(175))

            -- Non-number fallback
            assert.are.equal(0, H.mapHealth(nil))
            assert.are.equal(0, H.mapHealth('invalid'))
        end)
    end)

    describe('2. speed and gear (shared/logic/hud.lua)', function()
        local H
        before_each(function()
            natives.reset()
            H = load_hud_logic()
        end)

        it('converts m/s to km/h and mph rounded to whole numbers', function()
            -- 0 m/s
            assert.are.equal(0, H.speedToKmh(0))
            assert.are.equal(0, H.speedToMph(0))

            -- 10 m/s: 10 * 3.6 = 36 km/h; 10 * 2.236936 = 22.369 -> 22 mph
            assert.are.equal(36, H.speedToKmh(10))
            assert.are.equal(22, H.speedToMph(10))

            -- 27.78 m/s (approx 100 km/h; 27.78 * 2.236936 = 62.14 -> 62 mph)
            assert.are.equal(100, H.speedToKmh(27.78))
            assert.are.equal(62, H.speedToMph(27.78))

            -- Negative speed clamped to 0
            assert.are.equal(0, H.speedToKmh(-5))
            assert.are.equal(0, H.speedToMph(-5))
        end)

        it('formats gear text for reverse, neutral and 1-8', function()
            -- Reverse gear: flag or value
            assert.are.equal('R', H.gearText(0, true))
            assert.are.equal('R', H.gearText(1, true))
            assert.are.equal('R', H.gearText(-1, false))
            assert.are.equal('R', H.gearText('R', false))

            -- Neutral (0)
            assert.are.equal('N', H.gearText(0, false))
            assert.are.equal('N', H.gearText(nil, false))

            -- Forward gears 1 to 8
            for g = 1, 8 do
                assert.are.equal(tostring(g), H.gearText(g, false))
            end
        end)
    end)

    describe('3. heading sectors and 360 wrap (shared/logic/hud.lua)', function()
        local H
        before_each(function()
            natives.reset()
            H = load_hud_logic()
        end)

        it('maps angles to each of the eight sectors including wrap at 360', function()
            -- Center of each sector
            assert.are.equal('N', H.headingSector(0))
            assert.are.equal('NE', H.headingSector(45))
            assert.are.equal('E', H.headingSector(90))
            assert.are.equal('SE', H.headingSector(135))
            assert.are.equal('S', H.headingSector(180))
            assert.are.equal('SW', H.headingSector(225))
            assert.are.equal('W', H.headingSector(270))
            assert.are.equal('NW', H.headingSector(315))

            -- Sector boundaries (N: 337.5 to 22.5)
            assert.are.equal('N', H.headingSector(359.9))
            assert.are.equal('N', H.headingSector(22.4))
            assert.are.equal('NE', H.headingSector(22.5))
            assert.are.equal('NE', H.headingSector(67.4))
            assert.are.equal('E', H.headingSector(67.5))
            assert.are.equal('E', H.headingSector(112.4))
            assert.are.equal('SE', H.headingSector(112.5))
            assert.are.equal('S', H.headingSector(157.5))
            assert.are.equal('SW', H.headingSector(202.5))
            assert.are.equal('W', H.headingSector(247.5))
            assert.are.equal('NW', H.headingSector(292.5))
            assert.are.equal('N', H.headingSector(337.5))

            -- Wrap around 360 and negative degrees
            assert.are.equal('N', H.headingSector(360))
            assert.are.equal('N', H.headingSector(720))
            assert.are.equal('NW', H.headingSector(-45))
            assert.are.equal('W', H.headingSector(-90))
            assert.are.equal('S', H.headingSector(-180))

            -- Returns corresponding locale key as second value
            local code, locKey = H.headingSector(0)
            assert.are.equal('N', code)
            assert.are.equal('hudkit.dir.n', locKey)
        end)
    end)

    describe('4. minimap mapping and component delta (shared/logic/minimap.lua)', function()
        local M
        before_each(function()
            natives.reset()
            M = load_minimap_logic()
        end)

        it('round-trips offset -> screen -> offset within 0.0005 for 1920x1080 and ultrawide 3440x1440', function()
            -- S3 Reference Point A: 1920 x 1080, safe zone 0.97
            local refA_p0 = { x = 0.0150, y = 0.9850 }
            local refA_p1 = { x = 0.5775, y = 1.9850 }

            -- S3 Reference Point B: Ultrawide 3440 x 1440, safe zone 1.0
            local refB_p0 = { x = 0.0000, y = 1.0000 }
            local refB_p1 = { x = 0.4186, y = 2.0000 }

            local testOffsets = {
                { x = -0.0045, y = -0.0245 },
                { x = 0.0200, y = 0.0320 },
                { x = -0.0300, y = 0.0220 },
                { x = 0.1500, y = 0.2000 },
                { x = -0.1000, y = -0.0500 },
            }

            for _, off in ipairs(testOffsets) do
                -- Test ref A
                local sxA, syA = M.offsetToScreen(off.x, off.y, refA_p0, refA_p1)
                local roxA, royA = M.screenToOffset(sxA, syA, refA_p0, refA_p1)
                assert.is_true(math.abs(roxA - off.x) <= 0.0005, ('refA x error %f'):format(math.abs(roxA - off.x)))
                assert.is_true(math.abs(royA - off.y) <= 0.0005, ('refA y error %f'):format(math.abs(royA - off.y)))

                -- Test ref B
                local sxB, syB = M.offsetToScreen(off.x, off.y, refB_p0, refB_p1)
                local roxB, royB = M.screenToOffset(sxB, syB, refB_p0, refB_p1)
                assert.is_true(math.abs(roxB - off.x) <= 0.0005, ('refB x error %f'):format(math.abs(roxB - off.x)))
                assert.is_true(math.abs(royB - off.y) <= 0.0005, ('refB y error %f'):format(math.abs(royB - off.y)))
            end
        end)

        it('moving by a delta keeps the three components relative offsets', function()
            local defaults = M.DEFAULT_COMPONENTS
            local deltaX = 0.05
            local deltaY = -0.03
            local scale = 1.25

            local pos = M.computePositions(deltaX, deltaY, scale, defaults)

            -- Check relative offsets between minimap, minimap_mask and minimap_blur
            local origRelMaskX = defaults.minimap.x - defaults.minimap_mask.x
            local origRelMaskY = defaults.minimap.y - defaults.minimap_mask.y
            local origRelBlurX = defaults.minimap.x - defaults.minimap_blur.x
            local origRelBlurY = defaults.minimap.y - defaults.minimap_blur.y

            local newRelMaskX = pos.minimap.x - pos.minimap_mask.x
            local newRelMaskY = pos.minimap.y - pos.minimap_mask.y
            local newRelBlurX = pos.minimap.x - pos.minimap_blur.x
            local newRelBlurY = pos.minimap.y - pos.minimap_blur.y

            assert.is_true(math.abs(newRelMaskX - origRelMaskX * scale) < 1e-9)
            assert.is_true(math.abs(newRelMaskY - origRelMaskY * scale) < 1e-9)
            assert.is_true(math.abs(newRelBlurX - origRelBlurX * scale) < 1e-9)
            assert.is_true(math.abs(newRelBlurY - origRelBlurY * scale) < 1e-9)

            -- Scales applied
            assert.are.equal(defaults.minimap.w * scale, pos.minimap.w)
            assert.are.equal(defaults.minimap.h * scale, pos.minimap.h)
            assert.are.equal(defaults.minimap_mask.w * scale, pos.minimap_mask.w)
            assert.are.equal(defaults.minimap_blur.w * scale, pos.minimap_blur.w)
        end)
    end)

    describe('5. extra bars registry (shared/logic/hud.lua)', function()
        local H, warnings
        local function warnSpy(msg, fields)
            warnings[#warnings + 1] = { msg = msg, fields = fields }
        end

        before_each(function()
            natives.reset()
            H = load_hud_logic()
            warnings = {}
        end)

        it('supports add, update, nil hides, ninth refused, owner stop removes only its bars, sort by order then id', function()
            local reg = H.createBarsRegistry({ warn = warnSpy, maxBars = 8 })

            -- Add valid bars
            assert.is_true(reg.add('res_a', { id = 'stamina', label = 'Stamina', icon = 'activity', value = 80, order = 10 }))
            assert.is_true(reg.add('res_a', { id = 'oxygen', label = 'Oxygen', icon = 'droplet', value = 100, order = 20 }))
            assert.are.equal(2, reg.count())

            -- Update existing bar: updates value/label and does NOT increase bar count
            assert.is_true(reg.add('res_a', { id = 'stamina', label = 'Stamina', icon = 'activity', value = 65, order = 10 }))
            assert.are.equal(2, reg.count())
            assert.are.equal(65, reg.get('stamina').value)

            -- nil value hides bar for now (marked hidden and filtered when visibleOnly = true)
            assert.is_true(reg.add('res_a', { id = 'oxygen', label = 'Oxygen', icon = 'droplet', value = nil, order = 20 }))
            assert.is_nil(reg.get('oxygen').value)
            assert.is_true(reg.get('oxygen').hidden)
            local visibleBars = reg.getSortedBars(true)
            assert.are.equal(1, #visibleBars)
            assert.are.equal('stamina', visibleBars[1].id)

            -- Reserved bar ids are refused
            assert.is_false(reg.add('res_a', { id = 'health', label = 'Health', icon = 'heart', value = 50 }))
            assert.is_false(reg.add('res_a', { id = 'armour', label = 'Armour', icon = 'shield', value = 50 }))
            assert.is_false(reg.add('res_a', { id = 'hunger', label = 'Hunger', icon = 'utensils', value = 50 }))
            assert.is_false(reg.add('res_a', { id = 'thirst', label = 'Thirst', icon = 'droplet', value = 50 }))
            assert.is_false(reg.add('res_a', { id = 'stress', label = 'Stress', icon = 'alert-triangle', value = 50 }))

            -- Refuse id already held by another owner
            assert.is_false(reg.add('res_b', { id = 'stamina', label = 'Stamina 2', icon = 'activity', value = 40 }))

            -- Fill up to 8 bars
            for i = 3, 8 do
                local id = 'bar_' .. tostring(i)
                assert.is_true(reg.add('res_b', { id = id, label = 'Bar ' .. i, icon = 'sliders', value = 50, order = 50 }))
            end
            assert.are.equal(8, reg.count())

            -- 9th distinct bar is refused with a warn
            local ok9 = reg.add('res_c', { id = 'bar_9', label = 'Bar 9', icon = 'sliders', value = 50, order = 50 })
            assert.is_false(ok9)
            assert.are.equal(8, reg.count())
            assert.is_true(#warnings >= 1)

            -- Owner stop removes only its bars
            local removedA = reg.removeByOwner('res_a')
            assert.are.equal(2, removedA)
            assert.are.equal(6, reg.count())
            assert.is_nil(reg.get('stamina'))
            assert.is_nil(reg.get('oxygen'))
            -- res_b bars remain
            assert.is_not_nil(reg.get('bar_3'))

            -- Clear res_b bars so slots are available for sorting test
            reg.removeByOwner('res_b')
            assert.are.equal(0, reg.count())

            -- Sorting by order then id
            assert.is_true(reg.add('res_x', { id = 'bravo', label = 'B', icon = 'check', value = 10, order = 5 }))
            assert.is_true(reg.add('res_x', { id = 'alpha', label = 'A', icon = 'check', value = 10, order = 5 }))
            assert.is_true(reg.add('res_x', { id = 'zulu', label = 'Z', icon = 'check', value = 10, order = 1 }))

            local sorted = reg.getSortedBars(false)
            -- First should be order 1 ('zulu')
            assert.are.equal('zulu', sorted[1].id)
            -- Next order 5 tie-broken by id: 'alpha' then 'bravo'
            assert.are.equal('alpha', sorted[2].id)
            assert.are.equal('bravo', sorted[3].id)
        end)
    end)

    describe('6. change detection (shared/logic/hud.lua)', function()
        local H
        before_each(function()
            natives.reset()
            H = load_hud_logic()
        end)

        it('identical values send no NUI message; changed values return diff', function()
            local v1 = {
                status = { health = 100, armour = 50 },
                vehicle = { speed = 0, gear = 'N' },
                street = { street = 'Grove St', zone = 'Davis', heading = 'N' },
            }

            -- Initial diff against nil reports changed
            local initChanged, initDiff = H.diffValues(nil, v1)
            assert.is_true(initChanged)
            assert.are.same(v1, initDiff)

            -- Identical values report false and nil diff
            local vSame = {
                status = { health = 100, armour = 50 },
                vehicle = { speed = 0, gear = 'N' },
                street = { street = 'Grove St', zone = 'Davis', heading = 'N' },
            }
            local sameChanged, sameDiff = H.diffValues(v1, vSame)
            assert.is_false(sameChanged)
            assert.is_nil(sameDiff)

            -- One field changed (speed 0 -> 25)
            local vChanged = {
                status = { health = 100, armour = 50 },
                vehicle = { speed = 25, gear = 'N' },
                street = { street = 'Grove St', zone = 'Davis', heading = 'N' },
            }
            local changed, diff = H.diffValues(v1, vChanged)
            assert.is_true(changed)
            assert.are.equal(25, diff.vehicle.speed)
            assert.is_nil(diff.status)
            assert.is_nil(diff.street)
        end)

        it('need disappearing emits null in diff for removed keys', function()
            local vWithNeed = {
                status = { health = 100, armour = 50, hunger = 80 },
                vehicle = { speed = 0, gear = 'N' },
                street = { street = 'Grove St', zone = 'Davis', heading = 'N' },
            }
            local vWithoutNeed = {
                status = { health = 100, armour = 50 },
                vehicle = { speed = 0, gear = 'N' },
                street = { street = 'Grove St', zone = 'Davis', heading = 'N' },
            }
            local changed, diff = H.diffValues(vWithNeed, vWithoutNeed)
            assert.is_true(changed)
            assert.is_not_nil(diff.status)
            assert.are.equal(H.NULL, diff.status.hunger)
        end)
    end)

    describe('7. settings validation and KVP round trip (shared/logic/hud.lua)', function()
        local H
        before_each(function()
            natives.reset()
            H = load_hud_logic()
        end)

        it('refuses unknown key or invalid value; round-trips valid settings', function()
            -- Valid keys
            assert.is_true(H.validateSetting('numbers', true))
            assert.is_true(H.validateSetting('numbers', false))
            assert.is_true(H.validateSetting('speedUnit', 'kmh'))
            assert.is_true(H.validateSetting('speedUnit', 'mph'))
            assert.is_true(H.validateSetting('minimapMode', 'always'))
            assert.is_true(H.validateSetting('minimapMode', 'vehicle'))
            assert.is_true(H.validateSetting('minimapMode', 'never'))

            -- Invalid values
            local okNumStr = H.validateSetting('numbers', 'true')
            assert.is_false(okNumStr)

            local okBadUnit = H.validateSetting('speedUnit', 'knots')
            assert.is_false(okBadUnit)

            local okBadMode = H.validateSetting('minimapMode', 'sometimes')
            assert.is_false(okBadMode)

            -- Unknown key
            local okUnknown = H.validateSetting('unsupportedKey', true)
            assert.is_false(okUnknown)

            -- Resolution and merging
            local resolved = H.resolveSettings({ numbers = true, speedUnit = 'mph' }, {
                numbers = false,
                speedUnit = 'kmh',
                minimapMode = 'always',
            })
            assert.is_true(resolved.numbers)
            assert.are.equal('mph', resolved.speedUnit)
            assert.are.equal('always', resolved.minimapMode)

            -- JSON KVP round trip simulation
            local encoded = json.encode(resolved)
            assert.is_string(encoded)
            local decoded = json.decode(encoded)
            assert.are.same(resolved, decoded)
        end)
    end)

    describe('8. resource script integration (loaded through fxmanifest.lua)', function()
        local resServer, resClient
        before_each(function()
            natives.reset({ side = 'client', resource = 'aeterna_hudkit' })
            natives.spy('SetNuiFocus')
            natives.spy('SetNuiFocusKeepInput')
            natives.spy('RegisterCommand')
            natives.spy('RegisterKeyMapping')
            natives.spy('RegisterNUICallback')
        end)

        it('loads server scripts and responds to aeterna_uikit:menu event', function()
            natives.reset({ side = 'server', resource = 'aeterna_hudkit' })
            local clientEventSent = nil
            local targetPlayer = nil

            natives.spy('TriggerClientEvent')
            -- 0.2: server/selftest.lua registers the self-tests with aeterna_core on start.
            natives.stub_export('aeterna_core', 'addSelftest', function() return true end)

            resServer = resource.load_resource(DIR, 'server')
            assert.is_not_nil(resServer)

            -- Fire aeterna_uikit:menu for aeterna_hudkit
            rawset(_G, 'source', 1)
            TriggerEvent('aeterna_uikit:menu', 1, { owner = 'aeterna_hudkit' })
            natives.advance(0)

            local calls = natives.calls('TriggerClientEvent')
            local found = false
            for _, c in ipairs(calls) do
                if c[1] == 'aeterna_hudkit:cl:settings' and c[2] == 1 then
                    found = true
                    break
                end
            end
            assert.is_true(found, 'expected aeterna_hudkit:cl:settings to be triggered on client')
        end)

        it('loads client scripts and registers commands and key mappings', function()
            natives.reset({ side = 'client', resource = 'aeterna_hudkit' })
            natives.spy('SetNuiFocus')
            natives.spy('SetNuiFocusKeepInput')
            natives.spy('RegisterCommand')
            natives.spy('RegisterKeyMapping')
            natives.spy('RegisterNUICallback')
            resClient = resource.load_resource(DIR, 'client')
            assert.is_not_nil(resClient)

            -- Check registered commands
            local commands = natives.registered_commands()
            assert.is_not_nil(commands['aeterna_hudkit_settings'])
            assert.is_not_nil(commands['+aeterna_hudkit_settings'])
            assert.is_not_nil(commands['-aeterna_hudkit_settings'])
        end)

        it('ready callback resets change-detection state, resends settings, bars, and part visibility', function()
            natives.reset({ side = 'client', resource = 'aeterna_hudkit' })
            natives.spy('SetNuiFocus')
            natives.spy('SetNuiFocusKeepInput')
            natives.spy('RegisterCommand')
            natives.spy('RegisterKeyMapping')
            local callbacks = {}
            natives.spy('RegisterNUICallback', function(name, fn)
                callbacks[name] = fn
            end)
            local uiMessages = natives.spy('SendNUIMessage')
            natives.stub_export('aeterna_core', 'themeHref', function() return nil end)
            natives.stub_export('aeterna_core', 'themePreset', function() return 'night-market' end)
            resClient = resource.load_resource(DIR, 'client')
            assert.is_function(callbacks['ready'])

            callbacks['ready']({
                sizes = {
                    status = { w = 220, h = 64 },
                    vehicle = { w = 180, h = 72 },
                    street = { w = 240, h = 48 },
                },
            }, function() end)

            -- live W3 2026-11-23: the theme preset never reached the HUD page
            local theme
            for _, call in ipairs(uiMessages) do
                if type(call[1]) == 'table' and call[1].type == 'aeterna:theme' then theme = call[1] end
            end
            assert.is_truthy(theme, 'expected aeterna:theme to be sent on ready')
            assert.are.equal('night-market', theme.preset)

            local foundSettingsApply = false
            local foundBars = false
            local foundVisible = false
            for _, call in ipairs(uiMessages) do
                local msg = call[1]
                if type(msg) == 'table' then
                    if msg.type == 'settings:apply' then
                        foundSettingsApply = true
                        assert.is_table(msg.settings)
                        assert.are.equal(20, msg.low)
                    elseif msg.type == 'hud:bars' then
                        foundBars = true
                    elseif msg.type == 'hud:visible' and msg.id == 'vehicle' then
                        foundVisible = true
                    end
                end
            end
            assert.is_true(foundSettingsApply, 'expected settings:apply to be sent on ready')
            assert.is_true(foundBars, 'expected hud:bars to be sent on ready')
            assert.is_true(foundVisible, 'expected hud:visible to be sent on ready')
        end)

        it('opens and closes settings with focus coordination via AeternaCore', function()
            natives.reset({ side = 'client', resource = 'aeterna_hudkit' })
            local focusCalls = natives.spy('SetNuiFocus')
            local keepCalls = natives.spy('SetNuiFocusKeepInput')
            natives.spy('RegisterCommand')
            natives.spy('RegisterKeyMapping')
            local callbacks = {}
            natives.spy('RegisterNUICallback', function(name, fn)
                callbacks[name] = fn
            end)
            natives.stub('AeternaCore', {
                log = { debug = function() end, info = function() end, warn = function() end, error = function() end },
                t = function(k) return (Locales and Locales.en and Locales.en[k]) or k end,
                lang = function() return 'en' end,
                kvp = {
                    get = function(_, _, default) return default end,
                    set = function() end,
                },
                key = function() end,
                requestFocus = function(opts)
                    local ok, tok = pcall(function() return exports.aeterna_core:requestFocus(opts) end)
                    if not ok or not tok then return nil end
                    local normalized = type(opts) == 'table' and opts or {}
                    SetNuiFocus(normalized.keyboard ~= false, normalized.cursor ~= false)
                    SetNuiFocusKeepInput(normalized.keepGameInput == true)
                    return tok
                end,
                releaseFocus = function(tok)
                    local ok, res = pcall(function() return exports.aeterna_core:releaseFocus(tok) end)
                    if ok and res == true then
                        SetNuiFocusKeepInput(false)
                        SetNuiFocus(false, false)
                        return true
                    end
                    return false
                end,
            })
            natives.stub_export('aeterna_core', 'requestFocus', function() return 'hud_tok' end)
            natives.stub_export('aeterna_core', 'releaseFocus', function() return true end)
            natives.stub_export('aeterna_core', 'themeHref', function() return nil end)

            resClient = resource.load_resource(DIR, 'client')

            -- Trigger settings open
            natives.fire('aeterna_hudkit:cl:settings')
            assert.are.equal(1, #focusCalls)
            assert.are.same({ n = 2, true, true }, focusCalls[1])
            assert.are.equal(1, #keepCalls)
            assert.are.same({ n = 1, false }, keepCalls[1])

            -- Close settings via NUI callback
            assert.is_function(callbacks['close'])
            callbacks['close']({}, function() end)
            assert.are.equal(2, #focusCalls)
            assert.are.same({ n = 2, false, false }, focusCalls[2])
            assert.are.equal(2, #keepCalls)
            assert.are.same({ n = 1, false }, keepCalls[2])
        end)
    end)
end)
