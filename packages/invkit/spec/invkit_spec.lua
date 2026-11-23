-- invkit_spec.lua -- aeterna_invkit: pure logic in shared/logic/invkit.lua + server/client resource harness tests.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

describe('aeterna_invkit', function()
    describe('1. stash id (shared/logic/invkit.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/invkit.lua'))()
        end)

        it('1a. builds character and account stash ids when qbx_core is started', function()
            local charId = L.stashId('character', {
                qbxStarted = true,
                citizenid = 'CIT9001',
                license = 'license:9f8e7d6c5b4a',
            })
            assert.are.equal('aeterna_stash:c:CIT9001', charId)

            local accId = L.stashId('account', {
                qbxStarted = true,
                citizenid = 'CIT9001',
                license = 'license:9f8e7d6c5b4a',
            })
            assert.are.equal('aeterna_stash:a:9f8e7d6c5b4a', accId)
        end)

        it('1b. uses license identifier for both scopes when qbx_core is not started', function()
            local charNoQbx = L.stashId('character', {
                qbxStarted = false,
                citizenid = 'CIT9001',
                license = 'license:9f8e7d6c5b4a',
            })
            assert.are.equal('aeterna_stash:c:9f8e7d6c5b4a', charNoQbx)

            local accNoQbx = L.stashId('account', {
                qbxStarted = false,
                citizenid = nil,
                license = 'license:9f8e7d6c5b4a',
            })
            assert.are.equal('aeterna_stash:a:9f8e7d6c5b4a', accNoQbx)
        end)

        it('1c. rejects unknown scope or missing player identifiers', function()
            local badScope, errScope = L.stashId('clan', {
                qbxStarted = true,
                citizenid = 'CIT9001',
                license = 'license:9f8e7d6c5b4a',
            })
            assert.is_nil(badScope)
            assert.is_truthy(errScope)

            local missingId, errId = L.stashId('character', {
                qbxStarted = false,
                citizenid = nil,
                license = nil,
            })
            assert.is_nil(missingId)
            assert.is_truthy(errId)
        end)
    end)

    describe('2. distance check (shared/logic/invkit.lua)', function()
        local L, points
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/invkit.lua'))()
            points = {
                { coords = vector3(100.0, 200.0, 30.0), radius = 2.0 },
                { coords = vector3(-50.0, -60.0, 10.0), radius = 3.5 },
            }
        end)

        it('2a. passes when player is inside radius of a configured point', function()
            local ok, err = L.canOpenAt(vector3(101.0, 200.5, 30.0), points, false)
            assert.is_true(ok)
            assert.is_nil(err)

            -- Exact boundary passes
            local okEdge = L.canOpenAt(vector3(102.0, 200.0, 30.0), points, false)
            assert.is_true(okEdge)
        end)

        it('2b. fails when player is outside radius of all configured points', function()
            local ok, err = L.canOpenAt(vector3(103.0, 200.0, 30.0), points, false)
            assert.is_false(ok)
            assert.are.equal('invkit.stash.far', err)
        end)

        it('2c. fails when no points are configured unless anywhere is true', function()
            local okEmpty, errEmpty = L.canOpenAt(vector3(0.0, 0.0, 0.0), {}, false)
            assert.is_false(okEmpty)
            assert.are.equal('invkit.stash.far', errEmpty)

            local okAnywhere, errAnywhere = L.canOpenAt(vector3(9999.0, 9999.0, 0.0), {}, true)
            assert.is_true(okAnywhere)
            assert.is_nil(errAnywhere)
        end)

        it('2d. reads vector3 values through an injectable type function', function()
            local fake = { x = 100.0, y = 200.0, z = 30.0 }
            local typeFn = function(v)
                if v == fake then return 'vector3' end
                return type(v)
            end

            assert.are.same({ x = 100.0, y = 200.0, z = 30.0 }, L.readVec3(fake, typeFn))

            local ok, err = L.canOpenAt(fake, points, false, typeFn)
            assert.is_true(ok)
            assert.is_nil(err)

            local okNorm, errNorm, normalized = L.normalizeVec3(fake, 'prop.pos', typeFn)
            assert.is_true(okNorm)
            assert.is_nil(errNorm)
            assert.are.same({ x = 100.0, y = 200.0, z = 30.0 }, normalized)
        end)
    end)

    describe('3. use state machine (shared/logic/invkit.lua)', function()
        local L, clock, usedEvents, refusedEvents, clientStarts, sm
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/invkit.lua'))()
            clock = 1000
            usedEvents = {}
            refusedEvents = {}
            clientStarts = {}
            sm = L.createUseManager({
                now = function() return clock end,
                onStartClient = function(src, payload)
                    clientStarts[#clientStarts + 1] = { src = src, payload = payload }
                end,
                onRefused = function(src, payload)
                    refusedEvents[#refusedEvents + 1] = { src = src, payload = payload }
                end,
                onUsed = function(src, payload)
                    usedEvents[#usedEvents + 1] = { src = src, payload = payload }
                end,
            })
            assert(sm:registerUsable('needs_res', 'water', {
                label = 'Drink water',
                duration = 2000,
                consume = 1,
                cancelable = true,
                ask = false,
            }))
        end)

        it('3a. refuses done too early and passes done once after duration - 250 ms', function()
            local okStart, useId = sm:startUse(1, 'water', 3)
            assert.is_true(okStart)
            assert.is_string(useId)
            assert.are.equal(1, #clientStarts)

            -- Too early (1500 ms < 2000 - 250 = 1750 ms)
            clock = 2500
            local okEarly = sm:done(1, useId)
            assert.is_false(okEarly)
            assert.are.equal(0, #usedEvents)

            -- At duration - 250 ms (1750 ms elapsed): passes once
            clock = 2750
            local okDone, res = sm:done(1, useId)
            assert.is_true(okDone)
            assert.are.same({
                owner = 'needs_res',
                item = 'water',
                slot = 3,
                count = 1,
            }, res)
            assert.are.equal(1, #usedEvents)

            -- Second done for the same useId is refused
            clock = 3000
            local okAgain = sm:done(1, useId)
            assert.is_false(okAgain)
            assert.are.equal(1, #usedEvents)
        end)

        it('3b. refuses a second start while one is pending for the same player', function()
            local ok1, useId1 = sm:startUse(1, 'water', 1)
            assert.is_true(ok1)
            assert.is_string(useId1)

            local ok2, err2 = sm:startUse(1, 'water', 2)
            assert.is_false(ok2)
            assert.are.equal('invkit.use.busy', err2)
            assert.are.equal(1, #refusedEvents)
            assert.are.same({ item = 'water', reason = 'invkit.use.busy' }, refusedEvents[1].payload)
        end)

        it('3c. cancel clears the pending use so nothing is taken', function()
            local okStart, useId = sm:startUse(1, 'water', 2)
            assert.is_true(okStart)

            assert.is_true(sm:cancel(1, useId))

            clock = 4000
            assert.is_false(sm:done(1, useId))
            assert.are.equal(0, #usedEvents)

            -- Player can start another use after cancelling
            local okRestart = sm:startUse(1, 'water', 2)
            assert.is_true(okRestart)
        end)

        it('3d. owner stop clears its registered entries and pending uses', function()
            assert(sm:registerUsable('other_res', 'sandwich', { label = 'Eat', duration = 1500 }))
            local okStart, useId = sm:startUse(1, 'water', 1)
            assert.is_true(okStart)

            sm:removeByOwner('needs_res')

            assert.is_nil(sm:getUsable('water'))
            assert.is_not_nil(sm:getUsable('sandwich'))

            clock = 4000
            assert.is_false(sm:done(1, useId))
            assert.is_false(sm:startUse(1, 'water', 1))
            assert.is_true(sm:startUse(1, 'sandwich', 1))
        end)

        it('3e. server cancel clears a pending use even when it is not cancelable', function()
            assert(sm:registerUsable('needs_res', 'locked', {
                label = 'Locked item',
                duration = 2000,
                cancelable = false,
            }))
            local okStart, useId = sm:startUse(1, 'locked', 1)
            assert.is_true(okStart)

            assert.is_true(sm:cancel(1, useId))
            assert.is_nil(sm:getPending(1))

            clock = 4000
            assert.is_false(sm:done(1, useId))
            assert.are.equal(0, #usedEvents)
            assert.is_true(sm:startUse(1, 'water', 1))
        end)

        it('3f. expires a running use at duration + 5000 ms so the player is not stuck busy', function()
            local okStart, useId = sm:startUse(1, 'water', 1)
            assert.is_true(okStart)

            -- Started at 1000 ms with duration 2000 ms: expires at 8000 ms.
            clock = 7999
            sm:checkTimeouts()
            assert.is_not_nil(sm:getPending(1))

            clock = 8000
            sm:checkTimeouts()
            assert.is_nil(sm:getPending(1))

            clock = 8001
            assert.is_false(sm:done(1, useId))
            assert.is_true(sm:startUse(1, 'water', 1))
        end)
    end)

    describe('4. registerUsable validation (shared/logic/invkit.lua)', function()
        local L, sm
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/invkit.lua'))()
            sm = L.createUseManager()
        end)

        it('4a. rejects a def holding a function at top-level or nested', function()
            local okTop, errTop = sm:registerUsable('res_a', 'water', {
                label = 'Water',
                duration = 2000,
                callback = function() end,
            })
            assert.is_false(okTop)
            assert.is_truthy(errTop and errTop:match('function'))

            local okNested, errNested = sm:registerUsable('res_a', 'water', {
                label = 'Water',
                duration = 2000,
                anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle', fn = function() end },
            })
            assert.is_false(okNested)
            assert.is_truthy(errNested and errNested:match('function'))
        end)

        it('4b. rejects a duration outside 300-60000 ms', function()
            local okLow, errLow = sm:registerUsable('res_a', 'water', {
                label = 'Water',
                duration = 299,
            })
            assert.is_false(okLow)
            assert.is_truthy(errLow and errLow:match('duration'))

            local okHigh, errHigh = sm:registerUsable('res_a', 'water', {
                label = 'Water',
                duration = 60001,
            })
            assert.is_false(okHigh)
            assert.is_truthy(errHigh and errHigh:match('duration'))

            assert.is_true(sm:registerUsable('res_a', 'quick_pill', { label = 'Pill', duration = 300 }))
            assert.is_true(sm:registerUsable('res_a', 'long_repair', { label = 'Repair', duration = 60000 }))
        end)

        it('4c. rejects a non-positive or non-integer consume', function()
            local okZero, errZero = sm:registerUsable('res_a', 'water', {
                label = 'Water',
                duration = 2000,
                consume = 0,
            })
            assert.is_false(okZero)
            assert.is_truthy(errZero and errZero:match('consume'))

            local okNeg, errNeg = sm:registerUsable('res_a', 'water', {
                label = 'Water',
                duration = 2000,
                consume = -2,
            })
            assert.is_false(okNeg)
            assert.is_truthy(errNeg and errNeg:match('consume'))

            local okFrac = sm:registerUsable('res_a', 'water', {
                label = 'Water',
                duration = 2000,
                consume = 0.5,
            })
            assert.is_false(okFrac)
        end)
    end)

    describe('5. ask = true flow (shared/logic/invkit.lua)', function()
        local L, clock, askedEvents, refusedEvents, clientStarts, sm
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/invkit.lua'))()
            clock = 5000
            askedEvents = {}
            refusedEvents = {}
            clientStarts = {}
            sm = L.createUseManager({
                now = function() return clock end,
                onAsk = function(src, payload)
                    askedEvents[#askedEvents + 1] = { src = src, payload = payload }
                end,
                onStartClient = function(src, payload)
                    clientStarts[#clientStarts + 1] = { src = src, payload = payload }
                end,
                onRefused = function(src, payload)
                    refusedEvents[#refusedEvents + 1] = { src = src, payload = payload }
                end,
            })
            assert(sm:registerUsable('med_res', 'bandage', {
                label = 'Apply bandage',
                duration = 3000,
                consume = 1,
                ask = true,
            }))
        end)

        it('5a. denies and sends cl:refused when no answer arrives within 1000 ms, and ignores late allowUse', function()
            local ok, useId = sm:startUse(1, 'bandage', 4)
            assert.is_true(ok)
            assert.are.equal(1, #askedEvents)
            assert.are.same({
                owner = 'med_res',
                item = 'bandage',
                slot = 4,
                useId = useId,
            }, askedEvents[1].payload)
            assert.are.equal(0, #clientStarts)

            -- 999 ms: still waiting
            clock = 5999
            sm:checkTimeouts()
            assert.are.equal(0, #refusedEvents)

            -- 1000 ms without answer: denied and cl:refused sent
            clock = 6000
            sm:checkTimeouts()
            assert.are.equal(1, #refusedEvents)
            assert.are.equal(1, refusedEvents[1].src)
            assert.are.equal('bandage', refusedEvents[1].payload.item)
            assert.is_string(refusedEvents[1].payload.reason)

            -- Late allowUse with stale useId is ignored
            assert.is_false(sm:allowUse(useId))
            assert.are.equal(0, #clientStarts)
        end)

        it('5b. ignores allowUse with a stale or unknown useId, and starts client on timely allowUse', function()
            assert.is_false(sm:allowUse('u_nonexistent'))

            local ok, useId = sm:startUse(1, 'bandage', 2)
            assert.is_true(ok)

            clock = 5200
            assert.is_true(sm:allowUse(useId))
            assert.are.equal(1, #clientStarts)
            assert.are.equal(useId, clientStarts[1].payload.useId)

            -- Second allowUse with the same useId is now stale and ignored
            assert.is_false(sm:allowUse(useId))
            assert.are.equal(1, #clientStarts)
        end)

        it('5c. sends cl:refused with owner reasonKey on denyUse and ignores subsequent allowUse', function()
            local ok, useId = sm:startUse(2, 'bandage', 1)
            assert.is_true(ok)

            clock = 5100
            assert.is_true(sm:denyUse(useId, 'med.already_full'))
            assert.are.equal(1, #refusedEvents)
            assert.are.equal(2, refusedEvents[1].src)
            assert.are.same({
                item = 'bandage',
                reason = 'med.already_full',
            }, refusedEvents[1].payload)

            assert.is_false(sm:allowUse(useId))
            assert.are.equal(0, #clientStarts)
        end)
    end)

    describe('6. resource scripts under harness', function()
        it('6a. server: logs one warn when ox_inventory is not started and does nothing', function()
            natives.reset({ resource = 'aeterna_invkit', side = 'server', invoker = 'house_res' })
            local warns = {}
            natives.stub('GetResourceState', function() return 'missing' end)
            natives.stub('AeternaCore', {
                log = {
                    debug = function() end,
                    info = function() end,
                    warn = function(msg) warns[#warns + 1] = msg end,
                    error = function() end,
                },
                t = function(k) return (Locales and Locales.en and Locales.en[k]) or k end,
                lang = function() return 'en' end,
                rateLimit = function() return true end,
            })

            natives.spy('RegisterCommand')
            -- 0.2: server/selftest.lua registers the self-tests with aeterna_core on start.
            natives.stub_export('aeterna_core', 'addSelftest', function() return true end)

            local res = resource.load_resource(DIR, 'server')
            assert.are.equal(1, #warns)

            -- Subsequent calls do not log duplicate warnings and do nothing
            assert.is_false(res.exports.openStash(1))
            natives.fire_net('aeterna_invkit:sv:open', 1)
            assert.are.equal(1, #warns)
        end)

        it('6b. server: opens stashes, checks distance, and runs usable item flow with ox_inventory', function()
            natives.reset({
                resource = 'aeterna_invkit',
                side = 'server',
                invoker = 'needs_res',
                convars = { aeterna_core_log_level = 'error' },
            })
            local registeredStashes = {}
            local forcedOpens = {}
            local removedItems = {}
            local itemCounts = { [1] = { water = 2, medkit = 1 } }
            local hookFn = nil
            local oxStarted = true
            local forceOpenResult = true
            local hookRegistrations = 0
            local removeHooksCalls = 0

            natives.stub('GetResourceState', function(name)
                if name == 'ox_inventory' then
                    return oxStarted and 'started' or 'missing'
                end
                if name == 'qbx_core' then
                    return 'started'
                end
                return 'missing'
            end)
            natives.stub('GetPlayerIdentifiers', function(src)
                return { 'license:lic_' .. tostring(src) }
            end)
            natives.stub('GetPlayerPed', function(src) return tonumber(src) end)
            natives.spy('RegisterCommand')

            natives.stub_export('qbx_core', 'GetPlayer', function(src)
                return { PlayerData = { citizenid = 'CID_' .. tostring(src) } }
            end)
            natives.stub_export('ox_inventory', 'RegisterStash', function(id, label, slots, maxWeight, owner)
                registeredStashes[#registeredStashes + 1] = {
                    id = id, label = label, slots = slots, maxWeight = maxWeight, owner = owner,
                }
            end)
            natives.stub_export('ox_inventory', 'forceOpenInventory', function(src, invType, id)
                forcedOpens[#forcedOpens + 1] = { src = src, invType = invType, id = id }
                if forceOpenResult then return id end
                return nil
            end)
            natives.stub_export('ox_inventory', 'registerHook', function(eventName, fn, opts)
                if eventName == 'usingItem' then
                    hookFn = fn
                    hookRegistrations = hookRegistrations + 1
                end
                return hookRegistrations
            end)
            natives.stub_export('ox_inventory', 'removeHooks', function()
                removeHooksCalls = removeHooksCalls + 1
            end)
            natives.stub_export('ox_inventory', 'GetItemCount', function(src, item)
                return (itemCounts[tonumber(src)] and itemCounts[tonumber(src)][item]) or 0
            end)
            natives.stub_export('ox_inventory', 'RemoveItem', function(src, item, count, metadata, slot)
                local s = tonumber(src)
                local cur = (itemCounts[s] and itemCounts[s][item]) or 0
                if cur < count then return false end
                itemCounts[s][item] = cur - count
                removedItems[#removedItems + 1] = { src = s, item = item, count = count, metadata = metadata, slot = slot }
                return true
            end)

            -- 0.2: server/selftest.lua registers the self-tests with aeterna_core on start.
            natives.stub_export('aeterna_core', 'addSelftest', function() return true end)
            local res = resource.load_resource(DIR, 'server', {
                externals = { ['@aeterna_core/import.lua'] = DIR .. '/../core/import.lua' },
            })
            local api = res.exports

            assert.are.equal('aeterna_stash:c:CID_1', api.stashId(1, 'character'))
            assert.are.equal('aeterna_stash:a:lic_1', api.stashId(1, 'account'))

            -- openStash registers on first open only, and bypasses distance check
            assert.is_true(api.openStash(1))
            assert.is_true(api.openStash(1))
            assert.are.equal(1, #registeredStashes)
            assert.are.equal('aeterna_stash:c:CID_1', registeredStashes[1].id)
            assert.are.equal(2, #forcedOpens)

            -- Distance check on net event aeterna_invkit:sv:open
            Config.stash.points = { { coords = vector3(10.0, 20.0, 30.0), radius = 2.0 } }
            natives.set_entity_coords(1, vector3(50.0, 50.0, 30.0))
            natives.fire_net('aeterna_invkit:sv:open', 1)
            local refEv = natives.last_emitted('client', 'aeterna_invkit:cl:refused')
            assert.is_truthy(refEv)
            assert.are.equal('invkit.stash.far', refEv.args[1].reason)

            natives.set_entity_coords(1, vector3(10.5, 20.0, 30.0))
            natives.fire_net('aeterna_invkit:sv:open', 1)
            assert.are.equal(3, #forcedOpens)

            -- Item use flow via ox_inventory hook
            assert.is_true(api.registerUsable('water', {
                label = 'Drink water',
                duration = 2000,
                consume = 1,
                cancelable = true,
                ask = false,
            }))
            assert.is_function(hookFn)

            -- The positional hook shape is not part of the ox_inventory contract and is ignored.
            local clUseCount = #natives.emitted('client', 'aeterna_invkit:cl:use')
            local oldShapeRes = hookFn(2, { name = 'water', slot = 9 }, 9)
            assert.is_nil(oldShapeRes)
            assert.are.equal(clUseCount, #natives.emitted('client', 'aeterna_invkit:cl:use'))

            local hookRes = hookFn({
                source = 1,
                inventoryId = 'player',
                item = { name = 'water', slot = 2, metadata = nil },
                consume = 1,
            })
            assert.is_false(hookRes)

            local clUse = natives.last_emitted('client', 'aeterna_invkit:cl:use')
            assert.is_truthy(clUse)
            local useId = clUse.args[1].useId

            natives.advance(1800)
            natives.fire_net('aeterna_invkit:sv:done', 1, { useId = useId })
            assert.are.equal(1, #removedItems)
            assert.are.same({ src = 1, item = 'water', count = 1, metadata = nil, slot = 2 }, removedItems[1])

            local usedEv = natives.last_emitted('local', 'aeterna_invkit:used')
            assert.is_truthy(usedEv)
            assert.are.equal(1, usedEv.args[1])
            assert.are.same({ owner = 'needs_res', item = 'water', slot = 2, count = 1 }, usedEv.args[2])

            -- Spamming done removes no extra items
            natives.fire_net('aeterna_invkit:sv:done', 1, { useId = useId })
            assert.are.equal(1, #removedItems)

            -- ask = true timeout via SetTimeout on server
            assert.is_true(api.registerUsable('medkit', {
                label = 'Use medkit',
                duration = 2500,
                consume = 1,
                ask = true,
            }))
            hookFn({
                source = 1,
                inventoryId = 'player',
                item = { name = 'medkit', slot = 3, metadata = nil },
                consume = 1,
            })
            local askEv = natives.last_emitted('local', 'aeterna_invkit:asking')
            assert.is_truthy(askEv)
            local askUseId = askEv.args[2].useId
            natives.advance(1000)
            local timeoutRef = natives.last_emitted('client', 'aeterna_invkit:cl:refused')
            assert.is_truthy(timeoutRef)
            assert.are.equal('medkit', timeoutRef.args[1].item)
            assert.is_false(api.allowUse(askUseId))

            -- A running use expires after duration + 5000 ms, freeing the player.
            assert.is_true(api.registerUsable('quick', {
                label = 'Quick item',
                duration = 300,
                consume = 1,
                ask = false,
            }))
            hookFn({
                source = 1,
                inventoryId = 'player',
                item = { name = 'quick', slot = 5, metadata = nil },
                consume = 1,
            })
            local quickUse = natives.last_emitted('client', 'aeterna_invkit:cl:use')
            assert.is_truthy(quickUse)
            local quickUseId = quickUse.args[1].useId
            local quickStarts = #natives.emitted('client', 'aeterna_invkit:cl:use')

            natives.advance(5300)

            hookFn({
                source = 1,
                inventoryId = 'player',
                item = { name = 'quick', slot = 5, metadata = nil },
                consume = 1,
            })
            assert.are.equal(quickStarts + 1, #natives.emitted('client', 'aeterna_invkit:cl:use'))
            assert.are.not_equal(quickUseId, natives.last_emitted('client', 'aeterna_invkit:cl:use').args[1].useId)

            -- Only a truthy forceOpenInventory result counts as success.
            forceOpenResult = false
            assert.is_false(api.openStash(1))
            forceOpenResult = true
            assert.is_true(api.openStash(1))

            -- ox_inventory stop clears the stash cache and hook state.
            local hookRegsBeforeRestart = hookRegistrations
            local removeCallsBeforeRestart = removeHooksCalls
            oxStarted = false
            natives.fire('onResourceStop', 'ox_inventory')
            oxStarted = true
            assert.is_true(api.openStash(1))
            assert.are.equal(2, #registeredStashes)

            -- ox_inventory start clears both again and resyncs the hook.
            natives.fire('onResourceStart', 'ox_inventory')
            assert.are.equal(hookRegsBeforeRestart + 1, hookRegistrations)
            assert.are.equal(removeCallsBeforeRestart, removeHooksCalls)
            assert.is_true(api.openStash(1))
            assert.are.equal(3, #registeredStashes)
        end)

        it('6c. client: shows keyHints near point and runs uikit progress on cl:use', function()
            natives.reset({
                resource = 'aeterna_invkit',
                side = 'client',
                convars = { aeterna_core_log_level = 'error' },
            })
            local hintsShown = {}
            local hintsCleared = 0
            local progressResult = true

            natives.spy('RegisterCommand')
            natives.spy('RegisterKeyMapping')
            natives.spy('BeginTextCommandThefeedPost')
            natives.spy('AddTextComponentSubstringPlayerName')
            natives.spy('EndTextCommandThefeedPostTicker')
            natives.stub_export('aeterna_uikit', 'keyHints', function(list)
                hintsShown[#hintsShown + 1] = list
            end)
            natives.stub_export('aeterna_uikit', 'clearKeyHints', function()
                hintsCleared = hintsCleared + 1
            end)
            natives.stub_export('aeterna_uikit', 'progress', function()
                return progressResult
            end)

            resource.load_resource(DIR, 'client', {
                externals = { ['@aeterna_core/import.lua'] = DIR .. '/../core/import.lua' },
            })

            Config.stash.points = { { coords = vector3(10.0, 10.0, 10.0), radius = 2.0 } }
            natives.set_entity_coords(1, vector3(10.5, 10.0, 10.0))
            natives.advance(600)
            assert.are.equal(1, #hintsShown)
            assert.are.equal('+aeterna_invkit_open', hintsShown[1][1].key)

            natives.set_entity_coords(1, vector3(50.0, 50.0, 10.0))
            natives.advance(600)
            assert.are.equal(1, hintsCleared)

            -- cl:use finished -> sends sv:done
            progressResult = true
            natives.fire_net('aeterna_invkit:cl:use', 1, {
                useId = 'u1',
                label = 'Drink water',
                duration = 2000,
                cancelable = true,
            })
            local doneEv = natives.last_emitted('server', 'aeterna_invkit:sv:done')
            assert.is_truthy(doneEv)
            assert.are.equal('u1', doneEv.args[1].useId)

            -- cl:use cancelled -> sends sv:cancel
            progressResult = false
            natives.fire_net('aeterna_invkit:cl:use', 1, {
                useId = 'u2',
                label = 'Drink water',
                duration = 2000,
                cancelable = true,
            })
            local cancelEv = natives.last_emitted('server', 'aeterna_invkit:sv:cancel')
            assert.is_truthy(cancelEv)
            assert.are.equal('u2', cancelEv.args[1].useId)

            -- cl:refused shows the translated reason through the base game feed.
            natives.fire_net('aeterna_invkit:cl:refused', 1, {
                item = 'water',
                reason = 'invkit.use.busy',
            })
            local beginCalls = natives.calls('BeginTextCommandThefeedPost')
            assert.are.equal(1, #beginCalls)
            assert.are.equal('STRING', beginCalls[1][1])
            local textCalls = natives.calls('AddTextComponentSubstringPlayerName')
            assert.are.equal(1, #textCalls)
            assert.are.equal('Already using an item', textCalls[1][1])
            local endCalls = natives.calls('EndTextCommandThefeedPostTicker')
            assert.are.equal(1, #endCalls)
            assert.are.equal(false, endCalls[1][1])
            assert.are.equal(false, endCalls[1][2])
        end)
    end)
end)
