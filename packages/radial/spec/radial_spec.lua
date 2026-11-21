-- spec/radial_spec.lua -- busted tests for aeterna_radial (pure logic in shared/logic/radial.lua).

local natives = require('helpers.natives')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local function load_logic()
    return assert(loadfile(DIR .. '/shared/logic/radial.lua'))()
end

describe('aeterna_radial', function()
    describe('1. Registry (shared/logic/radial.lua)', function()
        local L, reg
        before_each(function()
            natives.reset()
            L = load_logic()
            reg = L.createRegistry({ maxPerOwner = 64, maxTotal = 128 })
        end)

        it('registers a new slot and replaces an existing slot with same owner and id', function()
            local ok1 = reg:addSlot('res_a', { id = 'slot_1', label = 'Slot 1' }, 'client')
            assert.is_true(ok1)
            local s1 = reg:getSlot('res_a', 'slot_1', 'client')
            assert.is_not_nil(s1)
            assert.are.equal('Slot 1', s1.label)

            local ok2 = reg:addSlot('res_a', { id = 'slot_1', label = 'Slot 1 Updated' }, 'client')
            assert.is_true(ok2)
            local s2 = reg:getSlot('res_a', 'slot_1', 'client')
            assert.are.equal('Slot 1 Updated', s2.label)
        end)

        it('refuses registration exceeding Config.maxPerOwner and Config.maxTotal', function()
            for i = 1, 64 do
                assert.is_true(reg:addSlot('res_a', { id = 'slot_' .. i, label = 'Slot' }, 'client'))
            end
            local okOverOwner, errOwner = reg:addSlot('res_a', { id = 'slot_65', label = 'Slot' }, 'client')
            assert.is_false(okOverOwner)
            assert.is_truthy(errOwner and errOwner:match('maxPerOwner'))

            for i = 1, 64 do
                assert.is_true(reg:addSlot('res_b', { id = 'slot_' .. i, label = 'Slot' }, 'client'))
            end
            local okOverTotal, errTotal = reg:addSlot('res_c', { id = 'slot_1', label = 'Slot' }, 'client')
            assert.is_false(okOverTotal)
            assert.is_truthy(errTotal and errTotal:match('maxTotal'))
        end)

        it('removes only slots and flags belonging to stopped owner', function()
            reg:addSlot('res_a', { id = 'slot_a', label = 'A' }, 'client')
            reg:addSlot('res_b', { id = 'slot_b', label = 'B' }, 'client')
            reg:setFlag('res_a', 'flag_a', true)
            reg:setFlag('res_b', 'flag_b', true)

            reg:removeByOwner('res_a')
            assert.is_nil(reg:getSlot('res_a', 'slot_a', 'client'))
            assert.is_not_nil(reg:getSlot('res_b', 'slot_b', 'client'))
            assert.is_false(reg:getFlag('res_a', 'flag_a'))
            assert.is_true(reg:getFlag('res_b', 'flag_b'))
        end)

        it('refuses a child of a child (depth) and cross-owner parent (unknown)', function()
            reg:addSlot('res_a', { id = 'root', label = 'Root' }, 'client')
            reg:addSlot('res_a', { id = 'sub', label = 'Sub', parent = 'root' }, 'client')

            local okDepth, errDepth = reg:addSlot('res_a', { id = 'sub_sub', label = 'Deep', parent = 'sub' }, 'client')
            assert.is_false(okDepth)
            assert.is_truthy(errDepth and errDepth:match('parent: depth'))

            local okUnknown, errUnknown = reg:addSlot('res_b', { id = 'child_b', label = 'B', parent = 'root' }, 'client')
            assert.is_false(okUnknown)
            assert.is_truthy(errUnknown and errUnknown:match('parent: unknown'))
        end)
    end)

    describe('2. Schema validation (shared/logic/radial.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = load_logic()
        end)

        it('fails with path when label exceeds 20 characters', function()
            local ok, err = L.validateSlot({ id = 'test', label = string.rep('a', 21) }, 'client')
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^label:'))
        end)

        it('counts label length in characters, so 20 Thai characters pass and 21 fail', function()
            local okTwenty = L.validateSlot({ id = 'test', label = string.rep('ก', 20) }, 'client')
            assert.is_true(okTwenty)
            local ok, err = L.validateSlot({ id = 'test', label = string.rep('ก', 21) }, 'client')
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^label:'))
        end)

        it('fails with path when when.jobs exceeds 8 items', function()
            local jobs = {}
            for i = 1, 9 do jobs[i] = 'job_' .. i end
            local ok, err = L.validateSlot({ id = 'test', label = 'Test', when = { jobs = jobs } }, 'client')
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^when%.jobs:'))
        end)

        it('fails with path when grade is provided without jobs', function()
            local ok, err = L.validateSlot({ id = 'test', label = 'Test', when = { grade = 2 } }, 'client')
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^when%.grade:'))
        end)

        it('fails with path when ace does not start with aeterna.', function()
            local ok, err = L.validateSlot({ id = 'test', label = 'Test', when = { ace = 'custom.admin' } }, 'server')
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^when%.ace:'))
        end)

        it('fails with path on unknown icon name', function()
            local ok, err = L.validateSlot({ id = 'test', label = 'Test', icon = 'invalid_icon_name' }, 'client')
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^icon:'))
        end)
    end)

    describe('3. Ring building (shared/logic/radial.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = load_logic()
        end)

        it('sorts visible slots by order then owner then id', function()
            local slots = {
                { owner = 'res_b', id = 'b', label = 'B', order = 100 },
                { owner = 'res_a', id = 'z', label = 'Z', order = 100 },
                { owner = 'res_a', id = 'a', label = 'A', order = 100 },
                { owner = 'res_c', id = 'first', label = 'First', order = 10 },
            }
            local ring = L.buildRing(slots)
            assert.are.equal('first', ring.slots[1].id)
            assert.are.equal('a', ring.slots[2].id)
            assert.are.equal('z', ring.slots[3].id)
            assert.are.equal('b', ring.slots[4].id)
        end)

        it('allocates max(4, n) positions for n visible slots up to 8', function()
            local r1 = L.buildRing({ { owner = 'a', id = '1', label = '1' } })
            assert.are.equal(4, r1.totalPositions)
            assert.are.equal(1, #r1.slots)

            local r5 = L.buildRing({
                { owner = 'a', id = '1', label = '1' },
                { owner = 'a', id = '2', label = '2' },
                { owner = 'a', id = '3', label = '3' },
                { owner = 'a', id = '4', label = '4' },
                { owner = 'a', id = '5', label = '5' },
            })
            assert.are.equal(5, r5.totalPositions)
            assert.are.equal(5, #r5.slots)
        end)

        it('shows first 8 slots and warns cut owners when 9 slots are visible', function()
            local warnings = {}
            local ctx = {
                warn = function(msg) warnings[#warnings + 1] = msg end,
            }
            local slots = {}
            for i = 1, 9 do
                slots[i] = { owner = 'res_' .. i, id = 'slot_' .. i, label = 'S' .. i, order = i * 10 }
            end
            local ring = L.buildRing(slots, ctx)
            assert.are.equal(8, #ring.slots)
            assert.are.equal(8, ring.totalPositions)
            assert.are.equal(1, #warnings)
            assert.is_truthy(warnings[1]:match('res_9'))
        end)

        it('hides a group slot when none of its children are visible', function()
            local slots = {
                { owner = 'res_a', id = 'alone', label = 'Standalone' },
                { owner = 'res_a', id = 'grp', label = 'Group', isGroup = true },
            }
            local children = {
                grp = {
                    { owner = 'res_a', id = 'c1', label = 'Child 1', visible = false },
                },
            }
            local ring = L.buildRing(slots, { children = children })
            assert.are.equal(1, #ring.slots)
            assert.are.equal('alone', ring.slots[1].id)
        end)
    end)

    describe('4. Conditions (shared/logic/radial.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = load_logic()
        end)

        it('evaluates vehicle conditions for in, out, and driver', function()
            assert.is_true(L.evalCondition({ vehicle = 'in' }, { inVehicle = true, isDriver = false }))
            assert.is_false(L.evalCondition({ vehicle = 'in' }, { inVehicle = false, isDriver = false }))

            assert.is_true(L.evalCondition({ vehicle = 'out' }, { inVehicle = false, isDriver = false }))
            assert.is_false(L.evalCondition({ vehicle = 'out' }, { inVehicle = true, isDriver = false }))

            assert.is_true(L.evalCondition({ vehicle = 'driver' }, { inVehicle = true, isDriver = true }))
            assert.is_false(L.evalCondition({ vehicle = 'driver' }, { inVehicle = true, isDriver = false }))
        end)

        it('evaluates jobs and grade conditions with qbx_core', function()
            local ctx = { hasQbx = true, job = 'police', grade = 3 }
            assert.is_true(L.evalCondition({ jobs = { 'police', 'sheriff' }, grade = 2 }, ctx))
            assert.is_false(L.evalCondition({ jobs = { 'police', 'sheriff' }, grade = 4 }, ctx))
            assert.is_false(L.evalCondition({ jobs = { 'ambulance' } }, ctx))
        end)

        it('evaluates jobs as false when qbx_core is missing', function()
            local warnings = {}
            local ctx = { hasQbx = false, warn = function(m) warnings[#warnings + 1] = m end }
            assert.is_false(L.evalCondition({ jobs = { 'police' } }, ctx))
            assert.are.equal(1, #warnings)
        end)

        it('evaluates flags requiring all specified flags to be true', function()
            local flags = { ['res_a:handcuffed'] = true, ['res_a:cuffed_front'] = true }
            local ctx = { owner = 'res_a', flags = flags }
            assert.is_true(L.evalCondition({ flags = { 'handcuffed', 'cuffed_front' } }, ctx))
            assert.is_false(L.evalCondition({ flags = { 'handcuffed', 'bleeding' } }, ctx))
        end)
    end)

    describe('5. Geometry (shared/logic/radial.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = load_logic()
        end)

        it('maps pointer or stick angle to slot index for 4, 5, and 8 positions with slot 1 at top clockwise', function()
            assert.are.equal(1, L.angleToSlot(0, 4))
            assert.are.equal(2, L.angleToSlot(90, 4))
            assert.are.equal(3, L.angleToSlot(180, 4))
            assert.are.equal(4, L.angleToSlot(270, 4))

            assert.are.equal(1, L.angleToSlot(0, 8))
            assert.are.equal(2, L.angleToSlot(45, 8))
            assert.are.equal(5, L.angleToSlot(180, 8))
            assert.are.equal(8, L.angleToSlot(315, 8))

            assert.are.equal(1, L.angleToSlot(0, 5))
            assert.are.equal(2, L.angleToSlot(72, 5))
        end)

        it('maps a pointer outside the dead zone with screen y down, slot 1 at the top, clockwise', function()
            assert.are.equal(1, L.pointerToSlot(0, -100, 150, 0.35, 4))
            assert.are.equal(2, L.pointerToSlot(100, 0, 150, 0.35, 4))
            assert.are.equal(3, L.pointerToSlot(0, 100, 150, 0.35, 4))
            assert.are.equal(4, L.pointerToSlot(-100, 0, 150, 0.35, 4))
            assert.are.equal(2, L.pointerToSlot(70, -70, 150, 0.35, 8))
            assert.are.equal(8, L.pointerToSlot(-70, -70, 150, 0.35, 8))
            assert.are.equal(2, L.pointerToSlot(95, -31, 150, 0.35, 5))
        end)

        it('maps a stick outside the dead zone with y down, slot 1 at the top, clockwise', function()
            assert.are.equal(1, L.stickToSlot(0, -1, 0.35, 4))
            assert.are.equal(2, L.stickToSlot(1, 0, 0.35, 4))
            assert.are.equal(3, L.stickToSlot(0, 1, 0.35, 4))
            assert.are.equal(4, L.stickToSlot(-1, 0, 0.35, 4))
            assert.are.equal(5, L.stickToSlot(0, 1, 0.35, 8))
            assert.are.equal(4, L.stickToSlot(-0.5, 0.9, 0.35, 5))
        end)

        it('returns nil/none when input is within dead zone', function()
            assert.is_nil(L.pointerToSlot(0.1, 0.1, 150, 0.35, 4))
            assert.is_nil(L.stickToSlot(0.1, 0.2, 0.35, 4))
        end)
    end)

    describe('6. Server pick validation (shared/logic/radial.lua)', function()
        local L, reg
        before_each(function()
            natives.reset()
            L = load_logic()
            reg = L.createRegistry({ maxPerOwner = 64, maxTotal = 128 })
            reg:addSlot('res_a', {
                id = 'repair',
                label = 'Repair',
                when = { vehicle = 'driver', jobs = { 'mechanic' }, ace = 'aeterna.mechanic.repair' },
            }, 'server')
        end)

        it('drops pick for unknown slot or when conditions fail', function()
            local ctxValid = {
                inVehicle = true,
                isDriver = true,
                hasQbx = true,
                job = 'mechanic',
                can = function(_, a) return a == 'aeterna.mechanic.repair' end,
            }

            local okUnknown = L.handleServerPick(1, 'res_a', 'nonexistent', reg, ctxValid)
            assert.is_false(okUnknown)

            local ctxBadVeh = { inVehicle = true, isDriver = false, hasQbx = true, job = 'mechanic', can = function() return true end }
            local okVeh = L.handleServerPick(1, 'res_a', 'repair', reg, ctxBadVeh)
            assert.is_false(okVeh)

            local ctxBadJob = { inVehicle = true, isDriver = true, hasQbx = true, job = 'taxi', can = function() return true end }
            local okJob = L.handleServerPick(1, 'res_a', 'repair', reg, ctxBadJob)
            assert.is_false(okJob)

            local ctxBadAce = { inVehicle = true, isDriver = true, hasQbx = true, job = 'mechanic', can = function() return false end }
            local okAce = L.handleServerPick(1, 'res_a', 'repair', reg, ctxBadAce)
            assert.is_false(okAce)
        end)

        it('dispatches aeterna_radial:select with { owner, id } on valid pick', function()
            local ctxValid = {
                inVehicle = true,
                isDriver = true,
                hasQbx = true,
                job = 'mechanic',
                can = function(_, a) return a == 'aeterna.mechanic.repair' end,
            }
            local ok, res = L.handleServerPick(1, 'res_a', 'repair', reg, ctxValid)
            assert.is_true(ok)
            assert.are.same({ owner = 'res_a', id = 'repair' }, res)
        end)
    end)
end)
