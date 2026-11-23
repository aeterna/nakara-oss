-- Pure logic for aeterna_radial: registry, schema validation, ring building,
-- conditions, geometry, and server pick handling. Natives-free so stock Lua can test it.

RadialLogic = {}
local L = RadialLogic

local ICON_NAMES = {
    'home', 'bell', 'box', 'user', 'users', 'phone', 'message-circle', 'calculator',
    'file-text', 'settings', 'sliders', 'map', 'map-pin', 'car', 'wrench', 'shield',
    'heart', 'droplet', 'utensils', 'clock', 'calendar', 'info', 'alert-triangle',
    'check', 'x', 'plus', 'minus', 'search', 'lock', 'unlock', 'key', 'star',
    'flag', 'trash', 'log-out', 'log-in', 'chevron-right', 'chevron-left', 'arrow-up', 'arrow-down',
}

L.ICONS = {}
for i = 1, #ICON_NAMES do L.ICONS[ICON_NAMES[i]] = true end

function L.validateSlot(slot, side)
    if type(slot) ~= 'table' then return false, 'slot: must be a table' end
    if type(slot.id) ~= 'string' or #slot.id < 1 or #slot.id > 32 or not slot.id:match('^[%w_%-]+$') then
        return false, 'id: must be string 1-32 chars matching ^[%w_%-]+$'
    end
    -- Lengths a player sees count characters (Thai is 3 bytes each); utf8.len is nil for invalid UTF-8.
    local labelLen = type(slot.label) == 'string' and utf8.len(slot.label) or nil
    if not labelLen or labelLen < 1 or labelLen > 20 then
        return false, 'label: must be string 1-20 characters'
    end
    if slot.icon ~= nil and (type(slot.icon) ~= 'string' or not L.ICONS[slot.icon]) then
        return false, 'icon: unknown icon "' .. tostring(slot.icon) .. '"'
    end
    if slot.order ~= nil and (type(slot.order) ~= 'number' or math.floor(slot.order) ~= slot.order or slot.order < 0 or slot.order > 1000) then
        return false, 'order: must be integer 0-1000'
    end
    if slot.parent ~= nil and (type(slot.parent) ~= 'string' or #slot.parent < 1 or #slot.parent > 32 or not slot.parent:match('^[%w_%-]+$')) then
        return false, 'parent: must be string 1-32 chars matching ^[%w_%-]+$'
    end
    if slot.when ~= nil then
        if type(slot.when) ~= 'table' then return false, 'when: must be a table' end
        local w = slot.when
        if w.vehicle ~= nil and w.vehicle ~= 'in' and w.vehicle ~= 'out' and w.vehicle ~= 'driver' then
            return false, 'when.vehicle: must be in, out, or driver'
        end
        if w.jobs ~= nil then
            if type(w.jobs) ~= 'table' then return false, 'when.jobs: must be array' end
            if #w.jobs > 8 then return false, 'when.jobs: exceeds 8 items' end
            for i = 1, #w.jobs do
                local jobLen = type(w.jobs[i]) == 'string' and utf8.len(w.jobs[i]) or nil
                if not jobLen or jobLen > 32 then
                    return false, 'when.jobs[' .. i .. ']: must be string <= 32 chars'
                end
            end
        end
        if w.grade ~= nil then
            if type(w.grade) ~= 'number' or math.floor(w.grade) ~= w.grade or w.grade < 0 or w.grade > 100 then
                return false, 'when.grade: must be integer 0-100'
            end
            if w.jobs == nil or #w.jobs == 0 then return false, 'when.grade: requires jobs' end
        end
        if w.ace ~= nil then
            if side == 'client' then return false, 'when.ace: server slots only' end
            if type(w.ace) ~= 'string' or not w.ace:match('^aeterna%.') then
                return false, 'when.ace: must start with aeterna.'
            end
            if #w.ace > 64 then return false, 'when.ace: exceeds 64 characters' end
        end
        if w.flags ~= nil then
            if type(w.flags) ~= 'table' then return false, 'when.flags: must be array' end
            if #w.flags > 4 then return false, 'when.flags: exceeds 4 items' end
            for i = 1, #w.flags do
                local fl = w.flags[i]
                if type(fl) ~= 'string' or #fl < 1 or #fl > 32 or not fl:match('^[%w_%-]+$') then
                    return false, 'when.flags[' .. i .. ']: must be string <= 32 chars matching ^[%w_%-]+$'
                end
            end
        end
    end
    return true
end

local Registry = {}
Registry.__index = Registry

local function copyList(list)
    if list == nil then return nil end
    local out = {}
    for i = 1, #list do out[i] = list[i] end
    return out
end

-- A copy of the schema fields only: nothing a caller adds (such as a forged isGroup) is stored.
local function copyWhen(w)
    if w == nil then return nil end
    return { vehicle = w.vehicle, jobs = copyList(w.jobs), grade = w.grade, ace = w.ace, flags = copyList(w.flags) }
end

function L.createRegistry(config)
    local reg = {
        config = config or { maxPerOwner = 64, maxTotal = 128 },
        slots = { client = {}, server = {} },
        flags = {},
        remoteGroups = {}, -- client mirror only: server slots the server says are groups
    }
    return setmetatable(reg, Registry)
end

function Registry:countByOwner(owner, side)
    local s, count = side or 'client', 0
    for _ in pairs((self.slots[s] and self.slots[s][owner]) or {}) do count = count + 1 end
    return count
end

function Registry:countTotal(side)
    local s, count = side or 'client', 0
    for _, ownerSlots in pairs(self.slots[s] or {}) do
        for _ in pairs(ownerSlots) do count = count + 1 end
    end
    return count
end

function Registry:hasChildren(owner, id, side)
    for _, child in pairs((self.slots[side] and self.slots[side][owner]) or {}) do
        if child.parent == id then return true end
    end
    return false
end

-- A slot is a group while it has children. On a client mirror of server slots, the server's word also
-- counts, since a player may receive a group but none of its children (their ACE fails).
function Registry:isGroup(owner, id, side)
    return self:hasChildren(owner, id, side) or self.remoteGroups[side .. ':' .. owner .. ':' .. id] == true
end

-- `remoteGroup` is passed only by the client mirror of server slots, from the server's payload.
function Registry:addSlot(owner, slot, side, remoteGroup)
    local s = side or 'client'
    local ok, err = L.validateSlot(slot, s)
    if not ok then return false, err end

    self.slots[s] = self.slots[s] or {}
    self.slots[s][owner] = self.slots[s][owner] or {}

    if slot.parent ~= nil then
        if slot.parent == slot.id or self:hasChildren(owner, slot.id, s) then return false, 'parent: depth' end
        local parentSlot = self.slots[s][owner][slot.parent]
        if not parentSlot then return false, 'parent: unknown' end
        if parentSlot.parent ~= nil then return false, 'parent: depth' end
    end

    local existing = self.slots[s][owner][slot.id]
    if not existing then
        if self:countByOwner(owner, s) >= (self.config.maxPerOwner or 64) then
            return false, 'maxPerOwner limit reached'
        end
        if self:countTotal(s) >= (self.config.maxTotal or 128) then
            return false, 'maxTotal limit reached'
        end
    end

    self.slots[s][owner][slot.id] = {
        id = slot.id, label = slot.label, icon = slot.icon, order = slot.order, parent = slot.parent,
        when = copyWhen(slot.when), owner = owner, side = s,
    }
    self.remoteGroups[s .. ':' .. owner .. ':' .. slot.id] = remoteGroup == true or nil
    return true
end

function Registry:getSlot(owner, id, side)
    if side then return self.slots[side] and self.slots[side][owner] and self.slots[side][owner][id] end
    return (self.slots.client and self.slots.client[owner] and self.slots.client[owner][id])
        or (self.slots.server and self.slots.server[owner] and self.slots.server[owner][id])
end

function Registry:removeSlot(owner, id, side)
    local sides = side and { side } or { 'client', 'server' }
    local removed = false
    for _, s in ipairs(sides) do
        if self.slots[s] and self.slots[s][owner] and self.slots[s][owner][id] then
            self.slots[s][owner][id] = nil
            self.remoteGroups[s .. ':' .. owner .. ':' .. id] = nil
            removed = true
            for childId, childSlot in pairs(self.slots[s][owner]) do
                if childSlot.parent == id then self.slots[s][owner][childId] = nil end
            end
        end
    end
    return removed
end

function Registry:removeByOwner(owner)
    for _, side in ipairs({ 'client', 'server' }) do
        for id in pairs(self.slots[side][owner] or {}) do self.remoteGroups[side .. ':' .. owner .. ':' .. id] = nil end
        self.slots[side][owner] = nil
    end
    self.flags[owner] = nil
end

function Registry:setFlag(owner, name, value)
    self.flags[owner] = self.flags[owner] or {}
    self.flags[owner][name] = (value == true)
end

function Registry:getFlag(owner, name)
    return self.flags[owner] and self.flags[owner][name] == true or false
end

function L.buildRing(slots, ctx)
    local context = ctx or {}
    local children = context.children or {}
    local visible = {}

    for _, s in ipairs(slots) do
        if s.visible ~= false then
            local show = true
            if s.isGroup and children[s.id] then
                local anyVis = false
                for _, c in ipairs(children[s.id]) do
                    if c.visible ~= false then anyVis = true; break end
                end
                if not anyVis then show = false end
            end
            if show then visible[#visible + 1] = s end
        end
    end

    table.sort(visible, function(a, b)
        local oa, ob = a.order or 100, b.order or 100
        if oa ~= ob then return oa < ob end
        local ownA, ownB = a.owner or '', b.owner or ''
        if ownA ~= ownB then return ownA < ownB end
        return (a.id or '') < (b.id or '')
    end)

    local ringSlots = {}
    if #visible > 8 then
        local cutOwners, cutSeen = {}, {}
        for i = 9, #visible do
            local o = visible[i].owner or 'unknown'
            if not cutSeen[o] then cutSeen[o] = true; cutOwners[#cutOwners + 1] = o end
        end
        if context.warn and type(context.warn) == 'function' then
            context.warn('Radial slots cut for owners: ' .. table.concat(cutOwners, ', '))
        end
        for i = 1, 8 do ringSlots[i] = visible[i] end
    else
        for i = 1, #visible do ringSlots[i] = visible[i] end
    end

    return {
        slots = ringSlots,
        totalPositions = math.max(4, #ringSlots),
    }
end

function L.evalCondition(cond, ctx)
    if not cond then return true end
    local c = ctx or {}

    if cond.vehicle ~= nil then
        if cond.vehicle == 'in' and not c.inVehicle then return false end
        if cond.vehicle == 'out' and c.inVehicle then return false end
        if cond.vehicle == 'driver' and (not c.inVehicle or not c.isDriver) then return false end
    end

    if cond.jobs ~= nil then
        if not c.hasQbx then
            if c.warn and type(c.warn) == 'function' then c.warn('qbx_core is required for job conditions') end
            return false
        end
        local jobMatched = false
        for _, j in ipairs(cond.jobs) do
            if j == c.job then jobMatched = true; break end
        end
        if not jobMatched then return false end
        if cond.grade ~= nil and (c.grade or 0) < cond.grade then return false end
    end

    if cond.ace ~= nil then
        if type(c.can) ~= 'function' or not c.can(c.src, cond.ace) then return false end
    end

    if cond.flags ~= nil then
        for _, flagName in ipairs(cond.flags) do
            local hasFlag = false
            if type(c.flags) == 'table' then
                local scopedKey = (c.owner and (c.owner .. ':' .. flagName)) or flagName
                hasFlag = (c.flags[scopedKey] == true) or (c.flags[flagName] == true)
                    or (c.owner and type(c.flags[c.owner]) == 'table' and c.flags[c.owner][flagName] == true)
            elseif type(c.getFlag) == 'function' then
                hasFlag = (c:getFlag(c.owner, flagName) == true)
            end
            if not hasFlag then return false end
        end
    end

    return true
end

function L.angleToSlot(angle, totalPositions)
    local n = totalPositions or 4
    local step = 360 / n
    local norm = (angle % 360 + 360) % 360
    return math.floor(((norm + step / 2) % 360) / step) + 1
end

function L.pointerToSlot(dx, dy, radius, deadZone, totalPositions)
    local r, dz = radius or 150, deadZone or 0.35
    if math.sqrt(dx * dx + dy * dy) < (r * dz) then return nil end
    local angle = math.deg(math.atan(dx, -dy))
    return L.angleToSlot(angle, totalPositions)
end

function L.stickToSlot(x, y, deadZone, totalPositions)
    local dz = deadZone or 0.35
    if math.sqrt(x * x + y * y) < dz then return nil end
    local angle = math.deg(math.atan(x, -y))
    return L.angleToSlot(angle, totalPositions)
end

local function withoutFlags(when)
    if when and when.flags then
        return { vehicle = when.vehicle, jobs = when.jobs, grade = when.grade, ace = when.ace }
    end
    return when
end

-- Server re-check of a pick. Groups open rings and are never picked. A child must also pass its group's
-- conditions (depth is 1). Flags live on the client, so the server skips them and the owner re-checks its
-- own state in its handler.
function L.handleServerPick(src, owner, id, registry, ctx)
    if not registry or type(registry.getSlot) ~= 'function' then return false end
    local slot = registry:getSlot(owner, id, 'server')
    if not slot or registry:isGroup(owner, id, 'server') then return false end
    local c = ctx or {}
    c.src, c.owner = src, owner
    if slot.parent ~= nil then
        local parent = registry:getSlot(owner, slot.parent, 'server')
        if not parent or not L.evalCondition(withoutFlags(parent.when), c) then return false end
    end
    if not L.evalCondition(withoutFlags(slot.when), c) then return false end
    return true, { owner = owner, id = id }
end

local function sameParent(slot, side, parent)
    if parent == nil then return slot.parent == nil end
    return slot.parent == parent.id and slot.owner == parent.owner and side == parent.side
end

local function slotKey(slot)
    return tostring(slot.side) .. ':' .. tostring(slot.owner) .. ':' .. tostring(slot.id)
end

-- The ring for `parent` (nil = root, else a ring entry of a group) across registries. `ctx` holds the
-- condition inputs (inVehicle, isDriver, hasQbx, job, grade, flags = owner -> name -> bool) and an
-- optional warn, called at most once per slot for a missing qbx_core.
function L.ringFor(registries, parent, ctx)
    local base = ctx or {}
    base.warned = base.warned or {}

    local function visible(slot)
        local c = {
            inVehicle = base.inVehicle, isDriver = base.isDriver,
            hasQbx = base.hasQbx, job = base.job, grade = base.grade,
            owner = slot.owner, flags = base.flags,
        }
        if base.warn then
            local key = slotKey(slot)
            c.warn = function(msg)
                if not base.warned[key] then
                    base.warned[key] = true
                    base.warn(msg .. ' (' .. key .. ')')
                end
            end
        end
        return L.evalCondition(slot.when, c)
    end

    local function children(groupSide, group)
        local out = {}
        for _, reg in ipairs(registries) do
            for owner, slots in pairs((reg.slots and reg.slots[groupSide]) or {}) do
                if owner == group.owner then
                    for _, s in pairs(slots) do
                        if s.parent == group.id then out[#out + 1] = s end
                    end
                end
            end
        end
        return out
    end

    local entries = {}
    for _, reg in ipairs(registries) do
        for side, owners in pairs(reg.slots or {}) do
            for _, slots in pairs(owners) do
                for _, s in pairs(slots) do
                    if sameParent(s, side, parent) then
                        local show = visible(s)
                        local isGroup = reg:isGroup(s.owner, s.id, side)
                        if show and isGroup then
                            show = false
                            for _, child in ipairs(children(side, s)) do
                                if visible(child) then show = true; break end
                            end
                        end
                        entries[#entries + 1] = {
                            owner = s.owner, side = side, id = s.id, label = s.label, icon = s.icon,
                            order = s.order, when = s.when, isGroup = isGroup, visible = show,
                        }
                    end
                end
            end
        end
    end
    return L.buildRing(entries, { warn = base.warn })
end

-- The visible slot at a 1-based ring index, or nil (empty position, wrong type, out of range).
function L.slotAt(ring, index)
    if not ring or type(index) ~= 'number' or index ~= math.floor(index) or index < 1 then return nil end
    return ring.slots[math.tointeger(index)]
end

-- What the NUI draws for each slot: nothing that names an owner or a condition.
function L.nuiSlots(ring)
    local out = {}
    for i, s in ipairs((ring and ring.slots) or {}) do
        out[i] = { label = s.label, icon = s.icon, group = s.isGroup == true }
    end
    return out
end

-- Moves the highlight one step (dir 1 = clockwise, -1 = back) over `count` visible slots.
function L.stepIndex(current, count, dir)
    if type(count) ~= 'number' or count < 1 then return nil end
    if current == nil then return dir < 0 and count or 1 end
    return ((current - 1 + dir) % count) + 1
end

-- Copy of a stored slot for a client: owner and group mark included, side and ace left out.
function L.publicSlot(stored, isGroup)
    local out = {
        owner = stored.owner, id = stored.id, label = stored.label, icon = stored.icon,
        order = stored.order, parent = stored.parent, isGroup = isGroup == true or nil,
    }
    if stored.when then
        local w = stored.when
        out.when = { vehicle = w.vehicle, jobs = w.jobs, grade = w.grade, flags = w.flags }
    end
    return out
end

-- Public copies of the slots of one side, roots before children so a receiving registry finds each
-- parent first. `filter(stored)` (optional) keeps a slot when it returns true.
function L.listSlots(registry, side, filter)
    local roots, kids = {}, {}
    for _, slots in pairs((registry.slots and registry.slots[side]) or {}) do
        for _, s in pairs(slots) do
            if filter == nil or filter(s) then
                local bucket = s.parent == nil and roots or kids
                bucket[#bucket + 1] = s
            end
        end
    end
    local function byKey(a, b)
        if a.owner ~= b.owner then return a.owner < b.owner end
        return a.id < b.id
    end
    table.sort(roots, byKey)
    table.sort(kids, byKey)
    local out = {}
    for i = 1, #roots do out[#out + 1] = L.publicSlot(roots[i], registry:isGroup(roots[i].owner, roots[i].id, side)) end
    for i = 1, #kids do out[#out + 1] = L.publicSlot(kids[i]) end
    return out
end

-- Config.deadZone must be a fraction in 0-1; anything else falls back to 0.35 with a warn.
function L.checkDeadZone(value, warn)
    if type(value) == 'number' and value >= 0 and value <= 1 then return value end
    if warn then warn('Config.deadZone must be a number from 0 to 1; using 0.35') end
    return 0.35
end

return RadialLogic
