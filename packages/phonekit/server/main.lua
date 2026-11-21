-- server/main.lua -- aeterna_phonekit server: app registry, app screen lifecycle, badge tracking, opening check
-- controller, and rate-limited net events. 0.2: device modes, the battery, the ring screen, contact intents.

local L = PhoneLogic
local D = DeviceLogic
local B = BatteryLogic
local H = HooksLogic

local function logWarn(msg, fields)
    if AeternaCore and AeternaCore.log and type(AeternaCore.log.warn) == 'function' then
        AeternaCore.log.warn(msg, fields)
    end
end

local function translate(key, vars)
    if AeternaCore and type(AeternaCore.t) == 'function' then
        return AeternaCore.t(key, vars)
    end
    return key
end

local Cfg = type(Config) == 'table' and Config or {}
local MODE = D.resolveMode(Cfg.devices)
local SINGLE_ID = 'single'
local SINGLE_MODEL = D.MODELS[Cfg.singleModel] and Cfg.singleModel or 'slab'
if Cfg.singleModel ~= nil and not D.MODELS[Cfg.singleModel] then
    logWarn('phonekit Config.singleModel is not a model id, using slab', { value = tostring(Cfg.singleModel) })
end
local batteryCfg = B.validateConfig(Cfg.battery, function(key)
    logWarn('phonekit Config.battery value out of range, using the default', { key = key })
end)

local registry = L.createAppRegistry({
    maxApps = tonumber(Cfg.maxApps) or 24,
})

local badgeMgr = L.createBadgeManager()

local openingMgr = L.createOpeningCheckManager({
    setTimeout = type(SetTimeout) == 'function' and SetTimeout or nil,
    clearTimeout = type(ClearTimeout) == 'function' and ClearTimeout or nil,
})

local intents = H.createIntents(logWarn)

local function nowSec()
    return (type(GetGameTimer) == 'function' and GetGameTimer() or 0) / 1000
end

local rings = H.createRingManager({ now = nowSec })

local playerScreens = {}

local function getCurrentScreen(src)
    local stack = playerScreens[src]
    if stack and #stack > 0 then
        return stack[#stack]
    end
    return nil
end

local function selfName()
    if type(GetCurrentResourceName) == 'function' then
        local n = GetCurrentResourceName()
        if type(n) == 'string' and n ~= '' then
            return n
        end
    end
    return 'aeterna_phonekit'
end

local function callerResource()
    if type(GetInvokingResource) == 'function' then
        local inv = GetInvokingResource()
        if type(inv) == 'string' and inv ~= '' then
            return inv
        end
    end
    return selfName()
end

local function canPlayerAccess(src, ace)
    if not ace or ace == '' then return true end
    if AeternaCore and type(AeternaCore.can) == 'function' then
        return AeternaCore.can(src, ace)
    end
    return false
end

local function validate(value, schema)
    if AeternaCore and type(AeternaCore.validate) == 'function' then
        return AeternaCore.validate(value, schema)
    end
    return type(value) == 'table', 'payload: type', value
end

local COVER = Cfg.cover ~= false

local function modelInfo(modelId)
    return D.resolveModel(modelId, Cfg.models, { names = Cfg.names, t = translate, prop = Cfg.prop })
end

--------------------------------------------------------------------------------
-- Device state (0.2)
--------------------------------------------------------------------------------

-- players[src] = { who, devices = { {id, model, color} }, active = id, chosen = id, states = { [id] = battery },
--   folds = { [id] = fold }, pulse = { level, at }, chargers = { [res:id] = sec }, calls = { [res] = true },
--   charging = bool, live = { owner, id, text } }
local players = {}
local loaded = {}

local function readKvp(key)
    if type(GetResourceKvpString) ~= 'function' then return nil end
    local raw = GetResourceKvpString(key)
    if type(raw) ~= 'string' or raw == '' then return nil end
    local ok, val = pcall(json.decode, raw)
    if ok then return val end
    return nil
end

local function writeKvp(key, value)
    if type(SetResourceKvp) ~= 'function' then return end
    local ok, encoded = pcall(json.encode, value)
    if ok and type(encoded) == 'string' then
        SetResourceKvp(key, encoded)
    end
end

local function qbxStarted()
    return type(GetResourceState) == 'function' and GetResourceState('qbx_core') == 'started'
end

-- `<who>`: nil while qbx_core runs and no character is loaded yet.
local function whoOf(src)
    local cid
    if qbxStarted() then
        local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
        if ok and type(player) == 'table' and type(player.PlayerData) == 'table' then
            cid = player.PlayerData.citizenid
        end
        if type(cid) ~= 'string' or cid == '' then return nil end
    end
    local license
    if type(GetPlayerIdentifierByType) == 'function' then
        local ok, id = pcall(GetPlayerIdentifierByType, src, 'license')
        if ok then license = id end
    end
    return D.whoKey(cid, license)
end

local function activeOf(p)
    if not p or not p.active then return nil end
    for _, d in ipairs(p.devices) do
        if d.id == p.active then return d end
    end
    return nil
end

local function ensureLoaded(src)
    local p = players[src]
    if p then return p end
    local who = whoOf(src)
    if not who then return nil end
    p = { who = who, devices = {}, states = {}, folds = {}, pulse = { level = 'off', at = 0 }, chargers = {},
        calls = {}, charging = false }
    if MODE == 'single' then
        local saved = readKvp('aeterna_phonekit:device:v1:' .. who)
        saved = type(saved) == 'table' and saved or {}
        p.devices = { { id = SINGLE_ID, model = SINGLE_MODEL, color = 0 } }
        p.active = SINGLE_ID
        p.states[SINGLE_ID] = B.createState(tonumber(saved.battery) or (batteryCfg and batteryCfg.startPct or 100))
        p.folds[SINGLE_ID] = D.validateFold(SINGLE_MODEL, saved.fold, COVER)
    else
        local chosen = readKvp('aeterna_phonekit:active:v1:' .. who)
        p.chosen = type(chosen) == 'string' and chosen or nil
    end
    players[src] = p
    loaded[src] = true
    return p
end

local function isDead(src)
    if not batteryCfg then return false end
    local p = players[src]
    local dev = activeOf(p)
    local st = dev and p.states[dev.id]
    return st ~= nil and st.dead == true
end

local function saveDevice(src)
    local p = players[src]
    local dev = activeOf(p)
    if not dev then return end
    local st = p.states[dev.id]
    if MODE == 'single' then
        writeKvp('aeterna_phonekit:device:v1:' .. p.who, { battery = st and st.pct or nil, fold = p.folds[dev.id] })
    else
        TriggerEvent('aeterna_phonekit:deviceSave', src, {
            id = dev.id,
            battery = (batteryCfg and st) and st.pct or nil,
            fold = p.folds[dev.id],
        })
    end
end

local function sendBattery(src)
    local p = players[src]
    local dev = activeOf(p)
    local st = dev and p.states[dev.id]
    if not batteryCfg or not st then
        TriggerClientEvent('aeterna_phonekit:cl:battery', src, { none = true })
        return
    end
    TriggerClientEvent('aeterna_phonekit:cl:battery', src, { pct = st.shown, charging = p.charging == true })
end

local function deviceList(p)
    local list = {}
    for _, d in ipairs(p.devices) do
        local st = p.states[d.id]
        list[#list + 1] = {
            id = d.id,
            label = modelInfo(d.model).label,
            battery = (batteryCfg and st) and st.shown or nil,
            active = d.id == p.active,
        }
    end
    return list
end

local function sendDevice(src)
    local p = players[src]
    local dev = activeOf(p)
    if not dev and MODE == 'single' then
        -- not loaded yet (no character): the single model with its defaults
        p = { folds = { [SINGLE_ID] = D.validateFold(SINGLE_MODEL, nil, COVER) }, states = {}, devices = {} }
        dev = { id = SINGLE_ID, model = SINGLE_MODEL, color = 0 }
    end
    if not dev then
        TriggerClientEvent('aeterna_phonekit:cl:device', src, { devices = {} })
        return
    end
    local info = modelInfo(dev.model)
    TriggerClientEvent('aeterna_phonekit:cl:device', src, {
        model = dev.model,
        label = info.label,
        fold = p.folds[dev.id],
        voice = info.voice,
        color = D.colorAt(dev.model, Cfg.models, dev.color),
        devices = MODE == 'items' and deviceList(p) or {},
    })
end

-- Closes every phone surface on the server side: the app on screen gets `__close`, the ring card goes.
local function closeServerSide(src)
    local current = getCurrentScreen(src)
    playerScreens[src] = nil
    badgeMgr:setPhoneOpen(src, false)
    badgeMgr:setCurrentApp(src, nil)
    local r = rings:current(src)
    if r then
        rings:stop(src, r.ringId)
        TriggerClientEvent('aeterna_phonekit:cl:ringStop', src, { ringId = r.ringId })
    end
    if current then
        TriggerEvent('aeterna_phonekit:action', src, {
            owner = current.owner, id = current.id, screenId = current.screenId, action = '__close', values = {},
        })
    end
end

local function setPower(src, on)
    TriggerClientEvent('aeterna_phonekit:cl:power', src, { on = on })
    TriggerEvent('aeterna_phonekit:power', src, { on = on })
    if not on then
        closeServerSide(src)
    end
end

local function warnLow(src, pct)
    local title = translate('phonekit.battery.low', { pct = pct })
    if badgeMgr:isPhoneOpen(src) then
        TriggerClientEvent('aeterna_phonekit:cl:banner', src, { id = 'battery', title = title, body = '' })
    else
        pcall(function()
            exports.aeterna_notify:notify(src, { title = title, type = 'warning', icon = 'alert-triangle' })
        end)
    end
end

local function applyBatteryEvents(src, ev, chargingChanged)
    if ev.changed or chargingChanged then sendBattery(src) end
    if ev.save then saveDevice(src) end
    for _, pct in ipairs(ev.warn) do warnLow(src, pct) end
    if ev.power ~= nil then setPower(src, ev.power) end
end

-- After the active device changed: tell the client when the phone's power state changed with it.
local function syncPowerAfterSwitch(src, wasDead)
    local dead = isDead(src)
    if dead ~= wasDead then
        setPower(src, not dead)
    end
end

-- A gate answer arrived: keep the carried devices, pick the active one, close surfaces if it is gone.
-- The active phone keeps the number the server counts; every other phone takes the battery and fold from its
-- item (it may have been handed away and back), and phones no longer carried are forgotten.
local function applyDevices(src, devices)
    local p = players[src]
    if not p then return end
    local before = p.active
    local wasDead = isDead(src)
    local carried = {}
    p.devices = {}
    for _, d in ipairs(devices or {}) do
        carried[d.id] = true
        p.devices[#p.devices + 1] = { id = d.id, model = d.model, color = d.color }
        local missingBattery = false
        if d.id == before and p.states[d.id] then
            p.folds[d.id] = D.validateFold(d.model, p.folds[d.id], COVER)
        else
            if d.battery ~= nil then
                p.states[d.id] = B.createState(d.battery)
            elseif not p.states[d.id] then
                p.states[d.id] = B.createState(batteryCfg and batteryCfg.startPct or 100)
                missingBattery = batteryCfg ~= false
            end
            p.folds[d.id] = D.validateFold(d.model, d.fold or p.folds[d.id], COVER)
        end
        if missingBattery then
            -- a phone with no battery in its item gets startPct written back once
            TriggerEvent('aeterna_phonekit:deviceSave', src, {
                id = d.id, battery = p.states[d.id].pct, fold = p.folds[d.id],
            })
        end
    end
    for id in pairs(p.states) do
        if not carried[id] then p.states[id] = nil end
    end
    for id in pairs(p.folds) do
        if not carried[id] then p.folds[id] = nil end
    end
    local pick = D.pickActiveDevice(p.devices, p.chosen)
    p.active = pick and pick.id or nil
    if before and before ~= p.active then
        -- The active phone is gone: every surface closes (an empty device message), the battery is not marked dead.
        closeServerSide(src)
        TriggerClientEvent('aeterna_phonekit:cl:device', src, { devices = {} })
    end
    sendDevice(src)
    sendBattery(src)
    if before ~= p.active then
        syncPowerAfterSwitch(src, wasDead)
    end
end

-- Asks other resources before the phone opens (Config.ask, and always in items mode).
local function askGate(src, onDone)
    local items = MODE == 'items'
    if not items and Cfg.ask ~= true then
        onDone(true)
        return
    end
    local checkId = openingMgr:createCheck(src, function(target, allowed, reason, devices)
        if items then
            if allowed and devices then
                applyDevices(target, devices)
            else
                applyDevices(target, {})
                if allowed or not reason or reason == 'phonekit.refused.default' then
                    reason = 'phonekit.refused.nodevice'
                end
                allowed = false
            end
        end
        onDone(allowed, reason)
    end, D.gateCheckOptions(MODE))
    TriggerEvent('aeterna_phonekit:asking', src, { checkId = checkId, devices = MODE })
end

local function visibleApps(src)
    local p = players[src]
    local dev = activeOf(p)
    local model = dev and dev.model or SINGLE_MODEL
    local spec = D.parseAppSpec(modelInfo(model).apps)
    local out = {}
    for _, app in ipairs(registry:getVisibleApps(src, canPlayerAccess)) do
        if D.isAppAllowed(spec, app.owner .. ':' .. app.id, app, model) then
            out[#out + 1] = app
        end
    end
    return out
end

local function appAllowedOnModel(src, app)
    local p = players[src]
    local dev = activeOf(p)
    local model = dev and dev.model or SINGLE_MODEL
    return D.isAppAllowed(modelInfo(model).apps, app.owner .. ':' .. app.id, app, model)
end

local function openFor(src)
    badgeMgr:setPhoneOpen(src, true)
    sendDevice(src)
    sendBattery(src)
    TriggerClientEvent('aeterna_phonekit:cl:open', src, { apps = visibleApps(src), intents = intents:available() })
end

--------------------------------------------------------------------------------
-- Server Exports (0.1 App API)
--------------------------------------------------------------------------------

exports('addTile', function(app)
    local owner = callerResource()
    local ok, err = registry:addTile(owner, app)
    if not ok then
        logWarn('addTile rejected tile', { owner = owner, err = err })
        return false, err
    end
    local stored = registry:find(owner, app.id)
    intents:set(owner, app.id, stored and stored.handles or {})
    return true
end)

exports('removeTile', function(id)
    local owner = callerResource()
    intents:remove(owner, id)
    return registry:removeTile(owner, id)
end)

exports('showApp', function(src, id, spec)
    local numSrc = tonumber(src)
    if not numSrc or numSrc < 0 then
        return nil, 'invalid_src'
    end

    local invoker = callerResource()
    local app = registry:find(invoker, id)
    if not app then
        logWarn('showApp rejected unknown app or unowned tile', { owner = invoker, id = id })
        return nil, 'unknown_app'
    end

    if not badgeMgr:isPhoneOpen(numSrc) then
        logWarn('showApp rejected phone closed', { src = numSrc, id = id })
        return nil, 'phone_closed'
    end

    if isDead(numSrc) then
        return nil, 'dead'
    end

    if app.ace and not canPlayerAccess(numSrc, app.ace) then
        logWarn('showApp rejected ace denied', { src = numSrc, id = id, ace = app.ace })
        return nil, 'ace_denied'
    end

    local okVal, errVal, cleanSpec = L.validateSpec(spec)
    if not okVal then
        logWarn('showApp rejected invalid spec', { owner = invoker, id = id, err = errVal })
        return nil, errVal
    end

    local screenId = L.generateScreenId(numSrc)

    if not playerScreens[numSrc] then
        playerScreens[numSrc] = {}
    else
        local curr = getCurrentScreen(numSrc)
        if curr and (curr.id ~= id or curr.owner ~= invoker) then
            playerScreens[numSrc] = {}
        end
    end

    local stack = playerScreens[numSrc]

    -- 0.2 `detailOf`: names a list or table of the screen on display. A new detail of the list beside the
    -- current detail replaces that detail; a `detailOf` that names nothing on display is dropped.
    if cleanSpec.detailOf then
        local top = stack[#stack]
        local under = stack[#stack - 1]
        if top and top.spec.detailOf and under and ShellLogic.hasDetailTarget(under.spec, cleanSpec.detailOf)
            and not ShellLogic.hasDetailTarget(top.spec, cleanSpec.detailOf) then
            table.remove(stack)
        elseif not (top and ShellLogic.hasDetailTarget(top.spec, cleanSpec.detailOf)) then
            cleanSpec.detailOf = nil
            cleanSpec.detailItem = nil
        end
    end

    if #stack >= 8 then
        table.remove(stack, 1)
    end

    stack[#stack + 1] = {
        screenId = screenId,
        id = id,
        owner = invoker,
        spec = cleanSpec,
    }

    badgeMgr:setCurrentApp(numSrc, id)

    TriggerClientEvent('aeterna_phonekit:cl:screen', numSrc, {
        screenId = screenId,
        id = id,
        title = cleanSpec.title,
        subtitle = cleanSpec.subtitle,
        blocks = cleanSpec.blocks,
        detailOf = cleanSpec.detailOf,
        detailItem = cleanSpec.detailItem,
    })

    return screenId
end)

exports('updateApp', function(src, screenId, patch)
    local numSrc = tonumber(src)
    if not numSrc then return false, 'invalid_src' end

    if not badgeMgr:isPhoneOpen(numSrc) then
        return false, 'phone_closed'
    end

    local invoker = callerResource()
    local current = nil
    for _, entry in ipairs(playerScreens[numSrc] or {}) do
        if entry.screenId == screenId then current = entry end
    end
    if not current then
        return false, 'unknown_screen'
    end

    if current.owner ~= invoker then
        logWarn('updateApp rejected owner mismatch', { invoker = invoker, screenOwner = current.owner })
        return false, 'owner_mismatch'
    end

    local app = registry:find(current.owner, current.id)
    if not app then
        return false, 'unknown_app'
    end

    if app.ace and not canPlayerAccess(numSrc, app.ace) then
        return false, 'ace_denied'
    end

    local okPatch, errPatch, cleanPatch = L.validatePatch(current.spec, patch)
    if not okPatch then
        logWarn('updateApp rejected invalid patch', { screenId = screenId, err = errPatch })
        return false, errPatch
    end

    -- Apply patch in place to server copy
    if cleanPatch.blocks then
        for blockId, partial in pairs(cleanPatch.blocks) do
            for i = 1, #current.spec.blocks do
                local b = current.spec.blocks[i]
                if b.id == blockId then
                    for pk, pv in pairs(partial) do
                        b[pk] = pv
                    end
                    break
                end
            end
        end
    end

    TriggerClientEvent('aeterna_phonekit:cl:update', numSrc, {
        screenId = screenId,
        patch = cleanPatch,
    })

    return true
end)

exports('badge', function(src, id, count)
    local numSrc = tonumber(src)
    if not numSrc then return 0 end

    local owner = callerResource()
    local clamped = badgeMgr:setBadge(numSrc, owner, id, count)
    TriggerClientEvent('aeterna_phonekit:cl:badge', numSrc, {
        id = id,
        count = clamped,
    })
    return clamped
end)

exports('notifyApp', function(src, id, opts)
    local numSrc = tonumber(src)
    if not numSrc then return false end

    local owner = callerResource()
    local app = registry:find(owner, id) or registry:find(nil, id)
    local appOwner = app and app.owner or owner

    local cleanOpts = {
        title = (opts and opts.title) or (app and app.label) or 'Notification',
        body = (opts and opts.body) or '',
    }

    local dead = isDead(numSrc)
    local newBadge = badgeMgr:notifyApp(
        numSrc,
        appOwner,
        id,
        cleanOpts,
        app,
        function(target, toastData)
            pcall(function()
                exports.aeterna_notify:notify(target, toastData)
            end)
        end,
        function(target, bannerData)
            if not dead then
                TriggerClientEvent('aeterna_phonekit:cl:banner', target, bannerData)
            end
        end
    )

    TriggerClientEvent('aeterna_phonekit:cl:badge', numSrc, {
        id = id,
        count = newBadge,
    })

    return true
end)

exports('listenOpen', function()
    return openingMgr:listenOpen()
end)

exports('allowOpen', function(checkId, answer)
    return openingMgr:allowOpen(checkId, answer)
end)

exports('denyOpen', function(checkId, reasonKey)
    return openingMgr:denyOpen(checkId, reasonKey)
end)

--------------------------------------------------------------------------------
-- Server Exports (0.2: devices, battery, hooks)
--------------------------------------------------------------------------------

exports('device', function(src)
    local numSrc = tonumber(src)
    local p = numSrc and players[numSrc]
    local dev = activeOf(p)
    if not dev or isDead(numSrc) then return nil end
    local info = modelInfo(dev.model)
    local st = p.states[dev.id]
    return {
        model = dev.model,
        id = dev.id,
        label = info.label,
        voice = info.voice,
        fold = p.folds[dev.id],
        battery = (batteryCfg and st) and st.shown or nil,
    }
end)

exports('refreshDevices', function(src)
    local numSrc = tonumber(src)
    if not numSrc or MODE ~= 'items' or not ensureLoaded(numSrc) then return false end
    askGate(numSrc, function() end)
    return true
end)

local function batteryTarget(src)
    if not batteryCfg then return nil end
    local numSrc = tonumber(src)
    local p = numSrc and ensureLoaded(numSrc)
    local dev = activeOf(p)
    if not dev then return nil end
    return numSrc, p, p.states[dev.id]
end

exports('battery', function(src)
    local _, _, st = batteryTarget(src)
    return st and st.shown or nil
end)

exports('setBattery', function(src, pct)
    local numSrc, _, st = batteryTarget(src)
    if not st or type(pct) ~= 'number' or pct ~= pct then return false end
    applyBatteryEvents(numSrc, B.set(st, pct, batteryCfg), false)
    return true
end)

exports('charge', function(src, pct)
    local numSrc, _, st = batteryTarget(src)
    if not st or type(pct) ~= 'number' or pct ~= pct or pct < 0 or pct > 100 then return false end
    applyBatteryEvents(numSrc, B.set(st, st.pct + pct, batteryCfg), false)
    return true
end)

exports('setCharger', function(src, id, secToFull)
    local numSrc = tonumber(src)
    if not numSrc or not L.isValidId(id, 32) then return false end
    local p = ensureLoaded(numSrc)
    if not p then return false end
    local key = callerResource() .. ':' .. id
    if secToFull == false or secToFull == nil then
        p.chargers[key] = nil
    elseif type(secToFull) == 'number' and secToFull == secToFull then
        p.chargers[key] = secToFull
    else
        return false
    end
    return true
end)

exports('activity', function(src, kind, on)
    local numSrc = tonumber(src)
    if not numSrc or kind ~= 'call' then return false end
    local p = ensureLoaded(numSrc)
    if not p then return false end
    p.calls[callerResource()] = on == true or nil
    return true
end)

exports('canCall', function(src)
    local numSrc = tonumber(src)
    local p = numSrc and players[numSrc]
    local dev = activeOf(p)
    local st = dev and p.states[dev.id]
    return H.canCall({
        hasDevice = dev ~= nil,
        model = dev and dev.model,
        battery = (batteryCfg and st) and st.shown or nil,
    })
end)

exports('ring', function(src, id, opts)
    local numSrc = tonumber(src)
    if not numSrc then return nil, 'nodevice' end
    local owner = callerResource()
    local app = registry:find(owner, id)
    local p = ensureLoaded(numSrc)
    local dev = activeOf(p)
    local st = dev and p.states[dev.id]
    local o = type(opts) == 'table' and opts or {}
    local title = L.textClean(type(o.title) == 'string' and o.title or '', 40)
    local body = L.textClean(type(o.body) == 'string' and o.body or '', 60)
    local ringId, err = rings:ring(numSrc, {
        owner = owner,
        id = id,
        appExists = app ~= nil,
        hasDevice = dev ~= nil,
        voice = dev ~= nil and modelInfo(dev.model).voice,
        battery = (batteryCfg and st) and st.shown or nil,
        title = title,
        body = body,
    })
    if not ringId then return nil, err end
    if badgeMgr:isPhoneOpen(numSrc) then
        TriggerClientEvent('aeterna_phonekit:cl:ring', numSrc, { ringId = ringId, id = id, title = title, body = body })
    else
        pcall(function()
            exports.aeterna_notify:notify(numSrc, { title = title, description = body, icon = app.icon or 'phone' })
        end)
    end
    return ringId
end)

exports('stopRing', function(src, ringId)
    local numSrc = tonumber(src)
    if not numSrc then return false end
    local r = rings:current(numSrc)
    if not r or r.owner ~= callerResource() or r.ringId ~= ringId then return false end
    rings:stop(numSrc, ringId)
    TriggerClientEvent('aeterna_phonekit:cl:ringStop', numSrc, { ringId = ringId })
    return true
end)

exports('live', function(src, opts)
    local numSrc = tonumber(src)
    if not numSrc then return false end
    local p = ensureLoaded(numSrc)
    if not p then return false end
    if type(opts) ~= 'table' then
        if p.live and p.live.owner ~= callerResource() then
            return false
        end
        p.live = nil
        TriggerClientEvent('aeterna_phonekit:cl:live', numSrc, {})
        return true
    end
    if not L.isValidId(opts.id, 32) or type(opts.text) ~= 'string' then return false end
    p.live = { owner = callerResource(), id = opts.id, text = L.textClean(opts.text, 24) }
    TriggerClientEvent('aeterna_phonekit:cl:live', numSrc, { id = p.live.id, text = p.live.text })
    return true
end)

--------------------------------------------------------------------------------
-- Server-local events (0.2 gate in local-event form)
--------------------------------------------------------------------------------

AddEventHandler('aeterna_phonekit:listen', function()
    openingMgr:listenOpen()
end)

AddEventHandler('aeterna_phonekit:answer', function(checkId, answer)
    openingMgr:answer(checkId, answer)
end)

AddEventHandler('aeterna_phonekit:devicesChanged', function(src)
    local numSrc = tonumber(src)
    if numSrc and MODE == 'items' and ensureLoaded(numSrc) then
        askGate(numSrc, function() end)
    end
end)

--------------------------------------------------------------------------------
-- Net Events (Server)
--------------------------------------------------------------------------------

RegisterNetEvent('aeterna_phonekit:sv:open', function()
    local src = source
    if not AeternaCore.rateLimit(src, 'phonekit:open', 2, 1000) then
        logWarn('aeterna_phonekit:sv:open rate limited', { src = src })
        return
    end

    local loadedPlayer = ensureLoaded(src)
    if MODE == 'items' and not loadedPlayer then
        TriggerClientEvent('aeterna_phonekit:cl:refused', src, { reason = 'phonekit.refused.nodevice' })
        return
    end
    askGate(src, function(allowed, reasonKey)
        if not allowed then
            TriggerClientEvent('aeterna_phonekit:cl:refused', src, {
                reason = reasonKey or 'phonekit.refused.default',
            })
            return
        end
        if MODE == 'items' and not activeOf(players[src]) then
            TriggerClientEvent('aeterna_phonekit:cl:refused', src, { reason = 'phonekit.refused.nodevice' })
            return
        end
        if isDead(src) then
            TriggerClientEvent('aeterna_phonekit:cl:refused', src, { reason = 'phonekit.battery.dead' })
            return
        end
        openFor(src)
    end)
end)

RegisterNetEvent('aeterna_phonekit:sv:close', function()
    local src = source
    if not AeternaCore.rateLimit(src, 'phonekit:close', 5, 1000) then
        logWarn('aeterna_phonekit:sv:close rate limited', { src = src })
        return
    end

    badgeMgr:setPhoneOpen(src, false)
    local current = getCurrentScreen(src)
    playerScreens[src] = nil
    badgeMgr:setCurrentApp(src, nil)

    if current then
        TriggerEvent('aeterna_phonekit:action', src, {
            owner = current.owner,
            id = current.id,
            screenId = current.screenId,
            action = '__close',
            values = {},
        })
    end
end)

local TAP_SCHEMA = {
    type = 'table',
    fields = {
        id = { type = 'string', minLen = 1, maxLen = 32 },
        owner = { type = 'string', maxLen = 64, optional = true },
        intent = {
            type = 'table',
            optional = true,
            fields = {
                kind = { type = 'string', enum = { 'tel', 'sms' } },
                number = { type = 'string', minLen = 1, maxLen = 20 },
            },
        },
    },
}

RegisterNetEvent('aeterna_phonekit:sv:tap', function(data)
    local src = source
    if not AeternaCore.rateLimit(src, 'phonekit:tap', 5, 1000) then
        logWarn('aeterna_phonekit:sv:tap rate limited', { src = src })
        return
    end

    if type(data) ~= 'table' or type(data.id) ~= 'string' or #data.id < 1 or #data.id > 32 then
        logWarn('aeterna_phonekit:sv:tap invalid payload', { src = src })
        return
    end
    if data.owner ~= nil and (type(data.owner) ~= 'string' or #data.owner > 64) then
        logWarn('aeterna_phonekit:sv:tap invalid owner', { src = src })
        return
    end
    local okSchema, errSchema = validate(data, TAP_SCHEMA)
    if not okSchema then
        logWarn('aeterna_phonekit:sv:tap invalid payload', { src = src, err = errSchema })
        return
    end

    if isDead(src) or not badgeMgr:isPhoneOpen(src) then
        return
    end

    local id = data.id
    local owner = (type(data.owner) == 'string' and data.owner ~= '') and data.owner or nil
    local app = registry:find(owner, id) or registry:find(nil, id)

    if not app then
        logWarn('aeterna_phonekit:sv:tap unknown app', { src = src, id = id })
        return
    end

    if app.ace and not canPlayerAccess(src, app.ace) then
        logWarn('aeterna_phonekit:sv:tap ace denied', { src = src, id = id, ace = app.ace })
        return
    end

    if not appAllowedOnModel(src, app) then
        TriggerClientEvent('aeterna_phonekit:cl:refused', src, { reason = 'phonekit.refused.noapp' })
        return
    end

    local payload = { owner = app.owner, id = app.id }
    if type(data.intent) == 'table' then
        if not H.isPhoneNumber(data.intent.number) then
            logWarn('aeterna_phonekit:sv:tap intent number refused', { src = src })
            return
        end
        if not intents:isHandler(data.intent.kind, app.owner, app.id) then
            logWarn('aeterna_phonekit:sv:tap intent for an app that does not handle it', { src = src, id = id })
            return
        end
        payload.intent = { kind = data.intent.kind, number = L.textClean(data.intent.number, 20) }
    end

    badgeMgr:setCurrentApp(src, id)
    TriggerEvent('aeterna_phonekit:app', src, payload)
end)

RegisterNetEvent('aeterna_phonekit:sv:action', function(data)
    local src = source
    if not AeternaCore.rateLimit(src, 'phonekit:action', 10, 1000) then
        logWarn('aeterna_phonekit:sv:action rate limited', { src = src })
        return
    end

    if type(data) ~= 'table' then
        logWarn('aeterna_phonekit:sv:action invalid payload', { src = src })
        return
    end

    if type(data.screenId) ~= 'string' or #data.screenId < 1 or #data.screenId > 24 then
        logWarn('aeterna_phonekit:sv:action invalid screenId', { src = src })
        return
    end

    if type(data.action) ~= 'string' or #data.action < 1 or #data.action > 32 then
        logWarn('aeterna_phonekit:sv:action invalid action', { src = src })
        return
    end

    if data.values ~= nil then
        if type(data.values) ~= 'table' then
            logWarn('aeterna_phonekit:sv:action invalid values', { src = src })
            return
        end
        local count = 0
        for _ in pairs(data.values) do
            count = count + 1
            if count > 40 then
                logWarn('aeterna_phonekit:sv:action too many values keys', { src = src })
                return
            end
        end
    end

    if isDead(src) then
        return
    end

    local current = getCurrentScreen(src)
    if not current then
        logWarn('aeterna_phonekit:sv:action screen mismatch or closed', { src = src, screenId = data.screenId })
        return
    end

    -- 0.2 two panes: a pick on the list beside a detail is checked against that list's screen.
    if current.screenId ~= data.screenId then
        local stack = playerScreens[src]
        local under = stack[#stack - 1]
        if under and under.screenId == data.screenId and current.spec.detailOf
            and L.isDetailSourceAction(under.spec, current.spec.detailOf, data.action) then
            local okLeft, errLeft, cleanLeft = L.validateAction(under, data)
            if not okLeft then
                logWarn('aeterna_phonekit:sv:action validation failed', { src = src, err = errLeft })
                return
            end
            TriggerEvent('aeterna_phonekit:action', src, cleanLeft)
            return
        end
        logWarn('aeterna_phonekit:sv:action screen mismatch or closed', { src = src, screenId = data.screenId })
        return
    end

    if data.action == '__close' then
        local appOwner = current.owner
        local appId = current.id
        local sId = current.screenId
        playerScreens[src] = nil
        badgeMgr:setCurrentApp(src, nil)

        TriggerEvent('aeterna_phonekit:action', src, {
            owner = appOwner,
            id = appId,
            screenId = sId,
            action = '__close',
            values = {},
        })
        return
    end

    if data.action == '__back' then
        local stack = playerScreens[src]
        if stack and #stack > 1 then
            table.remove(stack)
            local prev = stack[#stack]
            badgeMgr:setCurrentApp(src, prev.id)
            TriggerClientEvent('aeterna_phonekit:cl:screen', src, {
                screenId = prev.screenId,
                id = prev.id,
                title = prev.spec.title,
                subtitle = prev.spec.subtitle,
                blocks = prev.spec.blocks,
                detailOf = prev.spec.detailOf,
                detailItem = prev.spec.detailItem,
            })
        else
            local last = stack and table.remove(stack) or current
            playerScreens[src] = nil
            badgeMgr:setCurrentApp(src, nil)
            TriggerEvent('aeterna_phonekit:action', src, {
                owner = last.owner,
                id = last.id,
                screenId = last.screenId,
                action = '__close',
                values = {},
            })
        end
        return
    end

    local okVal, errVal, clean = L.validateAction(current, data)
    if not okVal then
        logWarn('aeterna_phonekit:sv:action validation failed', { src = src, err = errVal })
        return
    end

    TriggerEvent('aeterna_phonekit:action', src, clean)
end)

local SCREEN_SCHEMA = { type = 'table', fields = { level = { type = 'string', enum = { 'off', 'on', 'media' } } } }
local FOLD_SCHEMA = { type = 'table', fields = { state = { type = 'string', enum = { 'open', 'closed' } } } }
local DEVICE_SCHEMA = { type = 'table', fields = { id = { type = 'string', minLen = 1, maxLen = 64 } } }
local RING_SCHEMA = {
    type = 'table',
    fields = { ringId = { type = 'string', minLen = 1, maxLen = 24 }, answer = { type = 'boolean' } },
}

RegisterNetEvent('aeterna_phonekit:sv:screen', function(data)
    local src = source
    if not AeternaCore.rateLimit(src, 'phonekit:screen', 4, 1000) then return end
    local ok, err = validate(data, SCREEN_SCHEMA)
    if not ok then
        logWarn('aeterna_phonekit:sv:screen invalid payload', { src = src, err = err })
        return
    end
    local p = ensureLoaded(src)
    if not p then return end
    p.pulse = { level = data.level, at = type(GetGameTimer) == 'function' and GetGameTimer() or 0 }
end)

RegisterNetEvent('aeterna_phonekit:sv:fold', function(data)
    local src = source
    if not AeternaCore.rateLimit(src, 'phonekit:fold', 4, 1000) then return end
    local ok, err = validate(data, FOLD_SCHEMA)
    if not ok then
        logWarn('aeterna_phonekit:sv:fold invalid payload', { src = src, err = err })
        return
    end
    local p = ensureLoaded(src)
    local dev = activeOf(p)
    if not dev or not D.MODELS[dev.model].folds then
        logWarn('aeterna_phonekit:sv:fold refused for a model that does not fold', { src = src })
        return
    end
    if not COVER and dev.model == 'fold' and data.state == 'closed' then
        return
    end
    p.folds[dev.id] = data.state
    saveDevice(src)
end)

RegisterNetEvent('aeterna_phonekit:sv:device', function(data)
    local src = source
    if not AeternaCore.rateLimit(src, 'phonekit:device', 2, 1000) then return end
    local ok, err = validate(data, DEVICE_SCHEMA)
    if not ok then
        logWarn('aeterna_phonekit:sv:device invalid payload', { src = src, err = err })
        return
    end
    local p = players[src]
    if MODE ~= 'items' or not p then return end
    local found = false
    for _, d in ipairs(p.devices) do
        if d.id == data.id then found = true end
    end
    if not found then
        logWarn('aeterna_phonekit:sv:device id not in the last answer', { src = src })
        return
    end
    local wasDead = isDead(src)
    local switched = p.active ~= data.id
    p.chosen = data.id
    p.active = data.id
    writeKvp('aeterna_phonekit:active:v1:' .. p.who, data.id)
    sendDevice(src)
    sendBattery(src)
    if switched then
        syncPowerAfterSwitch(src, wasDead)
    end
end)

RegisterNetEvent('aeterna_phonekit:sv:ring', function(data)
    local src = source
    if not AeternaCore.rateLimit(src, 'phonekit:ring', 4, 1000) then return end
    local ok, err = validate(data, RING_SCHEMA)
    if not ok then
        logWarn('aeterna_phonekit:sv:ring invalid payload', { src = src, err = err })
        return
    end
    local action = rings:answer(src, data.ringId, data.answer)
    if not action then return end
    TriggerClientEvent('aeterna_phonekit:cl:ringStop', src, { ringId = data.ringId })
    TriggerEvent('aeterna_phonekit:action', src, action)
end)

RegisterNetEvent('aeterna_phonekit:sv:battery', function()
    local src = source
    if not AeternaCore.rateLimit(src, 'phonekit:battery', 1, 2000) then return end
    local p = ensureLoaded(src)
    if not p then
        TriggerClientEvent('aeterna_phonekit:cl:battery', src, { none = true })
        return
    end
    if MODE == 'items' then
        askGate(src, function() end)
        return
    end
    sendDevice(src)
    sendBattery(src)
end)

--------------------------------------------------------------------------------
-- Battery tick: only players in the loaded set, never a scan of every player
--------------------------------------------------------------------------------

local function inVehicle(src)
    if type(GetPlayerPed) ~= 'function' or type(GetVehiclePedIsIn) ~= 'function' then return false end
    local ok, veh = pcall(function() return GetVehiclePedIsIn(GetPlayerPed(src), false) end)
    return ok and veh ~= nil and veh ~= 0
end

local function tickPlayer(src, dtSec, nowMs)
    local p = players[src]
    local dev = activeOf(p)
    local st = dev and p.states[dev.id]
    if not st then return end
    local vehicle = batteryCfg.vehicleSec > 0 and inVehicle(src)
    local charging = B.fastestCharger(p.chargers, vehicle, batteryCfg.vehicleSec) ~= nil
    local chargingChanged = charging ~= p.charging
    p.charging = charging
    local ev = B.advance(st, dtSec, {
        chargers = p.chargers,
        inVehicle = vehicle,
        screen = p.pulse.level,
        pulseAge = (nowMs - p.pulse.at) / 1000,
        call = next(p.calls) ~= nil,
        multiplier = D.MODELS[dev.model].batteryMultiplier,
    }, batteryCfg)
    applyBatteryEvents(src, ev, chargingChanged)
end

if batteryCfg and type(CreateThread) == 'function' then
    CreateThread(function()
        local lastMs = GetGameTimer()
        while true do
            Wait(batteryCfg.tickSec * 1000)
            local nowMs = GetGameTimer()
            local dtSec = math.max(0, (nowMs - lastMs) / 1000)
            lastMs = nowMs
            for src in pairs(loaded) do
                tickPlayer(src, dtSec, nowMs)
            end
        end
    end)
end

if type(CreateThread) == 'function' then
    CreateThread(function()
        while true do
            Wait(1000)
            for _, r in ipairs(rings:expire()) do
                TriggerClientEvent('aeterna_phonekit:cl:ringStop', r.src, { ringId = r.ringId })
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- Resource Cleanup & Player Disconnect
--------------------------------------------------------------------------------

local function unloadPlayer(src)
    if players[src] then
        saveDevice(src)
    end
    players[src] = nil
    loaded[src] = nil
end

AddEventHandler('onResourceStop', function(resName)
    if resName ~= selfName() then
        registry:removeOwner(resName)
        badgeMgr:removeOwner(resName)
        intents:removeOwner(resName)
        rings:removeOwner(resName)
        local prefix = resName .. ':'
        for src, p in pairs(players) do
            for key in pairs(p.chargers) do
                if key:sub(1, #prefix) == prefix then p.chargers[key] = nil end
            end
            p.calls[resName] = nil
            if p.live and p.live.owner == resName then
                p.live = nil
                TriggerClientEvent('aeterna_phonekit:cl:live', src, {})
            end
        end
        for src in pairs(playerScreens) do
            local current = getCurrentScreen(src)
            if current and current.owner == resName then
                playerScreens[src] = nil
                badgeMgr:setCurrentApp(src, nil)
            end
        end
        for srcStr, p in pairs(badgeMgr.players) do
            local numSrc = tonumber(srcStr)
            if numSrc and p.phoneOpen then
                TriggerClientEvent('aeterna_phonekit:cl:open', numSrc, { apps = visibleApps(numSrc),
                    intents = intents:available() })
            end
        end
    else
        for src in pairs(players) do
            saveDevice(src)
        end
    end
end)

-- qbx_core character logout: save under the old character key and forget it (the next request loads the next one).
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    local numSrc = tonumber(src or source)
    if numSrc then
        closeServerSide(numSrc)
        unloadPlayer(numSrc)
        TriggerClientEvent('aeterna_phonekit:cl:battery', numSrc, { none = true })
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    if src then
        playerScreens[src] = nil
        rings:stop(src, nil)
        unloadPlayer(src)
        badgeMgr:removePlayer(src)
    end
end)

--------------------------------------------------------------------------------
-- Self-tests (spec § Self-tests (0.2)): server rows. Decisions live in shared/logic/selftest.lua.
--------------------------------------------------------------------------------

local PS = PhoneSelftest

local function reportSelftest(runId, name, ok, detail, extra)
    local sent, err = pcall(function() return exports.aeterna_core:reportSelftest(runId, name, ok, detail, extra) end)
    if not sent then logWarn('reportSelftest failed', { name = name, err = tostring(err) }) end
end

-- Core's write guard. No guard (an aeterna_core without it) means no write.
local function mayWrite(runId, name)
    local guard = AeternaCore and AeternaCore.selftest and AeternaCore.selftest.mayWrite
    return type(guard) == 'function' and guard(runId, name) == true
end

-- The presser's loaded phone, or nil and the SKIP reason.
local function presserPhone(ctx)
    local src = type(ctx) == 'table' and tonumber(ctx.a) or nil
    if not src then return nil, 'needs a presser' end
    local p = ensureLoaded(src)
    local dev = activeOf(p)
    if not dev then return nil, 'presser has no phone' end
    return src, p, dev
end

local function zeroClosesAll(runId, name, ctx)
    local src, p, dev = presserPhone(ctx)
    if not src then return 'skip', p end
    local st = p.states[dev.id]
    if st.dead then return 'skip', 'presser phone is already at 0 %' end
    if not mayWrite(runId, name) then return false, 'write guard refused' end
    local before = st.pct
    local ev = B.set(st, 0, batteryCfg)
    applyBatteryEvents(src, ev, false)
    local ok, detail = PS.zeroClosed({
        dead = isDead(src), powerOff = ev.power == false, open = badgeMgr:isPhoneOpen(src),
        screens = playerScreens[src] ~= nil,
    })
    applyBatteryEvents(src, B.set(st, before, batteryCfg), false)
    saveDevice(src)
    local restored = st.pct == before and not isDead(src)
    return ok and 'mock' or false, detail, { restored = restored, wrote = true }
end

local function kvpRoundtrip(runId, name, ctx)
    local src, p = presserPhone(ctx)
    if not src then return 'skip', p end
    if not mayWrite(runId, name) then return false, 'write guard refused' end
    local key = 'aeterna_phonekit:device:v1:' .. p.who
    local raw = GetResourceKvpString(key)
    local sample = { battery = 42.5, fold = p.folds[SINGLE_ID] }
    writeKvp(key, sample)
    local ok, detail = PS.kvpRoundtrip(sample, readKvp(key))
    local restored
    if type(raw) == 'string' and raw ~= '' then
        SetResourceKvp(key, raw)
        restored = GetResourceKvpString(key) == raw
    else
        -- the key did not exist before: it does not exist after
        DeleteResourceKvp(key)
        local left = GetResourceKvpString(key)
        restored = left == nil or left == ''
    end
    return ok and 'mock' or false, detail, { restored = restored, wrote = true }
end

local SERVER_TESTS = {
    rules_loaded = function()
        return PS.rulesLoaded({ mode = MODE, singleModel = SINGLE_MODEL, models = D.MODELS,
            batteryOn = Cfg.battery ~= false, battery = batteryCfg })
    end,
    models_have_apps = function() return PS.modelsHaveApps(D, modelInfo) end,
    battery_drain_tick = function() return PS.drainTick(B, batteryCfg) end,
    stale_pulse_is_off = function() return PS.stalePulse(B, batteryCfg) end,
    battery_zero_closes_all = zeroClosesAll,
    battery_kvp_roundtrip = kvpRoundtrip,
    gate_items_silence_denies = function()
        local ok, detail = PS.silenceDenies(L, D.gateCheckOptions('items'))
        -- a made-up check on its own manager: the live gate never changed, so nothing is left to restore
        return ok and 'mock' or false, detail, { restored = true }
    end,
}

AddEventHandler('aeterna_core:selftest', function(runId, name, ctx)
    if type(GetInvokingResource) ~= 'function' or GetInvokingResource() ~= 'aeterna_core' then return end
    local short = PS.shortName(selfName(), name)
    local test = short and SERVER_TESTS[short]
    if not test then return end
    local skip = PS.skipReason(short, { battery = batteryCfg ~= false, mode = MODE, lockScreen = Cfg.lockScreen,
        cover = COVER, model = SINGLE_MODEL, ped = true })
    if skip then
        reportSelftest(runId, name, 'skip', skip)
        return
    end
    reportSelftest(runId, name, test(runId, name, ctx))
end)

-- eye_battery_dead is a client eye test that needs the server half: core fires selftestStarted before it sends the
-- test to the presser, so the battery is at 0 (saved, power off) when the card asks; selftestEnd puts it back.
local deadPrepared = {} -- ['runId|name'] = { src, before }

local function fromCore()
    return type(GetInvokingResource) == 'function' and GetInvokingResource() == 'aeterna_core'
end

AddEventHandler('aeterna_core:selftestStarted', function(runId, name, ctx)
    if not fromCore() or PS.shortName(selfName(), name) ~= 'eye_battery_dead' or not batteryCfg then return end
    local src, p, dev = presserPhone(ctx)
    if not src then return end
    local st = p.states[dev.id]
    if st.dead or not mayWrite(runId, name) then return end
    deadPrepared[tostring(runId) .. '|' .. name] = { src = src, before = st.pct }
    applyBatteryEvents(src, B.set(st, 0, batteryCfg), false)
end)

AddEventHandler('aeterna_core:selftestEnd', function(runId, name)
    if not fromCore() then return end
    local key = tostring(runId) .. '|' .. tostring(name)
    local prep = deadPrepared[key]
    if not prep then return end
    deadPrepared[key] = nil
    local p = players[prep.src]
    local dev = activeOf(p)
    local st = dev and p.states[dev.id]
    if not st then return end
    applyBatteryEvents(prep.src, B.set(st, prep.before, batteryCfg), false)
    saveDevice(prep.src)
end)

for _, r in ipairs(PS.rows(selfName(), translate, function(id) return modelInfo(id).label end)) do
    pcall(function() return exports.aeterna_core:addSelftest(r.name, r.meta) end)
end

-- phonekit (re)started: answerers fire `aeterna_phonekit:listen` again.
TriggerEvent('aeterna_phonekit:hello')
