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

function L.createRegistry(config)
    local reg = {
        config = config or { maxPerOwner = 64, maxTotal = 128 },
        slots = { client = {}, server = {} },
        flags = {},
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

function Registry:addSlot(owner, slot, side)
    local s = side or 'client'
    local ok, err = L.validateSlot(slot, s)
    if not ok then return false, err end

    self.slots[s] = self.slots[s] or {}
    self.slots[s][owner] = self.slots[s][owner] or {}

    if slot.parent ~= nil then
        local parentSlot = self.slots[s][owner] and self.slots[s][owner][slot.parent]
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

    local stored = {}
    for k, v in pairs(slot) do stored[k] = v end
    stored.owner, stored.side = owner, s
    if existing and existing.isGroup then stored.isGroup = true end
    if slot.parent ~= nil then
        self.slots[s][owner][slot.parent].isGroup = true
    end

    self.slots[s][owner][slot.id] = stored
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
            removed = true
            for childId, childSlot in pairs(self.slots[s][owner]) do
                if childSlot.parent == id then self.slots[s][owner][childId] = nil end
            end
        end
    end
    return removed
end

function Registry:removeByOwner(owner)
    if self.slots.client then self.slots.client[owner] = nil end
    if self.slots.server then self.slots.server[owner] = nil end
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

    if cond.ace ~= nil and c.can and type(c.can) == 'function' then
        if not c.can(c.src or 1, cond.ace) then return false end
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

function L.handleServerPick(src, owner, id, registry, ctx)
    if not registry or type(registry.getSlot) ~= 'function' then return false end
    local slot = registry:getSlot(owner, id, 'server')
    if not slot then return false end
    local c = ctx or {}
    c.src, c.owner = src, owner
    if not L.evalCondition(slot.when, c) then return false end
    return true, { owner = owner, id = id }
end

return RadialLogic
