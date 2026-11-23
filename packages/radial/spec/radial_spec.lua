-- spec/radial_spec.lua -- busted tests for aeterna_radial (pure logic in shared/logic/radial.lua).

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

-- Core's local events come from aeterna_core: fire them with that invoking resource, as FXServer does.
local function fireAsCore(name, ...)
    local original = GetInvokingResource
    natives.stub('GetInvokingResource', function() return 'aeterna_core' end)
    natives.fire(name, ...)
    natives.stub('GetInvokingResource', original)
end

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

        it('stores only schema fields, so a forged isGroup does not make a group', function()
            assert.is_true(reg:addSlot('res_a', { id = 'fake', label = 'Fake', isGroup = true, extra = 'x' }, 'client'))
            local stored = reg:getSlot('res_a', 'fake', 'client')
            assert.is_nil(stored.isGroup)
            assert.is_nil(stored.extra)
            assert.is_false(reg:isGroup('res_a', 'fake', 'client'))
        end)

        it('refuses to give a parent to a slot that has children, or to itself', function()
            reg:addSlot('res_a', { id = 'root', label = 'Root' }, 'client')
            reg:addSlot('res_a', { id = 'other', label = 'Other' }, 'client')
            reg:addSlot('res_a', { id = 'sub', label = 'Sub', parent = 'root' }, 'client')
            local ok, err = reg:addSlot('res_a', { id = 'root', label = 'Root', parent = 'other' }, 'client')
            assert.is_false(ok)
            assert.is_truthy(err and err:match('parent: depth'))
            local okSelf, errSelf = reg:addSlot('res_a', { id = 'other', label = 'Other', parent = 'other' }, 'client')
            assert.is_false(okSelf)
            assert.is_truthy(errSelf and errSelf:match('^parent:'))
        end)

        it('stops being a group when its last child is removed', function()
            reg:addSlot('res_a', { id = 'root', label = 'Root' }, 'client')
            reg:addSlot('res_a', { id = 'sub', label = 'Sub', parent = 'root' }, 'client')
            assert.is_true(reg:isGroup('res_a', 'root', 'client'))
            reg:removeSlot('res_a', 'sub', 'client')
            assert.is_false(reg:isGroup('res_a', 'root', 'client'))
            local ring = L.ringFor({ reg }, nil, {})
            assert.are.equal(1, #ring.slots)
            assert.is_false(ring.slots[1].isGroup)
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

        it('fails closed when ace is set and no can function is given', function()
            assert.is_false(L.evalCondition({ ace = 'aeterna.radial.x' }, {}))
            assert.is_true(L.evalCondition({ ace = 'aeterna.radial.x' }, { can = function() return true end }))
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

        it('drops a pick of a group slot', function()
            reg:addSlot('res_a', { id = 'grp', label = 'Group' }, 'server')
            reg:addSlot('res_a', { id = 'grp_child', label = 'Child', parent = 'grp' }, 'server')
            local ctx = { can = function() return true end }
            assert.is_false(L.handleServerPick(1, 'res_a', 'grp', reg, ctx))
            assert.is_true(L.handleServerPick(1, 'res_a', 'grp_child', reg, ctx))
        end)

        it('re-checks the parent group conditions for a child pick', function()
            reg:addSlot('res_a', { id = 'admin', label = 'Admin', when = { ace = 'aeterna.radial.admin' } }, 'server')
            reg:addSlot('res_a', { id = 'kick', label = 'Kick', parent = 'admin' }, 'server')
            reg:addSlot('res_a', { id = 'cops', label = 'Cops', when = { jobs = { 'police' } } }, 'server')
            reg:addSlot('res_a', { id = 'cuff', label = 'Cuff', parent = 'cops' }, 'server')
            local deny = { hasQbx = true, job = 'taxi', can = function() return false end }
            assert.is_false(L.handleServerPick(1, 'res_a', 'kick', reg, deny))
            assert.is_false(L.handleServerPick(1, 'res_a', 'cuff', reg, deny))
            local allow = { hasQbx = true, job = 'police', can = function() return true end }
            assert.is_true(L.handleServerPick(1, 'res_a', 'kick', reg, allow))
            assert.is_true(L.handleServerPick(1, 'res_a', 'cuff', reg, allow))
        end)

        it('does not re-check flags on the server, since the client holds them', function()
            reg:addSlot('res_a', { id = 'flagged', label = 'Flagged', when = { flags = { 'armed' } } }, 'server')
            local ok, res = L.handleServerPick(1, 'res_a', 'flagged', reg, { can = function() return true end })
            assert.is_true(ok)
            assert.are.same({ owner = 'res_a', id = 'flagged' }, res)
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

    describe('7. Rings from the registries (shared/logic/radial.lua)', function()
        local L, clientReg, serverReg
        before_each(function()
            natives.reset()
            L = load_logic()
            clientReg = L.createRegistry({ maxPerOwner = 64, maxTotal = 128 })
            serverReg = L.createRegistry({ maxPerOwner = 64, maxTotal = 128 })
        end)

        it('builds the root ring from client and server slots, with per-owner flags', function()
            clientReg:addSlot('res_a', { id = 'hud', label = 'HUD', order = 10 }, 'client')
            clientReg:addSlot('res_a', { id = 'armed', label = 'Armed', when = { flags = { 'armed' } } }, 'client')
            clientReg:addSlot('res_b', { id = 'other', label = 'Other', when = { flags = { 'armed' } } }, 'client')
            serverReg:addSlot('res_c', { id = 'keys', label = 'Keys', order = 20 }, 'server')
            clientReg:setFlag('res_a', 'armed', true)

            local ring = L.ringFor({ clientReg, serverReg }, nil, { flags = clientReg.flags })
            assert.are.equal(3, #ring.slots)
            assert.are.equal('hud', ring.slots[1].id)
            assert.are.equal('keys', ring.slots[2].id)
            assert.are.equal('server', ring.slots[2].side)
            assert.are.equal('armed', ring.slots[3].id)
            assert.are.equal(4, ring.totalPositions)
        end)

        it('builds a child ring for one group and hides a group whose children are all hidden', function()
            clientReg:addSlot('res_a', { id = 'grp', label = 'Group' }, 'client')
            clientReg:addSlot('res_a', { id = 'c1', label = 'C1', order = 2 }, 'client')
            clientReg:addSlot('res_a', { id = 'k1', label = 'K1', parent = 'grp', order = 2 }, 'client')
            clientReg:addSlot('res_a', { id = 'k2', label = 'K2', parent = 'grp', order = 1 }, 'client')
            clientReg:addSlot('res_a', { id = 'empty', label = 'Empty' }, 'client')
            clientReg:addSlot('res_a', { id = 'e1', label = 'E1', parent = 'empty', when = { vehicle = 'in' } }, 'client')

            local root = L.ringFor({ clientReg }, nil, { inVehicle = false })
            assert.are.equal(2, #root.slots)
            assert.are.equal('c1', root.slots[1].id)
            assert.are.equal('grp', root.slots[2].id)
            assert.is_true(root.slots[2].isGroup)

            local child = L.ringFor({ clientReg }, root.slots[2], { inVehicle = false })
            assert.are.equal(2, #child.slots)
            assert.are.equal('k2', child.slots[1].id)
            assert.are.equal('k1', child.slots[2].id)
        end)

        it('warns once per slot when jobs are used without qbx_core', function()
            clientReg:addSlot('res_a', { id = 'cop', label = 'Cop', when = { jobs = { 'police' } } }, 'client')
            local warnings = {}
            local ctx = { hasQbx = false, warn = function(m) warnings[#warnings + 1] = m end }
            L.ringFor({ clientReg }, nil, ctx)
            L.ringFor({ clientReg }, nil, ctx)
            assert.are.equal(1, #warnings)
        end)

        it('maps an index to a visible slot and drops empty positions', function()
            clientReg:addSlot('res_a', { id = 'one', label = 'One' }, 'client')
            local ring = L.ringFor({ clientReg }, nil, {})
            assert.are.equal('one', L.slotAt(ring, 1).id)
            assert.is_nil(L.slotAt(ring, 2))
            assert.is_nil(L.slotAt(ring, 0))
            assert.is_nil(L.slotAt(ring, 1.5))
            assert.is_nil(L.slotAt(ring, '1'))
        end)

        it('sends the NUI only labels, icons and group marks', function()
            clientReg:addSlot('res_a', { id = 'grp', label = 'Group', icon = 'car' }, 'client')
            clientReg:addSlot('res_a', { id = 'k1', label = 'K1', parent = 'grp' }, 'client')
            local ring = L.ringFor({ clientReg }, nil, {})
            assert.are.same({ { label = 'Group', icon = 'car', group = true } }, L.nuiSlots(ring))
        end)

        it('steps the highlight around the visible slots', function()
            assert.are.equal(1, L.stepIndex(nil, 3, 1))
            assert.are.equal(3, L.stepIndex(nil, 3, -1))
            assert.are.equal(1, L.stepIndex(3, 3, 1))
            assert.are.equal(3, L.stepIndex(1, 3, -1))
            assert.is_nil(L.stepIndex(1, 0, 1))
        end)
    end)

    describe('7b. Config checks (shared/logic/radial.lua)', function()
        it('keeps a dead zone in 0-1 and falls back to 0.35 with a warn otherwise', function()
            local L = load_logic()
            local warnings = {}
            local warn = function(m) warnings[#warnings + 1] = m end
            assert.are.equal(0.5, L.checkDeadZone(0.5, warn))
            assert.are.equal(0, L.checkDeadZone(0, warn))
            assert.are.equal(0, #warnings)
            assert.are.equal(0.35, L.checkDeadZone(1.5, warn))
            assert.are.equal(0.35, L.checkDeadZone(-0.1, warn))
            assert.are.equal(0.35, L.checkDeadZone('x', warn))
            assert.are.equal(3, #warnings)
        end)
    end)

    describe('8. Server slot transfer (shared/logic/radial.lua)', function()
        local L, reg
        before_each(function()
            natives.reset()
            L = load_logic()
            reg = L.createRegistry({ maxPerOwner = 64, maxTotal = 128 })
        end)

        it('lists roots before children and applies the filter', function()
            reg:addSlot('res_a', { id = 'grp', label = 'Group' }, 'server')
            reg:addSlot('res_a', { id = 'k1', label = 'K1', parent = 'grp' }, 'server')
            reg:addSlot('res_b', { id = 'admin', label = 'Admin', when = { ace = 'aeterna.radial.admin' } }, 'server')
            local all = L.listSlots(reg, 'server')
            assert.are.equal(3, #all)
            assert.is_nil(all[1].parent)
            assert.is_nil(all[2].parent)
            assert.are.equal('grp', all[3].parent)

            local filtered = L.listSlots(reg, 'server', function(slot)
                return not (slot.when and slot.when.ace)
            end)
            assert.are.equal(2, #filtered)
        end)

        it('sends clients a copy with owner, without ace, that a client registry accepts', function()
            reg:addSlot('res_a', { id = 'grp', label = 'Group', when = { ace = 'aeterna.radial.x', vehicle = 'in' } }, 'server')
            reg:addSlot('res_a', { id = 'k1', label = 'K1', parent = 'grp' }, 'server')
            local list = L.listSlots(reg, 'server')
            assert.are.equal('res_a', list[1].owner)
            assert.is_nil(list[1].when.ace)
            assert.are.equal('in', list[1].when.vehicle)
            assert.is_true(list[1].isGroup)
            assert.is_nil(list[1].side)
            assert.is_not_nil(reg:getSlot('res_a', 'grp', 'server').when.ace)

            local mirror = L.createRegistry({ maxPerOwner = 64, maxTotal = 128 })
            for i = 1, #list do
                assert.is_true(mirror:addSlot(list[i].owner, list[i], 'server', list[i].isGroup))
            end
            assert.is_true(mirror:isGroup('res_a', 'grp', 'server'))
            assert.is_nil(mirror:getSlot('res_a', 'grp', 'server').isGroup)

            -- The server's word keeps a parent a group when this player received none of its children.
            local lone = L.createRegistry({ maxPerOwner = 64, maxTotal = 128 })
            assert.is_true(lone:addSlot('res_a', list[1], 'server', true))
            assert.is_true(lone:isGroup('res_a', 'grp', 'server'))
            assert.are.equal(0, #L.ringFor({ lone }, nil, {}).slots)
            assert.is_true(lone:addSlot('res_a', list[1], 'server', false))
            assert.is_false(lone:isGroup('res_a', 'grp', 'server'))
        end)
    end)

    describe('9. Resource scripts under the harness', function()
        local CORE = { ['@aeterna_core/import.lua'] = DIR .. '/../core/import.lua' }

        it('server: delivers slots by ACE, re-checks picks, fires one select, cleans up on owner stop', function()
            natives.reset({ resource = 'aeterna_radial', side = 'server', invoker = 'res_a' })
            natives.add_player(1, 'One')
            natives.add_player(2, 'Two')
            local inVehicle = false
            natives.stub('IsPlayerAceAllowed', function(src, ace) return tonumber(src) == 1 and ace == 'aeterna.radial.test' end)
            natives.stub('GetPlayerPed', function(src) return 100 + tonumber(src) end)
            natives.stub('GetVehiclePedIsIn', function() return inVehicle and 500 or 0 end)
            natives.stub('GetResourceState', function() return 'missing' end)
            -- 0.2: server/selftest.lua registers the self-tests with aeterna_core on start.
            natives.stub_export('aeterna_core', 'addSelftest', function() return true end)
            local api = resource.load_resource(DIR, 'server', { externals = CORE }).exports

            assert.is_true(api.addSlot({ id = 'open', label = 'Open' }))
            local first = natives.last_emitted('client', 'aeterna_radial:cl:slot')
            assert.are.equal(-1, first.target)
            assert.are.equal('add', first.args[1].op)
            assert.are.equal('res_a', first.args[1].owner)

            assert.is_true(api.addSlot({ id = 'admin', label = 'Admin', when = { ace = 'aeterna.radial.test' } }))
            local sent = natives.emitted('client', 'aeterna_radial:cl:slot')
            local byTarget = {}
            for i = 2, #sent do byTarget[tonumber(sent[i].target)] = sent[i].args[1].op end
            assert.are.same({ [1] = 'add', [2] = 'remove' }, byTarget)

            natives.fire_net('aeterna_radial:sv:hello', 2)
            assert.are.equal(1, #natives.last_emitted('client', 'aeterna_radial:cl:slots').args[1].slots)
            natives.fire_net('aeterna_radial:sv:hello', 1)
            local list = natives.last_emitted('client', 'aeterna_radial:cl:slots').args[1].slots
            assert.are.equal(2, #list)
            for i = 1, #list do assert.is_true(list[i].when == nil or list[i].when.ace == nil) end

            assert.is_true(api.addSlot({ id = 'car', label = 'Car', when = { vehicle = 'in' } }))
            natives.fire_net('aeterna_radial:sv:select', 1, { owner = 'res_a', id = 'car' })
            natives.fire_net('aeterna_radial:sv:select', 2, { owner = 'res_a', id = 'admin' })
            natives.fire_net('aeterna_radial:sv:select', 1, { owner = 'res_a', id = 'nope' })
            natives.fire_net('aeterna_radial:sv:select', 1, { owner = 'res_a', id = 'car', extra = true })
            assert.are.equal(0, #natives.emitted('local', 'aeterna_radial:select'))

            inVehicle = true
            natives.fire_net('aeterna_radial:sv:select', 1, { owner = 'res_a', id = 'car' })
            local picks = natives.emitted('local', 'aeterna_radial:select')
            assert.are.equal(1, #picks)
            assert.are.equal(1, picks[1].args[1])
            assert.are.same({ owner = 'res_a', id = 'car' }, picks[1].args[2])

            -- A parent's group mark follows its children: re-sent when the first arrives and the last leaves.
            assert.is_true(api.addSlot({ id = 'kid', label = 'Kid', parent = 'open' }))
            local marks = natives.emitted('client', 'aeterna_radial:cl:slot')
            local regroup = marks[#marks - 1].args[1]
            assert.are.equal('open', regroup.slot.id)
            assert.is_true(regroup.slot.isGroup)
            assert.are.equal('kid', marks[#marks].args[1].slot.id)
            assert.is_true(api.removeSlot('kid'))
            marks = natives.emitted('client', 'aeterna_radial:cl:slot')
            assert.are.equal('remove', marks[#marks - 1].args[1].op)
            assert.are.equal('open', marks[#marks].args[1].slot.id)
            assert.is_nil(marks[#marks].args[1].slot.isGroup)

            local before = #natives.emitted('client', 'aeterna_radial:cl:slot')
            natives.fire('onResourceStop', 'res_a')
            local after = natives.emitted('client', 'aeterna_radial:cl:slot')
            assert.are.equal(before + 3, #after)
            assert.are.equal('remove', after[#after].args[1].op)
            natives.fire_net('aeterna_radial:sv:hello', 1)
            assert.are.equal(0, #natives.last_emitted('client', 'aeterna_radial:cl:slots').args[1].slots)
        end)

        it('client: opens on the key, picks a client slot, opens a group, and closes on focus loss', function()
            natives.reset({ resource = 'aeterna_radial', side = 'client', invoker = 'res_a' })
            local commands, nuiCallbacks = {}, {}
            local nui = natives.spy('SendNUIMessage')
            natives.spy('RegisterCommand', function(name, fn) commands[name] = fn end)
            natives.spy('RegisterNUICallback', function(name, fn) nuiCallbacks[name] = fn end)
            local mappings = natives.spy('RegisterKeyMapping')
            natives.spy('SetNuiFocus')
            natives.spy('SetNuiFocusKeepInput')
            natives.stub('GetVehiclePedIsIn', function() return 0 end)
            natives.stub('GetResourceState', function() return 'missing' end)
            natives.stub('IsEntityDead', function() return false end)
            natives.stub('IsPedRagdoll', function() return false end)
            natives.stub_export('aeterna_core', 'requestFocus', function() return 'tok_1' end)
            natives.stub_export('aeterna_core', 'releaseFocus', function() return true end)
            natives.stub_export('aeterna_core', 'themeHref', function() return '' end)
            natives.stub_export('aeterna_core', 'themePreset', function() return 'asphalt' end)
            local api = resource.load_resource(DIR, 'client', { externals = CORE }).exports

            -- keyboard gets the kit's suggested default (F3, ADR 0004 decision 10 amended); the gamepad mapping none
            local byMapper = {}
            for i = 1, #mappings do byMapper[mappings[i][3]] = mappings[i][4] end
            assert.are.same({ keyboard = 'F3', PAD_DIGITALBUTTON = '' }, byMapper)
            assert.are.equal(2, #mappings)

            assert.is_true(api.addSlot({ id = 'hud', label = 'HUD', order = 1 }))
            assert.is_true(api.addSlot({ id = 'grp', label = 'Group', order = 2 }))
            assert.is_true(api.addSlot({ id = 'k1', label = 'K1', parent = 'grp' }))
            local okAce = api.addSlot({ id = 'bad', label = 'Bad', when = { ace = 'aeterna.radial.x' } })
            assert.is_false(okAce)

            commands['+aeterna_radial_open']()
            assert.is_true(api.isOpen())
            local opened
            for i = 1, #nui do if nui[i][1].type == 'ring:open' then opened = nui[i][1] end end
            assert.are.equal(2, #opened.slots)
            assert.are.same({ label = 'Group', group = true }, opened.slots[2])

            nuiCallbacks.pick({ index = 2 }, function() end)
            assert.are.equal('ring:hover', nui[#nui][1].type)
            assert.are.equal('ring:child', nui[#nui - 1][1].type)
            nuiCallbacks.pick({ index = 2 }, function() end)
            assert.is_true(api.isOpen())
            nuiCallbacks.back({}, function() end)
            assert.are.equal(2, nui[#nui][1].index)
            -- After a group opened, releasing the key no longer picks; escape closes with no pick.
            commands['-aeterna_radial_open']()
            assert.is_true(api.isOpen())
            nuiCallbacks.escape({}, function() end)
            assert.is_false(api.isOpen())
            assert.are.equal(0, #natives.emitted('local', 'aeterna_radial:select'))

            commands['+aeterna_radial_open']()
            nuiCallbacks.hover({ index = 7 }, function() end)
            nuiCallbacks.hover({ index = 1 }, function() end)
            commands['-aeterna_radial_open']()
            assert.is_false(api.isOpen())
            local picks = natives.emitted('local', 'aeterna_radial:select')
            assert.are.equal(1, #picks)
            assert.are.equal('res_a', picks[1].args[1])
            assert.are.equal('hud', picks[1].args[2])

            commands['aeterna_radial_open']()
            assert.is_true(api.isOpen())
            fireAsCore('aeterna_core:focusLost', 'aeterna_radial', 'tok_1', 'preempted')
            assert.is_false(api.isOpen())
            assert.are.equal('ring:close', nui[#nui][1].type)
            assert.are.equal(1, #natives.emitted('local', 'aeterna_radial:select'))
        end)

        local function loadClient(opts)
            natives.reset({ resource = 'aeterna_radial', side = 'client', invoker = 'res_a' })
            local env = { commands = {}, callbacks = {}, dead = false, released = 0 }
            env.nui = natives.spy('SendNUIMessage')
            natives.spy('RegisterCommand', function(name, fn) env.commands[name] = fn end)
            natives.spy('RegisterNUICallback', function(name, fn) env.callbacks[name] = fn end)
            natives.spy('RegisterKeyMapping')
            env.focus = natives.spy('SetNuiFocus')
            natives.spy('SetNuiFocusKeepInput')
            natives.spy('DisableControlAction')
            natives.stub('GetDisabledControlNormal', function() return 0 end)
            natives.stub('IsDisabledControlJustReleased', function() return false end)
            natives.stub('IsUsingKeyboard', function() return true end)
            natives.stub('GetVehiclePedIsIn', function() return 0 end)
            natives.stub('GetResourceState', function() return 'missing' end)
            natives.stub('IsEntityDead', function() return env.dead end)
            natives.stub('IsPedRagdoll', function() return false end)
            natives.stub_export('aeterna_core', 'requestFocus', function() return 'tok_1' end)
            natives.stub_export('aeterna_core', 'releaseFocus', function()
                env.released = env.released + 1
                return true
            end)
            natives.stub_export('aeterna_core', 'themeHref', function() return '' end)
            natives.stub_export('aeterna_core', 'themePreset', function() return 'asphalt' end)
            env.api = resource.load_resource(DIR, 'client', { externals = CORE }).exports
            if not (opts and opts.keepHello) then
                natives.fire_net('aeterna_radial:cl:slots', 1, { slots = {} })
            end
            natives.advance(0)
            return env
        end

        it('client: own resource stop closes the ring and releases focus', function()
            local env = loadClient()
            env.commands['aeterna_radial_open']()
            assert.is_true(env.api.isOpen())
            natives.fire('onClientResourceStop', 'aeterna_radial')
            assert.is_false(env.api.isOpen())
            assert.are.equal(1, env.released)
            local last = env.focus[#env.focus]
            assert.are.same({ false, false }, { last[1], last[2] })
        end)

        it('client: close while paused gives the token back without clearing the overlay focus', function()
            local env = loadClient()
            env.commands['aeterna_radial_open']()
            fireAsCore('aeterna_core:focusPaused', 'aeterna_radial')
            local before = #env.focus
            env.api.close()
            assert.is_false(env.api.isOpen())
            assert.are.equal(1, env.released)
            assert.are.equal(before, #env.focus)
        end)

        it('client: the frame loop closes the ring when the ped dies', function()
            local env = loadClient()
            env.commands['aeterna_radial_open']()
            natives.advance(5)
            assert.is_true(env.api.isOpen())
            env.dead = true
            natives.advance(5)
            assert.is_false(env.api.isOpen())
        end)

        it('client: the frame loop idles while paused', function()
            local env = loadClient()
            env.commands['aeterna_radial_open']()
            fireAsCore('aeterna_core:focusPaused', 'aeterna_radial')
            natives.advance(1)
            assert.is_true(natives.advance(1000) <= 10)
            fireAsCore('aeterna_core:focusResumed', 'aeterna_radial', 'tok_1')
            assert.is_true(natives.advance(500) > 10)
        end)

        it('client: focus events from another resource change nothing', function()
            local env = loadClient()
            env.commands['aeterna_radial_open']()
            natives.fire('aeterna_core:focusLost', 'aeterna_radial', 'tok_1', 'preempted')
            natives.fire('aeterna_core:focusPaused', 'aeterna_radial')
            assert.is_true(env.api.isOpen())
            natives.advance(1)
            assert.is_true(natives.advance(100) > 10) -- not paused: the frame loop still runs every frame
        end)

        it('client: retries sv:hello once when no slots arrive', function()
            loadClient({ keepHello = true })
            assert.are.equal(1, #natives.emitted('server', 'aeterna_radial:sv:hello'))
            natives.advance(3000)
            assert.are.equal(2, #natives.emitted('server', 'aeterna_radial:sv:hello'))
            natives.advance(10000)
            assert.are.equal(2, #natives.emitted('server', 'aeterna_radial:sv:hello'))

            loadClient()
            natives.advance(10000)
            assert.are.equal(1, #natives.emitted('server', 'aeterna_radial:sv:hello'))
        end)
    end)
end)
