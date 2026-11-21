-- aeterna_radial client: client slots and flags, the mirror of server slots, focus, input and the NUI bridge.

local L, I = RadialLogic, RadialInput
local RESOURCE = GetCurrentResourceName()
local LIMITS = { maxPerOwner = Config.maxPerOwner, maxTotal = Config.maxTotal }
local MAX_FLAGS = 32
local LOCALE_KEYS = { 'radial.back', 'radial.close', 'radial.denied', 'radial.empty' }
local PAUSED_WAIT_MS = 250
local HELLO_RETRY_MS = 3000
local DEAD_ZONE = L.checkDeadZone(Config.deadZone, AeternaCore.log.warn)

local clientReg = L.createRegistry(LIMITS)
local serverReg = L.createRegistry(LIMITS)
local warnedJobs = {}  -- slot key -> true, so a jobs slot without qbx_core warns once
local menu = nil       -- { mode, token, session, ring, parent, parentIndex, hover, holding, paused }
local session = 0
local slotsReceived = false

local function send(msg)
    SendNUIMessage(msg)
end

local function vehicleState(ped)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return 'out', 0 end
    return GetPedInVehicleSeat(veh, -1) == ped and 'driver' or 'in', veh
end

local function conditionContext()
    local state = vehicleState(PlayerPedId())
    local ctx = {
        inVehicle = state ~= 'out',
        isDriver = state == 'driver',
        hasQbx = GetResourceState('qbx_core') == 'started',
        flags = clientReg.flags,
        warned = warnedJobs,
        warn = function(msg) AeternaCore.log.warn(msg) end,
    }
    if ctx.hasQbx then
        local ok, data = pcall(function() return exports.qbx_core:GetPlayerData() end)
        local job = ok and type(data) == 'table' and data.job
        if type(job) == 'table' then
            ctx.job = job.name
            ctx.grade = type(job.grade) == 'table' and tonumber(job.grade.level) or 0
        end
    end
    return ctx
end

local function buildRing(parent)
    return L.ringFor({ clientReg, serverReg }, parent, conditionContext())
end

local function render()
    local slots = L.nuiSlots(menu.ring)
    if menu.parent then
        send({ type = 'ring:child', groupId = menu.parent.id, slots = slots })
    else
        send({ type = 'ring:open', slots = slots, mode = menu.mode, radius = Config.radius, deadZone = DEAD_ZONE })
    end
    send({ type = 'ring:hover', index = menu.hover or 0 })
end

local function setHover(index, tellNui)
    local hover = L.slotAt(menu.ring, index) and index or nil
    if hover == menu.hover then return end
    menu.hover = hover
    if tellNui then send({ type = 'ring:hover', index = hover or 0 }) end
end

local function sameSlot(a, b)
    return a.side == b.side and a.owner == b.owner and a.id == b.id
end

-- Rebuilds the open ring after slots, flags or the vehicle changed. A group that went away returns to the root.
local function refresh()
    if not menu then return end
    if menu.parent then
        local root, found = buildRing(nil), nil
        for i, entry in ipairs(root.slots) do
            if sameSlot(entry, menu.parent) then found = i end
        end
        if found then
            menu.parent, menu.parentIndex = root.slots[found], found
        else
            menu.parent, menu.parentIndex = nil, nil
        end
    end
    menu.ring = buildRing(menu.parent)
    if not L.slotAt(menu.ring, menu.hover) then menu.hover = nil end
    render()
end

local function close()
    if not menu then return end
    local token, paused = menu.token, menu.paused
    menu = nil
    send({ type = 'ring:close' })
    pcall(function() exports.aeterna_uikit:clearKeyHints() end)
    if not token then return end
    if paused then
        -- The overlay holder owns the NUI natives now: give the token back without clearing them.
        pcall(function() exports.aeterna_core:releaseFocus(token) end)
    else
        AeternaCore.releaseFocus(token)
    end
end

local function denied()
    send({ type = 'ring:denied' })
    if menu.mode == 'hold' and not menu.holding then
        local s = menu.session
        SetTimeout(1000, function()
            if menu and menu.session == s then close() end
        end)
    end
end

local function pick(index)
    local entry = L.slotAt(menu.ring, index)
    if not entry then return end
    if entry.isGroup then
        menu.parent, menu.parentIndex, menu.hover, menu.holding = entry, index, nil, false
        menu.ring = buildRing(entry)
        render()
        return
    end
    -- Conditions may have changed since the ring was drawn (got out of the car, a flag flipped).
    local ctx = conditionContext()
    ctx.owner, ctx.warn = entry.owner, nil
    if not L.evalCondition(entry.when, ctx) then
        denied()
        return
    end
    close()
    if entry.side == 'server' then
        TriggerServerEvent('aeterna_radial:sv:select', { owner = entry.owner, id = entry.id })
    else
        TriggerEvent('aeterna_radial:select', entry.owner, entry.id)
    end
end

local function back()
    if not menu.parent then
        close()
        return
    end
    local groupIndex = menu.parentIndex
    menu.parent, menu.parentIndex = nil, nil
    menu.ring = buildRing(nil)
    menu.hover = L.slotAt(menu.ring, groupIndex) and groupIndex or nil
    render()
end

local function handleInput(input)
    if input.escape then return close() end
    if input.cancel then return back() end
    if not IsUsingKeyboard(0) then
        local idx = L.stickToSlot(input.x, input.y, DEAD_ZONE, menu.ring.totalPositions)
        if idx then setHover(idx, true) end
    end
    if input.left or input.right then
        setHover(L.stepIndex(menu.hover, #menu.ring.slots, input.left and -1 or 1), true)
    end
    if input.accept and menu.hover and not menu.holding then pick(menu.hover) end
end

local function canOpen()
    if Config.whileDead then return true end
    local ped = PlayerPedId()
    return not IsEntityDead(ped) and not IsPedRagdoll(ped)
end

local function frameLoop(s)
    local lastVehicle = nil
    while menu and menu.session == s do
        if menu.paused then
            Wait(PAUSED_WAIT_MS)
        elseif not canOpen() then
            close()
        else
            I.disableFrame()
            local state = vehicleState(PlayerPedId())
            if lastVehicle and state ~= lastVehicle then refresh() end
            lastVehicle = state
            handleInput(I.read())
            Wait(0)
        end
    end
end

local function showHints()
    -- uikit hints name a command; only the hold-mode pick (release the open key) has one.
    if menu.mode ~= 'hold' then return end
    pcall(function()
        exports.aeterna_uikit:keyHints({ { key = '+aeterna_radial_open', label = AeternaCore.t('radial.hint.pick') } })
    end)
end

local function open(mode)
    if menu or not canOpen() then return end
    local token = AeternaCore.requestFocus({ cursor = true, keyboard = false, keepGameInput = true })
    if not token then return end
    session = session + 1
    menu = { mode = mode, token = token, session = session, holding = mode == 'hold' }
    menu.ring = buildRing(nil)
    local strings = {}
    for i = 1, #LOCALE_KEYS do strings[LOCALE_KEYS[i]] = AeternaCore.t(LOCALE_KEYS[i]) end
    send(AeternaCore.themeMessage())
    send({ type = 'locale', strings = strings })
    render()
    showHints()
    local s = session
    CreateThread(function() frameLoop(s) end)
end

local function pressOpen(mode)
    if menu then
        if not menu.holding and not menu.paused then close() end
        return
    end
    open(mode)
end

RegisterCommand('aeterna_radial_open', function() pressOpen('toggle') end, false)
RegisterCommand('+aeterna_radial_open', function() pressOpen(Config.mode == 'toggle' and 'toggle' or 'hold') end, false)
RegisterCommand('-aeterna_radial_open', function()
    if not menu or not menu.holding then return end
    menu.holding = false
    if menu.paused then return end
    if menu.hover then pick(menu.hover) else close() end
end, false)

AeternaCore.key('+aeterna_radial_open', 'radial.key.open')
RegisterKeyMapping('+aeterna_radial_open', AeternaCore.t('radial.key.open'), 'PAD_DIGITALBUTTON', '')

-- NUI callbacks. Each is validated; an index that does not map to a visible slot is dropped.
local function indexSchema(min)
    return { type = 'table', extra = false, fields = { index = { type = 'number', integer = true, min = min, max = 8 } } }
end
local HOVER_SCHEMA, PICK_SCHEMA = indexSchema(0), indexSchema(1)
local EMPTY_SCHEMA = { type = 'table', extra = false, fields = {} }

local function accepts(name, data, schema)
    if not menu or menu.paused then return false end
    local ok, err = AeternaCore.validate(data, schema)
    if not ok then AeternaCore.log.warn('dropped NUI callback', { name = name, err = err }) end
    return ok
end

RegisterNUICallback('hover', function(data, cb)
    cb({})
    if not accepts('hover', data, HOVER_SCHEMA) then return end
    if data.index == 0 or L.slotAt(menu.ring, data.index) then setHover(data.index, false) end
end)

RegisterNUICallback('pick', function(data, cb)
    cb({})
    if accepts('pick', data, PICK_SCHEMA) then pick(data.index) end
end)

RegisterNUICallback('back', function(data, cb)
    cb({})
    if accepts('back', data, EMPTY_SCHEMA) then back() end
end)

RegisterNUICallback('escape', function(data, cb)
    cb({})
    if accepts('escape', data, EMPTY_SCHEMA) then close() end
end)

-- Focus from aeterna_core: lost closes with no pick; an overlay pauses the menu until it resumes.
AddEventHandler('aeterna_core:focusLost', function(owner, token)
    if owner == RESOURCE and menu and menu.token == token then
        menu.token = nil
        close()
    end
end)

AddEventHandler('aeterna_core:focusPaused', function(owner)
    if owner == RESOURCE and menu then menu.paused = true end
end)

AddEventHandler('aeterna_core:focusResumed', function(owner, token)
    if owner == RESOURCE and menu and menu.token == token then menu.paused = false end
end)

-- Server slots: the full list on hello, then one add or remove at a time.
RegisterNetEvent('aeterna_radial:cl:slots', function(payload)
    if type(payload) ~= 'table' or type(payload.slots) ~= 'table' or #payload.slots > Config.maxTotal then return end
    slotsReceived = true
    serverReg = L.createRegistry(LIMITS)
    for pass = 1, 2 do
        for _, slot in ipairs(payload.slots) do
            if type(slot) == 'table' and type(slot.owner) == 'string' and (slot.parent == nil) == (pass == 1) then
                local ok, err = serverReg:addSlot(slot.owner, slot, 'server', slot.isGroup == true)
                if not ok then AeternaCore.log.debug('ignored server slot', { owner = slot.owner, err = err }) end
            end
        end
    end
    refresh()
end)

RegisterNetEvent('aeterna_radial:cl:slot', function(msg)
    if type(msg) ~= 'table' or type(msg.owner) ~= 'string' then return end
    if msg.op == 'add' and type(msg.slot) == 'table' then
        local ok, err = serverReg:addSlot(msg.owner, msg.slot, 'server', msg.slot.isGroup == true)
        if not ok then
            AeternaCore.log.debug('ignored server slot', { owner = msg.owner, err = err })
            return
        end
    elseif msg.op == 'remove' and type(msg.id) == 'string' then
        if not serverReg:removeSlot(msg.owner, msg.id, 'server') then return end
    else
        return
    end
    refresh()
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == RESOURCE then
        close()
        return
    end
    clientReg:removeByOwner(resource)
    serverReg:removeByOwner(resource)
    refresh()
end)

exports('addSlot', function(slot)
    local owner = GetInvokingResource() or RESOURCE
    local ok, err = clientReg:addSlot(owner, slot, 'client')
    if not ok then
        AeternaCore.log.warn('refused client slot', { owner = owner, err = err })
        return false, err
    end
    refresh()
    return true
end)

exports('removeSlot', function(id)
    local owner = GetInvokingResource() or RESOURCE
    if type(id) ~= 'string' or not clientReg:removeSlot(owner, id, 'client') then return false end
    refresh()
    return true
end)

exports('setFlag', function(name, value)
    local owner = GetInvokingResource() or RESOURCE
    if type(name) ~= 'string' or #name < 1 or #name > 32 or not name:match('^[%w_%-]+$') or type(value) ~= 'boolean' then
        AeternaCore.log.warn('refused flag', { owner = owner, name = tostring(name) })
        return nil
    end
    local owned = clientReg.flags[owner] or {}
    if owned[name] == nil then
        local count = 0
        for _ in pairs(owned) do count = count + 1 end
        if count >= MAX_FLAGS then
            AeternaCore.log.warn('refused flag: more than 32 for this owner', { owner = owner, name = name })
            return nil
        end
    end
    if owned[name] == value then return nil end
    clientReg:setFlag(owner, name, value)
    refresh()
    return nil
end)

exports('isOpen', function()
    return menu ~= nil
end)

exports('close', function()
    close()
    return nil
end)

-- Ask for the server slots; ask once more if the first answer is lost (sv:hello allows 2 per 5 s).
CreateThread(function()
    TriggerServerEvent('aeterna_radial:sv:hello')
    Wait(HELLO_RETRY_MS)
    if not slotsReceived then TriggerServerEvent('aeterna_radial:sv:hello') end
end)
