-- aeterna_radial server: server slot registry, per-player delivery by ACE, and the re-check of every pick.

local L = RadialLogic
local registry = L.createRegistry({ maxPerOwner = Config.maxPerOwner, maxTotal = Config.maxTotal })

local SELECT_SCHEMA = { type = 'table', extra = false, fields = {
    owner = { type = 'string', maxLen = 64 },
    id = { type = 'string', maxLen = 32 },
} }

local function invoker()
    return GetInvokingResource() or GetCurrentResourceName()
end

local function passesAce(src, slot)
    local ace = slot.when and slot.when.ace
    return ace == nil or AeternaCore.can(src, ace)
end

local function sendSlot(src, msg)
    TriggerClientEvent('aeterna_radial:cl:slot', src, msg)
end

local function qbxJob(src)
    if GetResourceState('qbx_core') ~= 'started' then return nil end
    local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    local job = ok and type(player) == 'table' and player.PlayerData and player.PlayerData.job
    if type(job) ~= 'table' then return nil end
    return job.name, type(job.grade) == 'table' and tonumber(job.grade.level) or 0
end

local function pickContext(src)
    local ped = GetPlayerPed(src)
    local veh = ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    local ctx = {
        inVehicle = veh ~= 0,
        isDriver = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped,
        can = AeternaCore.can,
        hasQbx = false,
    }
    local job, grade = qbxJob(src)
    if job then
        ctx.hasQbx, ctx.job, ctx.grade = true, job, grade
    end
    return ctx
end

-- Sends one stored slot to every client that may see it. `hadAce` says an earlier copy was ACE-limited,
-- so players who no longer pass drop it.
local function deliver(owner, stored, hadAce)
    local msg = { op = 'add', owner = owner, slot = L.publicSlot(stored, registry:isGroup(owner, stored.id, 'server')) }
    if not hadAce and not (stored.when and stored.when.ace) then
        sendSlot(-1, msg)
        return
    end
    local gone = { op = 'remove', owner = owner, id = stored.id }
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        sendSlot(src, passesAce(src, stored) and msg or gone)
    end
end

local function hasAce(stored)
    return stored ~= nil and stored.when ~= nil and stored.when.ace ~= nil
end

exports('addSlot', function(slot)
    local owner = invoker()
    local id = type(slot) == 'table' and slot.id or nil
    local parentId = type(slot) == 'table' and slot.parent or nil
    local hadAce = hasAce(registry:getSlot(owner, id, 'server'))
    local parentWasGroup = type(parentId) == 'string' and registry:isGroup(owner, parentId, 'server')
    local ok, err = registry:addSlot(owner, slot, 'server')
    if not ok then
        AeternaCore.log.warn('refused server slot', { owner = owner, err = err })
        return false, err
    end
    -- A parent that just became a group is sent again with its group mark, before its first child.
    if parentId ~= nil and not parentWasGroup then
        local parent = registry:getSlot(owner, parentId, 'server')
        deliver(owner, parent, hasAce(parent))
    end
    deliver(owner, registry:getSlot(owner, id, 'server'), hadAce)
    return true
end)

exports('removeSlot', function(id)
    local owner = invoker()
    local stored = type(id) == 'string' and registry:getSlot(owner, id, 'server') or nil
    if not stored or not registry:removeSlot(owner, id, 'server') then return false end
    sendSlot(-1, { op = 'remove', owner = owner, id = id })
    -- A parent whose last child left is an ordinary slot again.
    if stored.parent ~= nil and not registry:isGroup(owner, stored.parent, 'server') then
        local parent = registry:getSlot(owner, stored.parent, 'server')
        if parent then deliver(owner, parent, hasAce(parent)) end
    end
    return true
end)

RegisterNetEvent('aeterna_radial:sv:hello', function()
    local src = source
    if not AeternaCore.rateLimit(src, 'radial:hello', 2, 5000) then return end
    local slots = L.listSlots(registry, 'server', function(stored) return passesAce(src, stored) end)
    TriggerClientEvent('aeterna_radial:cl:slots', src, { slots = slots })
end)

RegisterNetEvent('aeterna_radial:sv:select', function(payload)
    local src = source
    if not AeternaCore.rateLimit(src, 'radial:select', 4, 1000) then return end
    local ok, err, data = AeternaCore.validate(payload, SELECT_SCHEMA)
    if not ok then
        AeternaCore.log.warn('dropped aeterna_radial:sv:select', { src = src, err = err })
        return
    end
    local picked, result = L.handleServerPick(src, data.owner, data.id, registry, pickContext(src))
    if not picked then
        AeternaCore.log.debug('dropped pick that failed its checks', { src = src, owner = data.owner, id = data.id })
        return
    end
    TriggerEvent('aeterna_radial:select', src, result)
end)

AddEventHandler('onResourceStop', function(resource)
    local owned = registry.slots.server[resource]
    if not owned then return end
    local roots = {}
    for id, stored in pairs(owned) do
        if stored.parent == nil then roots[#roots + 1] = id end
    end
    registry:removeByOwner(resource)
    -- Removing a root on the client takes its children with it.
    for i = 1, #roots do
        sendSlot(-1, { op = 'remove', owner = resource, id = roots[i] })
    end
end)
