-- phone_spec.lua -- aeterna_invkit 0.2 phone item mode: pure logic in shared/logic/phone.lua and the
-- server scripts under the devkit harness with a fake ox_inventory (docs/specs/aeterna_invkit.md, Tests 0.2).

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local SHIPPED_ITEMS = {
    phone = 'slab',
    phone_keypad = 'keypad', phone_burner = 'burner', phone_qwerty = 'qwerty', phone_slab = 'slab',
    phone_fold = 'fold', phone_pro = 'pro', phone_book = 'book', phone_pad = 'pad',
}

local function loadLogic()
    natives.reset()
    return assert(loadfile(DIR .. '/shared/logic/phone.lua'))()
end

-- Fake ox_inventory 2.44.0 server exports used by invkit 0.2. inv[src][slot] = { name, slot, count, metadata }.
local function fakeOx(inv)
    local ox = { inv = inv, writes = {}, hooks = {}, hookOpts = {}, removed = {}, started = true, nextHook = 0 }

    natives.stub_export('ox_inventory', 'Search', function(src, search, names)
        assert(search == 'slots', 'invkit only searches slots')
        local items = inv[tonumber(src)]
        if not items then return false end
        if type(names) == 'string' then names = { names } end
        local out = {}
        for _, name in ipairs(names) do
            out[name] = {}
            for _, slot in pairs(items) do
                if slot.name == name then
                    slot.metadata = slot.metadata or {}
                    out[name][#out[name] + 1] = slot
                end
            end
        end
        if #names == 1 then return out[names[1]] end
        return out
    end)
    natives.stub_export('ox_inventory', 'GetSlot', function(src, slot)
        local items = inv[tonumber(src)]
        return items and items[slot] or nil
    end)
    natives.stub_export('ox_inventory', 'SetMetadata', function(src, slot, metadata)
        local items = inv[tonumber(src)]
        local item = items and items[slot]
        if not item then return end
        item.metadata = metadata
        ox.writes[#ox.writes + 1] = { src = tonumber(src), slot = slot, metadata = metadata }
    end)
    natives.stub_export('ox_inventory', 'registerHook', function(event, fn, opts)
        ox.nextHook = ox.nextHook + 1
        ox.hooks[event] = fn
        ox.hookOpts[event] = opts
        return ox.nextHook
    end)
    natives.stub_export('ox_inventory', 'removeHooks', function(id)
        ox.removed[#ox.removed + 1] = id
    end)
    return ox
end

-- Boot the server side of aeterna_invkit with a stubbed Config (config.lua skipped) and a fake ox.
local function boot(opts)
    opts = opts or {}
    natives.reset({ resource = 'aeterna_invkit', side = 'server', invoker = 'aeterna_phonekit' })
    local warns, debugs = {}, {}
    local ox = fakeOx(opts.inv or {})
    for id in pairs(opts.inv or {}) do
        if type(id) == 'number' then natives.add_player(id, 'player' .. id) end
    end
    if opts.oxStarted == false then ox.started = false end

    natives.stub('GetResourceState', function(name)
        if name == 'ox_inventory' then return ox.started and 'started' or 'missing' end
        return 'missing'
    end)
    natives.stub('AeternaCore', {
        log = {
            debug = function(msg, fields) debugs[#debugs + 1] = { msg = msg, fields = fields } end,
            info = function() end,
            warn = function(msg, fields) warns[#warns + 1] = { msg = msg, fields = fields } end,
            error = function() end,
        },
        t = function(k) return k end,
        lang = function() return 'en' end,
        rateLimit = function() return true end,
    })
    natives.stub('Config', {
        stash = { scope = 'character', slots = 40, maxWeight = 100000, label = 'invkit.stash.label', points = {} },
        phone = {
            enabled = opts.enabled ~= false,
            items = opts.items or SHIPPED_ITEMS,
        },
    })
    natives.spy('RegisterCommand')

    local res = resource.load_resource(DIR, 'server', { skip = { ['config.lua'] = true } })
    return { res = res, ox = ox, warns = warns, debugs = debugs }
end

-- Fire playerDropped as FXServer does: `source` is the leaving player.
local function drop(src)
    local prev = rawget(_G, 'source')
    rawset(_G, 'source', src)
    natives.fire('playerDropped', 'quit')
    rawset(_G, 'source', prev)
end

local function ask(src, checkId, devices)
    natives.fire('aeterna_phonekit:asking', src, { checkId = checkId, devices = devices or 'items' })
    local ev = natives.last_emitted('local', 'aeterna_phonekit:answer')
    if not ev or ev.args[1] ~= checkId then return nil end
    return ev.args[2]
end

local function save(src, data)
    natives.fire('aeterna_phonekit:deviceSave', src, data)
end

local function changedFor(src)
    local n = 0
    for _, ev in ipairs(natives.emitted('local', 'aeterna_phonekit:devicesChanged')) do
        if ev.args[1] == src then n = n + 1 end
    end
    return n
end

describe('aeterna_invkit 0.2 phone items', function()
    describe('1. item map (shared/logic/phone.lua)', function()
        it('1a. the shipped Config.phone.items passes with nothing skipped', function()
            local P = loadLogic()
            local env = setmetatable({}, { __index = _G })
            assert(loadfile(DIR .. '/config.lua', 't', env))()
            assert.are.same(SHIPPED_ITEMS, env.Config.phone.items)
            assert.is_false(env.Config.phone.enabled)

            local map, skipped = P.validateItemMap(env.Config.phone.items)
            assert.are.same(SHIPPED_ITEMS, map)
            assert.are.equal(0, #skipped)
        end)

        it('1b. an unknown model, a bad name, a 65-char name and a 33rd entry are skipped', function()
            local P = loadLogic()
            local items = {}
            -- 32 'pNN' names plus one valid 64-char name: 33 valid entries, so the last in name order (p32) is skipped.
            for i = 1, 32 do items[('p%02d'):format(i)] = 'slab' end
            items['zz_brick'] = 'brick'
            items['bad name!'] = 'slab'
            items[string.rep('a', 65)] = 'slab'
            items[string.rep('b', 64)] = 'pad'

            local map, skipped = P.validateItemMap(items)
            local count = 0
            for _ in pairs(map) do count = count + 1 end
            assert.are.equal(32, count)
            assert.are.equal('pad', map[string.rep('b', 64)])
            assert.is_nil(map.zz_brick)
            assert.is_nil(map['bad name!'])
            assert.is_nil(map[string.rep('a', 65)])
            assert.is_nil(map.p32)
            assert.are.equal('slab', map.p31)
            assert.are.equal(4, #skipped)
        end)

        it('1c. the server logs exactly one warn at start for the skipped entries', function()
            local items = { phone = 'slab', zz_brick = 'brick', ['bad name!'] = 'slab', [string.rep('a', 65)] = 'slab' }
            for i = 1, 32 do items[('p%02d'):format(i)] = 'fold' end
            local b = boot({ items = items })
            assert.are.equal(1, #b.warns)
        end)
    end)

    describe('2. answer', function()
        it('2a. two phones give two entries with their phoneId serials and models, lowest slot first', function()
            local b = boot({ inv = { [1] = {
                [3] = { name = 'phone_fold', slot = 3, count = 1, metadata = { phoneId = 'aaaa0001' } },
                [1] = { name = 'phone', slot = 1, count = 1, metadata = { phoneId = 'bbbb0002' } },
                [2] = { name = 'water', slot = 2, count = 4, metadata = {} },
            } } })
            local answer = ask(1, 'chk1')
            assert.is_truthy(answer)
            assert.is_true(answer.allow)
            assert.are.same({
                { id = 'bbbb0002', model = 'slab' },
                { id = 'aaaa0001', model = 'fold' },
            }, answer.devices)
            assert.are.equal(0, #b.ox.writes)
        end)

        it('2b. a phone without phoneId gets one written once and keeps it on the next answer', function()
            local b = boot({ inv = { [1] = {
                [4] = { name = 'phone_pro', slot = 4, count = 1, metadata = { color = 1, label = 'Mine' } },
            } } })
            local first = ask(1, 'chk1')
            assert.are.equal(1, #first.devices)
            local id = first.devices[1].id
            assert.is_truthy(id:match('^[0-9a-f]+$'))
            assert.are.equal(8, #id)
            assert.are.equal(1, #b.ox.writes)
            assert.are.equal(4, b.ox.writes[1].slot)
            assert.are.same({ phoneId = id, color = 1, label = 'Mine' }, b.ox.writes[1].metadata)

            local second = ask(1, 'chk2')
            assert.are.equal(id, second.devices[1].id)
            assert.are.equal(1, #b.ox.writes)
        end)

        it('2c. two new phones never get the same serial', function()
            local P = loadLogic()
            local values = { 0xdeadbeef, 0xdeadbeef, 0x00c0ffee }
            local i = 0
            local rng = function() i = i + 1; return values[i] end
            local slots = {
                { name = 'phone', slot = 1, metadata = {} },
                { name = 'phone_fold', slot = 2, metadata = {} },
            }
            local devices, writes = P.buildDevices(slots, SHIPPED_ITEMS, rng)
            assert.are.equal('deadbeef', devices[1].id)
            assert.are.equal('00c0ffee', devices[2].id)
            assert.are.equal(2, #writes)

            local b = boot({ inv = { [1] = {
                [1] = { name = 'phone', slot = 1, count = 1, metadata = {} },
                [2] = { name = 'phone_slab', slot = 2, count = 1, metadata = {} },
            } } })
            local answer = ask(1, 'chk1')
            assert.are.equal(2, #answer.devices)
            assert.are_not.equal(answer.devices[1].id, answer.devices[2].id)
        end)

        it('2d. nine phones give the eight lowest slots', function()
            local items = {}
            for _, slot in ipairs({ 9, 2, 7, 1, 5, 3, 8, 4, 6 }) do
                items[slot] = { name = 'phone_keypad', slot = slot, count = 1, metadata = { phoneId = ('id%06d'):format(slot) } }
            end
            boot({ inv = { [1] = items } })
            local answer = ask(1, 'chk1')
            assert.are.equal(8, #answer.devices)
            for slot = 1, 8 do
                assert.are.equal(('id%06d'):format(slot), answer.devices[slot].id)
            end
        end)

        it('2e. no phone carried answers allow = true with an empty list', function()
            boot({ inv = { [1] = { [1] = { name = 'water', slot = 1, count = 1, metadata = {} } } } })
            local answer = ask(1, 'chk1')
            assert.are.same({ allow = true, devices = {} }, answer)
        end)

        it('2f. ox_inventory not started answers the same empty list', function()
            boot({ oxStarted = false, inv = { [1] = { [1] = { name = 'phone', slot = 1, count = 1, metadata = { phoneId = 'abcd1234' } } } } })
            local answer = ask(1, 'chk1')
            assert.are.same({ allow = true, devices = {} }, answer)
        end)
    end)

    describe('3. metadata pass-through (shared/logic/phone.lua)', function()
        it('3a. sends battery 87, fold closed and color 2', function()
            local P = loadLogic()
            local devices = P.buildDevices({
                { name = 'phone_fold', slot = 1, metadata = { phoneId = 'f00d0001', battery = 87, fold = 'closed', color = 2 } },
            }, SHIPPED_ITEMS)
            assert.are.same({ { id = 'f00d0001', model = 'fold', battery = 87, fold = 'closed', color = 2 } }, devices)
        end)

        it('3b. leaves out battery x, 120 or missing, fold half and color -1', function()
            local P = loadLogic()
            local devices = P.buildDevices({
                { name = 'phone_fold', slot = 1, metadata = { phoneId = 'f00d0001', battery = 'x', fold = 'half', color = -1 } },
                { name = 'phone_fold', slot = 2, metadata = { phoneId = 'f00d0002', battery = 120, color = 1.5 } },
                { name = 'phone_fold', slot = 3, metadata = { phoneId = 'f00d0003' } },
            }, SHIPPED_ITEMS)
            assert.are.same({
                { id = 'f00d0001', model = 'fold' },
                { id = 'f00d0002', model = 'fold' },
                { id = 'f00d0003', model = 'fold' },
            }, devices)
        end)

        it('3c. the server answer carries the same pass-through', function()
            boot({ inv = { [1] = {
                [2] = { name = 'phone_fold', slot = 2, count = 1, metadata = { phoneId = 'f00d0001', battery = 87, fold = 'closed', color = 2 } },
            } } })
            local answer = ask(1, 'chk1')
            assert.are.same({ { id = 'f00d0001', model = 'fold', battery = 87, fold = 'closed', color = 2 } }, answer.devices)
        end)
    end)

    describe('4. gate', function()
        it('4a. fires listen on start and again on every hello', function()
            boot()
            assert.are.equal(1, #natives.emitted('local', 'aeterna_phonekit:listen'))
            natives.fire('aeterna_phonekit:hello')
            assert.are.equal(2, #natives.emitted('local', 'aeterna_phonekit:listen'))
        end)

        it('4b. stays silent for devices = single', function()
            boot({ inv = { [1] = { [1] = { name = 'phone', slot = 1, count = 1, metadata = { phoneId = 'abcd1234' } } } } })
            natives.fire('aeterna_phonekit:asking', 1, { checkId = 'chk1', devices = 'single' })
            assert.are.equal(0, #natives.emitted('local', 'aeterna_phonekit:answer'))
        end)

        it('4c. Config.phone.enabled = false: no listen, no answer, no hooks', function()
            local b = boot({ enabled = false, inv = { [1] = { [1] = { name = 'phone', slot = 1, count = 1, metadata = {} } } } })
            assert.are.equal(0, #natives.emitted('local', 'aeterna_phonekit:listen'))
            natives.fire('aeterna_phonekit:hello')
            assert.are.equal(0, #natives.emitted('local', 'aeterna_phonekit:listen'))
            natives.fire('aeterna_phonekit:asking', 1, { checkId = 'chk1', devices = 'items' })
            assert.are.equal(0, #natives.emitted('local', 'aeterna_phonekit:answer'))
            assert.is_nil(b.ox.hooks.swapItems)
            assert.is_nil(b.ox.hooks.createItem)
            assert.are.equal(0, #b.ox.writes)
        end)
    end)

    describe('5. deviceSave', function()
        local b, inv
        before_each(function()
            inv = { [1] = {
                [1] = { name = 'phone_fold', slot = 1, count = 1,
                    metadata = { phoneId = 'cafe0001', battery = 50, fold = 'open', color = 2, label = 'Mine' } },
                [2] = { name = 'phone', slot = 2, count = 1, metadata = { phoneId = 'cafe0002', battery = 10 } },
            } }
            b = boot({ inv = inv })
        end)

        it('5a. battery 101 and -5 clamp to 100 and 0', function()
            save(1, { id = 'cafe0002', battery = 101 })
            assert.are.equal(100, inv[1][2].metadata.battery)
            natives.advance(5000)
            save(1, { id = 'cafe0002', battery = -5 })
            assert.are.equal(0, inv[1][2].metadata.battery)
            assert.are.equal(2, #b.ox.writes)
        end)

        it('5b. a bad fold is ignored and battery is still written', function()
            save(1, { id = 'cafe0001', battery = 42.4, fold = 'half' })
            assert.are.equal(1, #b.ox.writes)
            assert.are.equal(42, inv[1][1].metadata.battery)
            assert.are.equal('open', inv[1][1].metadata.fold)
        end)

        it('5c. a save for a phoneId no longer carried fires devicesChanged and writes nothing', function()
            save(1, { id = 'gone0003', battery = 40 })
            assert.are.equal(0, #b.ox.writes)
            assert.are.equal(1, changedFor(1))
        end)

        it('5d. a phone moved to another slot is still found', function()
            inv[1][7] = inv[1][2]
            inv[1][7].slot = 7
            inv[1][2] = nil
            save(1, { id = 'cafe0002', battery = 33 })
            assert.are.equal(1, #b.ox.writes)
            assert.are.equal(7, b.ox.writes[1].slot)
            assert.are.equal(33, inv[1][7].metadata.battery)
        end)

        it('5e. three saves within 5000 ms write the latest once', function()
            save(1, { id = 'cafe0001', battery = 49, fold = 'open' })
            assert.are.equal(1, #b.ox.writes)
            natives.advance(1000)
            save(1, { id = 'cafe0001', battery = 48, fold = 'open' })
            natives.advance(1000)
            save(1, { id = 'cafe0001', battery = 47, fold = 'closed' })
            natives.advance(1000)
            save(1, { id = 'cafe0001', battery = 46, fold = 'closed' })
            assert.are.equal(1, #b.ox.writes)
            natives.advance(1999)
            assert.are.equal(1, #b.ox.writes)
            natives.advance(1)
            assert.are.equal(2, #b.ox.writes)
            assert.are.equal(46, inv[1][1].metadata.battery)
            assert.are.equal('closed', inv[1][1].metadata.fold)
            natives.advance(10000)
            assert.are.equal(2, #b.ox.writes)
        end)

        it('5f. other metadata fields are kept, and a fold-only save leaves battery alone', function()
            save(1, { id = 'cafe0001', fold = 'closed' })
            assert.are.same({ phoneId = 'cafe0001', battery = 50, fold = 'closed', color = 2, label = 'Mine' },
                inv[1][1].metadata)
        end)

        it('5g. a save from another player does not touch this player\'s phone', function()
            inv[2] = {}
            save(2, { id = 'cafe0001', battery = 1 })
            assert.are.equal(50, inv[1][1].metadata.battery)
            assert.are.equal(0, #b.ox.writes)
            assert.are.equal(1, changedFor(2))
        end)
    end)

    describe('5h. deviceSave around player drop and resource stop', function()
        local b, inv
        before_each(function()
            inv = { [1] = {
                [1] = { name = 'phone_fold', slot = 1, count = 1, metadata = { phoneId = 'cafe0001', battery = 50 } },
            } }
            b = boot({ inv = inv })
        end)

        it('5h1. save first, then drop: the held save is written at once on drop', function()
            save(1, { id = 'cafe0001', battery = 49 })
            natives.advance(1000)
            save(1, { id = 'cafe0001', battery = 44 })
            assert.are.equal(1, #b.ox.writes)
            drop(1)
            assert.are.equal(2, #b.ox.writes)
            assert.are.equal(44, inv[1][1].metadata.battery)
            natives.advance(10000)
            assert.are.equal(2, #b.ox.writes)
        end)

        it('5h2. drop first, then save: written at once while the inventory is still there', function()
            save(1, { id = 'cafe0001', battery = 49 })
            drop(1)
            natives.advance(500)
            save(1, { id = 'cafe0001', battery = 41, fold = 'closed' })
            assert.are.equal(2, #b.ox.writes)
            assert.are.equal(41, inv[1][1].metadata.battery)
            assert.are.equal('closed', inv[1][1].metadata.fold)
        end)

        it('5h3. drop first, then save with the inventory gone: nothing written, debug log, no devicesChanged', function()
            drop(1)
            inv[1] = nil
            save(1, { id = 'cafe0001', battery = 30 })
            natives.advance(0)
            assert.are.equal(0, #b.ox.writes)
            assert.are.equal(0, changedFor(1))
            assert.is_true(#b.debugs >= 1)
        end)

        it('5h4. no devicesChanged for a dropped player from a late hook report', function()
            b.ox.hooks.swapItems({
                source = 1, action = 'move',
                fromInventory = 1, fromType = 'player', fromSlot = { name = 'phone_fold', slot = 1 },
                toInventory = 1, toType = 'player', toSlot = 5,
            })
            drop(1)
            natives.advance(0)
            assert.are.equal(0, changedFor(1))
        end)

        it('5h5. invkit stopping writes every held save', function()
            inv[2] = { [3] = { name = 'phone', slot = 3, count = 1, metadata = { phoneId = 'cafe0002', battery = 80 } } }
            natives.add_player(2, 'player2')
            save(1, { id = 'cafe0001', battery = 49 })
            save(2, { id = 'cafe0002', battery = 79 })
            save(1, { id = 'cafe0001', battery = 48 })
            save(2, { id = 'cafe0002', battery = 78 })
            assert.are.equal(2, #b.ox.writes)
            natives.fire('onResourceStop', 'aeterna_invkit')
            assert.are.equal(4, #b.ox.writes)
            assert.are.equal(48, inv[1][1].metadata.battery)
            assert.are.equal(78, inv[2][3].metadata.battery)
        end)
    end)

    describe('6. devicesChanged', function()
        local b
        before_each(function()
            b = boot({ inv = { [1] = {}, [2] = {} } })
        end)

        it('6a. registers swapItems and createItem hooks filtered on the mapped items', function()
            assert.is_function(b.ox.hooks.swapItems)
            assert.is_function(b.ox.hooks.createItem)
            local filter = b.ox.hookOpts.swapItems.itemFilter
            assert.is_true(filter.phone_fold)
            assert.is_true(filter.phone)
            assert.is_nil(filter.water)
            assert.are.same(filter, b.ox.hookOpts.createItem.itemFilter)
        end)

        it('6b. a swap report for a mapped item fires it once for that player, after the hook returns', function()
            local ret = b.ox.hooks.swapItems({
                source = 1, action = 'move',
                fromInventory = 1, fromType = 'player', fromSlot = { name = 'phone_fold', slot = 1 },
                toInventory = 1, toType = 'player', toSlot = 5,
            })
            assert.is_nil(ret)
            assert.are.equal(0, changedFor(1))
            natives.advance(0)
            assert.are.equal(1, changedFor(1))
        end)

        it('6c. a give fires it for both players, a drop for the giver', function()
            b.ox.hooks.swapItems({
                source = 1, action = 'give',
                fromInventory = 1, fromType = 'player', fromSlot = { name = 'phone', slot = 2 },
                toInventory = 2, toType = 'player',
            })
            b.ox.hooks.swapItems({
                source = 1, action = 'move',
                fromInventory = 1, fromType = 'player', fromSlot = { name = 'phone', slot = 3 },
                toInventory = 'newdrop', toType = 'drop', toSlot = 1,
            })
            natives.advance(0)
            assert.are.equal(1, changedFor(1))
            assert.are.equal(1, changedFor(2))
        end)

        it('6d. a new mapped item in a player inventory fires it; a stash does not', function()
            local ret = b.ox.hooks.createItem({ inventoryId = 2, item = { name = 'phone_pad' }, metadata = {}, count = 1 })
            assert.is_nil(ret)
            b.ox.hooks.createItem({ inventoryId = 'aeterna_stash:c:X', item = { name = 'phone_pad' }, metadata = {}, count = 1 })
            natives.advance(0)
            assert.are.equal(1, changedFor(2))
            assert.are.equal(1, #natives.emitted('local', 'aeterna_phonekit:devicesChanged'))
        end)

        it('6f. a numeric or numeric-string stash id is not taken for a player', function()
            b.ox.hooks.createItem({ inventoryId = '2', item = { name = 'phone_pad' }, metadata = {}, count = 1 })
            b.ox.hooks.createItem({ inventoryId = 77, item = { name = 'phone_pad' }, metadata = {}, count = 1 })
            b.ox.hooks.createItem({ inventoryId = 2.5, item = { name = 'phone_pad' }, metadata = {}, count = 1 })
            b.ox.hooks.swapItems({
                source = 1, action = 'move',
                fromInventory = '1', fromType = 'stash', fromSlot = { name = 'phone', slot = 1 },
                toInventory = 1, toType = 'stash', toSlot = 2,
            })
            natives.advance(0)
            assert.are.equal(0, #natives.emitted('local', 'aeterna_phonekit:devicesChanged'))
        end)

        it('6e. an unmapped item does not fire it', function()
            b.ox.hooks.swapItems({
                source = 1, action = 'move',
                fromInventory = 1, fromType = 'player', fromSlot = { name = 'water', slot = 1 },
                toInventory = 1, toType = 'player', toSlot = 5,
            })
            b.ox.hooks.createItem({ inventoryId = 1, item = { name = 'water' }, metadata = {}, count = 1 })
            natives.advance(0)
            assert.are.equal(0, #natives.emitted('local', 'aeterna_phonekit:devicesChanged'))
        end)
    end)
end)
