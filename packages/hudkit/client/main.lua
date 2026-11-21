-- client/main.lua -- aeterna_hudkit client: layout registration, minimap positioning, tick sampling, settings.

local H = HudLogic
local M = MinimapLogic
local C = CompassLogic
local V = VoiceLogic
local S = SeatbeltLogic

local settingsOpen = false
local focusToken = nil
local localeReady = false
local cachedNeeds = {}
local appliedPlaces = {}
local lastValues = nil
local lastVehicleVisible = nil
local focusPaused = false
local lastCompassDeg = nil
local lastInVehicle = false
local lastSeatbelt = nil
local seatbeltSent = false

local LOCALE_KEYS = {
    'hudkit.menu.entry',
    'hudkit.key.settings',
    'hudkit.bar.health',
    'hudkit.bar.armour',
    'hudkit.bar.hunger',
    'hudkit.bar.thirst',
    'hudkit.bar.stress',
    'hudkit.vehicle.fuel',
    'hudkit.vehicle.gear',
    'hudkit.unit.kmh',
    'hudkit.unit.mph',
    'hudkit.part.status',
    'hudkit.part.vehicle',
    'hudkit.part.street',
    'hudkit.part.minimap',
    'hudkit.settings.title',
    'hudkit.settings.numbers',
    'hudkit.settings.speedUnit',
    'hudkit.settings.minimap',
    'hudkit.settings.minimap.always',
    'hudkit.settings.minimap.vehicle',
    'hudkit.settings.minimap.never',
    'hudkit.settings.layout',
    'hudkit.settings.close',
    'hudkit.dir.n',
    'hudkit.dir.ne',
    'hudkit.dir.e',
    'hudkit.dir.se',
    'hudkit.dir.s',
    'hudkit.dir.sw',
    'hudkit.dir.w',
    'hudkit.dir.nw',
    'hudkit.settings.barStyle',
    'hudkit.settings.barStyle.bar',
    'hudkit.settings.barStyle.ring',
    'hudkit.part.compass',
    'hudkit.part.voice',
    'hudkit.voice.mode.1',
    'hudkit.voice.mode.2',
    'hudkit.voice.mode.3',
    'hudkit.voice.radio',
    'hudkit.vehicle.seatbelt.on',
    'hudkit.vehicle.seatbelt.off',
}

local elementSizes = {
    status = { w = 220, h = 64 },
    vehicle = { w = 180, h = 72 },
    street = { w = 240, h = 48 },
    compass = { w = 320, h = 44 },
    voice = { w = 120, h = 32 },
}

-- Parts drawn in hudkit's own NUI (the minimap is drawn by the game).
local NUI_PARTS = { status = true, vehicle = true, street = true, compass = true, voice = true }

local function compassEnabled()
    return not (Config and Config.compass and Config.compass.enabled == false)
end

local function seatbeltEnabled()
    return not (Config and Config.seatbelt and Config.seatbelt.enabled == false)
end

local function compassSpan()
    return C.clampSpan(Config and Config.compass and Config.compass.span)
end

local function selfResource()
    return type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_hudkit'
end

local function logWarn(msg, fields)
    if AeternaCore and AeternaCore.log and type(AeternaCore.log.warn) == 'function' then
        AeternaCore.log.warn(msg, fields)
    end
end

local function translate(key)
    if AeternaCore and type(AeternaCore.t) == 'function' then
        return AeternaCore.t(key)
    end
    if Locales and Locales.en and Locales.en[key] then
        return Locales.en[key]
    end
    return key
end

local function sendUi(msg)
    if type(SendNUIMessage) == 'function' then
        SendNUIMessage(msg)
    end
end

local function loadSettings()
    local defaultSettings = {
        numbers = false,
        speedUnit = Config and Config.speedUnit or 'kmh',
        minimapMode = Config and Config.minimap and Config.minimap.mode or 'always',
        barStyle = Config and Config.barStyle or 'bar',
    }
    if AeternaCore and AeternaCore.kvp and type(AeternaCore.kvp.get) == 'function' then
        local stored = AeternaCore.kvp.get('settings', 1, nil)
        return H.resolveSettings(stored, defaultSettings)
    end
    return defaultSettings
end

local function saveSettings(s)
    if AeternaCore and AeternaCore.kvp and type(AeternaCore.kvp.set) == 'function' then
        AeternaCore.kvp.set('settings', 1, s)
    end
end

local settings = loadSettings()

local extraBarsRegistry = H.createBarsRegistry({
    warn = logWarn,
    maxBars = 8,
})

local seatbelt = S.create({ warn = logWarn })

local voiceDetector = V.createDetector({
    enabled = not (Config and Config.voice and Config.voice.enabled == false),
})
local voiceState = { talking = false, proximity = nil, radioChannel = nil, radioActive = false }
local lastVoiceMsg = nil

local function syncThemeAndLocale()
    if not localeReady then
        local strings = {}
        for i = 1, #LOCALE_KEYS do
            local k = LOCALE_KEYS[i]
            strings[k] = translate(k)
        end
        sendUi({ type = 'locale', strings = strings })
        local ok, href = pcall(function()
            return exports.aeterna_core:themeHref()
        end)
        if ok and href then
            sendUi({ type = 'aeterna:theme', href = href })
        end
        localeReady = true
    end
end

local function getMinimapMetrics()
    local p0 = { x = 0.0150, y = 0.9850 }
    local p1 = { x = 0.5775, y = 1.9850 }

    if type(SetScriptGfxAlign) == 'function' and type(GetScriptGfxPosition) == 'function' then
        SetScriptGfxAlign(string.byte('L'), string.byte('B'))
        if type(SetScriptGfxAlignParams) == 'function' then
            SetScriptGfxAlignParams(0.0, 0.0, 0.0, 0.0)
        end
        local p0x, p0y = GetScriptGfxPosition(0.0, 0.0)
        local p1x, p1y = GetScriptGfxPosition(1.0, 1.0)
        if type(ResetScriptGfxAlign) == 'function' then
            ResetScriptGfxAlign()
        end
        p0 = { x = p0x, y = p0y }
        p1 = { x = p1x, y = p1y }
    end

    local screenW, screenH = 1920, 1080
    if type(GetActiveScreenResolution) == 'function' then
        screenW, screenH = GetActiveScreenResolution()
    end

    local def = M.DEFAULT_COMPONENTS.minimap
    local pxW, pxH = M.screenSizeToPixels(def.w, def.h, p0, p1, screenW, screenH)
    local defaultSx, defaultSy = M.offsetToScreen(def.x, def.y, p0, p1)

    return p0, p1, pxW, pxH, defaultSx, defaultSy, screenW, screenH
end

local lastMinimapPositions = nil

local function positionsEqual(a, b)
    if not a or not b then return false end
    for name, pos in pairs(b) do
        local apos = a[name]
        if not apos then return false end
        if math.abs(apos.x - pos.x) > 1e-6 or
           math.abs(apos.y - pos.y) > 1e-6 or
           math.abs(apos.w - pos.w) > 1e-6 or
           math.abs(apos.h - pos.h) > 1e-6 then
            return false
        end
    end
    return true
end

local function hideBaseHealthArmour()
    if not (Config and Config.hideBaseBars) then return end
    if type(RequestScaleformMovie) ~= 'function' then return end
    local minimap = RequestScaleformMovie('minimap')
    if type(HasScaleformMovieLoaded) == 'function' and HasScaleformMovieLoaded(minimap) then
        if type(BeginScaleformMovieMethod) == 'function' then
            BeginScaleformMovieMethod(minimap, 'SETUP_HEALTH_ARMOUR')
            if type(ScaleformMovieMethodAddParamInt) == 'function' then
                ScaleformMovieMethodAddParamInt(3)
            end
            if type(EndScaleformMovieMethod) == 'function' then
                EndScaleformMovieMethod()
            end
        end
    end
    if type(SetScaleformMovieAsNoLongerNeeded) == 'function' then
        SetScaleformMovieAsNoLongerNeeded(minimap)
    end
end

local function applyMinimapPlace(place)
    if not place then return end
    appliedPlaces['minimap'] = place

    local p0, p1, pxW, pxH, defaultSx, defaultSy, screenW, screenH = getMinimapMetrics()
    local scale = M.clampScale(place.scale)

    local leftPx = place.x * screenW - place.ax * pxW * scale
    local topPx  = place.y * screenH - place.ay * pxH * scale
    local bottomPx = topPx + pxH * scale
    local targetSx = leftPx / screenW
    local targetSy = bottomPx / screenH

    local deltaSx = targetSx - defaultSx
    local deltaSy = targetSy - defaultSy

    local deltaOx = (p1.x ~= p0.x) and (deltaSx / (p1.x - p0.x)) or 0.0
    local deltaOy = (p1.y ~= p0.y) and (deltaSy / (p1.y - p0.y)) or 0.0

    local positions = M.computePositions(deltaOx, deltaOy, scale)

    if positionsEqual(lastMinimapPositions, positions) then
        return
    end
    lastMinimapPositions = positions

    if type(SetMinimapComponentPosition) == 'function' then
        for name, pos in pairs(positions) do
            SetMinimapComponentPosition(name, 'L', 'B', pos.x, pos.y, pos.w, pos.h)
        end
    end

    if type(SetBigmapActive) == 'function' then
        SetBigmapActive(true, false)
        Wait(0)
        SetBigmapActive(false, false)
    end

    hideBaseHealthArmour()
end

local function registerLayoutElements()
    local selfName = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_hudkit'
    local p0, p1, pxW, pxH, defaultSx, defaultSy = getMinimapMetrics()

    -- Status part
    TriggerEvent('aeterna_layout:add', {
        id = 'status',
        label = translate('hudkit.part.status'),
        w = elementSizes.status.w,
        h = elementSizes.status.h,
        x = 0.18,
        y = 0.95,
        ax = 0.0,
        ay = 1.0,
        scalable = true,
        hideable = true,
        owner = selfName,
    })

    -- Vehicle part
    TriggerEvent('aeterna_layout:add', {
        id = 'vehicle',
        label = translate('hudkit.part.vehicle'),
        w = elementSizes.vehicle.w,
        h = elementSizes.vehicle.h,
        x = 0.98,
        y = 0.95,
        ax = 1.0,
        ay = 1.0,
        scalable = true,
        hideable = true,
        owner = selfName,
    })

    -- Street part
    TriggerEvent('aeterna_layout:add', {
        id = 'street',
        label = translate('hudkit.part.street'),
        w = elementSizes.street.w,
        h = elementSizes.street.h,
        x = 0.50,
        y = 0.95,
        ax = 0.5,
        ay = 1.0,
        scalable = true,
        hideable = true,
        owner = selfName,
    })

    -- Compass tape (0.2): top-centre, unless the server turned it off.
    if compassEnabled() then
        TriggerEvent('aeterna_layout:add', {
            id = 'compass',
            label = translate('hudkit.part.compass'),
            w = elementSizes.compass.w,
            h = elementSizes.compass.h,
            x = 0.50,
            y = 0.02,
            ax = 0.5,
            ay = 0.0,
            scalable = true,
            hideable = true,
            owner = selfName,
        })
    end

    -- Voice indicator (0.2): only while pma-voice is started; placed just above the status part.
    if voiceDetector.isActive() then
        local _, screenH = 1920, 1080
        if type(GetActiveScreenResolution) == 'function' then
            _, screenH = GetActiveScreenResolution()
        end
        TriggerEvent('aeterna_layout:add', {
            id = 'voice',
            label = translate('hudkit.part.voice'),
            w = elementSizes.voice.w,
            h = elementSizes.voice.h,
            x = 0.18,
            y = 0.95 - (elementSizes.status.h + 8) / math.max(1, screenH or 1080),
            ax = 0.0,
            ay = 1.0,
            scalable = true,
            hideable = true,
            owner = selfName,
        })
    end

    -- Minimap part (hideable is false; visibility managed by minimapMode)
    TriggerEvent('aeterna_layout:add', {
        id = 'minimap',
        label = translate('hudkit.part.minimap'),
        w = pxW,
        h = pxH,
        x = defaultSx,
        y = defaultSy,
        ax = 0.0,
        ay = 1.0,
        scalable = true,
        hideable = false,
        owner = selfName,
    })
end

local lastRadarVisible = nil
local lastRadarMode = nil
local lastRadarInVeh = nil

local function updateMinimapVisibility(inVeh, force)
    if type(DisplayRadar) ~= 'function' then return end
    local mode = settings.minimapMode
    local inVehBool = (inVeh == true)
    if not force and mode == lastRadarMode and inVehBool == lastRadarInVeh then
        return
    end
    lastRadarMode = mode
    lastRadarInVeh = inVehBool

    local shouldShow = false
    if mode == 'always' then
        shouldShow = true
    elseif mode == 'vehicle' then
        shouldShow = inVehBool
    elseif mode == 'never' then
        shouldShow = false
    end

    if force or shouldShow ~= lastRadarVisible then
        lastRadarVisible = shouldShow
        DisplayRadar(shouldShow)
    end
end

local function openSettings()
    if settingsOpen then return end
    local ok, tok = pcall(function()
        return AeternaCore.requestFocus({
            cursor = true,
            keyboard = true,
            keepGameInput = false,
        })
    end)
    if not ok or type(tok) ~= 'string' then
        logWarn('aeterna_hudkit: settings open refused', { err = 'focus: unavailable' })
        return
    end
    focusToken = tok
    settingsOpen = true
    focusPaused = false
    syncThemeAndLocale()
    sendUi({
        type = 'settings:open',
        settings = settings,
        low = Config and Config.low or 20,
        span = compassSpan(),
    })
end

local function closeSettings(releaseFocus)
    if not settingsOpen then return end
    settingsOpen = false
    focusPaused = false
    sendUi({ type = 'settings:close' })
    if releaseFocus ~= false and focusToken then
        local tok = focusToken
        focusToken = nil
        pcall(function()
            AeternaCore.releaseFocus(tok)
        end)
    else
        focusToken = nil
    end
end

-- While another resource holds core's focus overlay the card stays open and ignores its page (core 0.2 § Focus).
-- The page may already have hidden the card or changed a control, so it gets its state back.
local function ignoredWhilePaused()
    if not (settingsOpen and focusPaused) then return false end
    sendUi({
        type = 'settings:open',
        settings = settings,
        low = Config and Config.low or 20,
        span = compassSpan(),
    })
    return true
end

local function sendPlace(id, place)
    sendUi({
        type = 'hud:place',
        id = id,
        x = place.x,
        y = place.y,
        ax = place.ax,
        ay = place.ay,
        scale = place.scale,
        hidden = place.hidden,
    })
end

local function isInVehicle()
    local ped = type(PlayerPedId) == 'function' and PlayerPedId() or 0
    if ped == 0 or type(IsPedInAnyVehicle) ~= 'function' then return false end
    return IsPedInAnyVehicle(ped, false) == true
end

-- Seatbelt icon: true / false / nil (hidden). Sent only when it changes, unless forced.
local function sendSeatbelt(inVeh, force)
    local state = nil
    if seatbeltEnabled() then
        state = seatbelt.display(inVeh)
    end
    if not force and seatbeltSent and state == lastSeatbelt then return end
    seatbeltSent = true
    lastSeatbelt = state
    sendUi({ type = 'hud:seatbelt', state = state })
end

-- Voice indicator state for NUI. `mode` is absent when no label applies (the page hides it).
local function voiceMessage()
    if not voiceDetector.isActive() then
        return { available = false, talking = false, radio = false, radioActive = false }
    end
    local mode = nil
    local label = V.modeLabel(voiceState.proximity)
    if label and label.key then
        mode = translate(label.key)
    elseif label and label.meters then
        mode = label.meters .. ' m'
    end
    local radio = V.radioOn(voiceState.radioChannel)
    return {
        available = true,
        talking = voiceState.talking == true,
        mode = mode,
        radio = radio,
        radioActive = radio and voiceState.radioActive == true,
    }
end

local function sendVoice(force)
    local msg = voiceMessage()
    local prev = lastVoiceMsg
    if not force and prev and prev.available == msg.available and prev.talking == msg.talking
        and prev.mode == msg.mode and prev.radio == msg.radio and prev.radioActive == msg.radioActive then
        return
    end
    lastVoiceMsg = msg
    sendUi({
        type = 'hud:voice',
        available = msg.available,
        talking = msg.talking,
        mode = msg.mode,
        radio = msg.radio,
        radioActive = msg.radioActive,
    })
end

local function readLocalState(key)
    local ok, val = pcall(function()
        if LocalPlayer and LocalPlayer.state then
            return LocalPlayer.state[key]
        end
    end)
    if ok then return val end
    return nil
end

local function isOwnBag(bagName)
    local ply = type(PlayerId) == 'function' and PlayerId() or 0
    local myServerId = type(GetPlayerServerId) == 'function' and GetPlayerServerId(ply) or 1
    return bagName == ('player:' .. myServerId)
end

-- Reading pma-voice: two state bag keys and one client-local event. No export, no dependency.
local voiceReaders = nil

local function startVoiceReading()
    if voiceReaders then return end
    voiceReaders = { bags = {} }
    voiceState.proximity = readLocalState('proximity')
    voiceState.radioChannel = readLocalState('radioChannel')
    voiceState.radioActive = false
    voiceState.talking = false
    if type(AddStateBagChangeHandler) == 'function' then
        voiceReaders.bags[#voiceReaders.bags + 1] = AddStateBagChangeHandler('proximity', nil, function(bagName, _, value)
            if not isOwnBag(bagName) then return end
            voiceState.proximity = value
            sendVoice()
        end)
        voiceReaders.bags[#voiceReaders.bags + 1] = AddStateBagChangeHandler('radioChannel', nil, function(bagName, _, value)
            if not isOwnBag(bagName) then return end
            voiceState.radioChannel = value
            if not V.radioOn(value) then
                voiceState.radioActive = false
            end
            sendVoice()
        end)
    end
    voiceReaders.radioEvent = AddEventHandler('pma-voice:radioActive', function(active)
        voiceState.radioActive = (active == true)
        sendVoice()
    end)
end

local function stopVoiceReading()
    if not voiceReaders then return end
    if type(RemoveStateBagChangeHandler) == 'function' then
        for i = 1, #voiceReaders.bags do
            RemoveStateBagChangeHandler(voiceReaders.bags[i])
        end
    end
    if voiceReaders.radioEvent and type(RemoveEventHandler) == 'function' then
        RemoveEventHandler(voiceReaders.radioEvent)
    end
    voiceReaders = nil
    voiceState.proximity = nil
    voiceState.radioChannel = nil
    voiceState.radioActive = false
    voiceState.talking = false
end

local function checkVoice()
    local state = type(GetResourceState) == 'function' and GetResourceState(V.RESOURCE) or 'missing'
    local action = voiceDetector.update(state)
    if action == 'register' then
        startVoiceReading()
        registerLayoutElements()
        sendVoice(true)
    elseif action == 'remove' then
        stopVoiceReading()
        appliedPlaces['voice'] = nil
        TriggerEvent('aeterna_layout:remove', { id = 'voice', owner = selfResource() })
        sendVoice(true)
    end
end

-- Layout protocol events
AddEventHandler('aeterna_layout:apply', function(owner, id, place)
    local selfName = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_hudkit'
    if owner ~= selfName then return end
    if not id or type(place) ~= 'table' then return end

    if NUI_PARTS[id] then
        appliedPlaces[id] = place
        sendPlace(id, place)
    elseif id == 'minimap' then
        applyMinimapPlace(place)
    end
end)

AddEventHandler('aeterna_layout:hello', function()
    registerLayoutElements()
end)

-- pma-voice started or stopped after hudkit (runtime detection, ADR 0005 decision 4)
AddEventHandler('onClientResourceStart', function(resName)
    if resName == V.RESOURCE then checkVoice() end
end)

AddEventHandler('onClientResourceStop', function(resName)
    if resName == V.RESOURCE then checkVoice() end
end)

-- Seatbelt state from another resource (client-local). The last resource that fired it owns it.
AddEventHandler('aeterna_hudkit:seatbelt', function(payload)
    local inv = type(GetInvokingResource) == 'function' and GetInvokingResource() or nil
    local owner = inv or (type(payload) == 'table' and payload.owner) or 'unknown'
    if seatbelt.set(owner, payload) then
        sendSeatbelt(isInVehicle())
    end
end)

-- External bars events
AddEventHandler('aeterna_hudkit:bar', function(def)
    local inv = type(GetInvokingResource) == 'function' and GetInvokingResource() or nil
    local owner = inv or (type(def) == 'table' and def.owner) or 'unknown'
    local ok = extraBarsRegistry.add(owner, def)
    if ok then
        sendUi({ type = 'hud:bars', bars = extraBarsRegistry.getSortedBars(false) })
    end
end)

AddEventHandler('aeterna_hudkit:removeBar', function(arg1, arg2)
    local inv = type(GetInvokingResource) == 'function' and GetInvokingResource() or nil
    local id = type(arg1) == 'table' and arg1.id or arg1
    local owner = inv or (type(arg1) == 'table' and arg1.owner) or arg2
    if extraBarsRegistry.remove(owner, id) then
        sendUi({ type = 'hud:bars', bars = extraBarsRegistry.getSortedBars(false) })
    end
end)

AddEventHandler('onResourceStop', function(stoppedRes)
    if type(stoppedRes) ~= 'string' or stoppedRes == '' then return end
    local selfName = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_hudkit'
    if stoppedRes == selfName then
        if settingsOpen then
            closeSettings(true)
        end
        return
    end
    local removed = extraBarsRegistry.removeByOwner(stoppedRes)
    if removed > 0 then
        sendUi({ type = 'hud:bars', bars = extraBarsRegistry.getSortedBars(false) })
    end
    if seatbelt.ownerStopped(stoppedRes) then
        sendSeatbelt(lastInVehicle)
    end
end)

-- Server -> Client Net Event (opened from uikit menu)
RegisterNetEvent('aeterna_hudkit:cl:settings', function()
    openSettings()
end)

-- Focus loss handler from aeterna_core
AddEventHandler('aeterna_core:focusLost', function(owner, token)
    local selfName = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_hudkit'
    if owner ~= nil and owner ~= selfName then return end
    if token ~= nil and focusToken ~= nil and token ~= focusToken then return end
    if settingsOpen then
        closeSettings(false)
    end
end)

-- Focus overlay (core 0.2): paused keeps the card open; resumed gives input back.
AddEventHandler('aeterna_core:focusPaused', function(owner, token)
    if owner ~= selfResource() then return end
    if token ~= nil and focusToken ~= nil and token ~= focusToken then return end
    if settingsOpen then
        focusPaused = true
    end
end)

AddEventHandler('aeterna_core:focusResumed', function(owner, token)
    if owner ~= selfResource() then return end
    if token ~= nil and focusToken ~= nil and token ~= focusToken then return end
    focusPaused = false
end)

-- NUI Callbacks
RegisterNUICallback('ready', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if type(data) == 'table' and type(data.sizes) == 'table' then
        for id, sz in pairs(data.sizes) do
            if NUI_PARTS[id] and type(sz) == 'table' and tonumber(sz.w) and tonumber(sz.h) then
                elementSizes[id] = {
                    w = math.max(8, math.min(2000, math.floor(tonumber(sz.w) + 0.5))),
                    h = math.max(8, math.min(2000, math.floor(tonumber(sz.h) + 0.5))),
                }
            end
        end
    end
    registerLayoutElements()

    -- Reset change-detection state
    lastValues = nil
    lastVehicleVisible = nil
    lastCompassDeg = nil
    localeReady = false

    syncThemeAndLocale()

    -- Resend settings with low threshold (without opening the card)
    sendUi({
        type = 'settings:apply',
        settings = settings,
        low = Config and Config.low or 20,
        span = compassSpan(),
    })

    -- Resend extra bars
    sendUi({
        type = 'hud:bars',
        bars = extraBarsRegistry.getSortedBars(false),
    })

    -- Resend part positions and hidden states from layout
    for id, place in pairs(appliedPlaces) do
        if NUI_PARTS[id] then
            sendPlace(id, place)
        end
    end

    -- Resend voice and seatbelt state (compass follows on the next tick)
    sendVoice(true)
    sendSeatbelt(lastInVehicle, true)

    -- Resend vehicle runtime visibility
    local ped = type(PlayerPedId) == 'function' and PlayerPedId() or 0
    local inVeh = (ped ~= 0 and type(IsPedInAnyVehicle) == 'function') and IsPedInAnyVehicle(ped, false) or false
    local veh = inVeh and (type(GetVehiclePedIsIn) == 'function' and GetVehiclePedIsIn(ped, false) or 0) or 0
    local isDriver = inVeh and (type(GetPedInVehicleSeat) == 'function' and GetPedInVehicleSeat(veh, -1) == ped or false)
    sendUi({
        type = 'hud:visible',
        id = 'vehicle',
        visible = isDriver,
    })
    lastVehicleVisible = isDriver
end)

RegisterNUICallback('settings', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if ignoredWhilePaused() then return end
    if type(data) ~= 'table' then return end
    local key = data.key
    local val = data.value
    local ok, err = H.validateSetting(key, val)
    if not ok then
        logWarn('aeterna_hudkit: invalid setting update', { key = key, err = err })
        return
    end
    settings[key] = val
    saveSettings(settings)
    if key == 'minimapMode' then
        local ped = type(PlayerPedId) == 'function' and PlayerPedId() or 0
        local inVeh = type(IsPedInAnyVehicle) == 'function' and IsPedInAnyVehicle(ped, false) or false
        updateMinimapVisibility(inVeh)
    end
end)

RegisterNUICallback('layoutEditor', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if ignoredWhilePaused() then return end
    closeSettings(true)
    ExecuteCommand('aeterna_layout')
end)

RegisterNUICallback('close', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if ignoredWhilePaused() then return end
    closeSettings(true)
end)

-- Commands and key mappings (literal names required by fivem-devkit safety)
RegisterCommand('aeterna_hudkit_settings', function()
    openSettings()
end, false)

RegisterCommand('+aeterna_hudkit_settings', function()
    openSettings()
end, false)

RegisterCommand('-aeterna_hudkit_settings', function() end, false)

if AeternaCore and type(AeternaCore.key) == 'function' then
    AeternaCore.key('+aeterna_hudkit_settings', 'hudkit.key.settings')
end

-- State bag change handler for needs
if type(AddStateBagChangeHandler) == 'function' and Config and Config.needs then
    for i = 1, #Config.needs do
        local needKey = Config.needs[i]
        AddStateBagChangeHandler(needKey, nil, function(bagName, key, value)
            if isOwnBag(bagName) then
                cachedNeeds[key] = tonumber(value)
            end
        end)
    end
end

local function getLocalNeed(key)
    local ok, val = pcall(function()
        if LocalPlayer and LocalPlayer.state then
            return LocalPlayer.state[key]
        end
    end)
    if ok and tonumber(val) then
        return tonumber(val)
    end
    return cachedNeeds[key]
end

-- Tick sampling thread: reads player and vehicle values
CreateThread(function()
    local interval = Config and Config.tick or 200
    while true do
        Wait(interval)

        local ped = type(PlayerPedId) == 'function' and PlayerPedId() or 0
        if ped and ped ~= 0 then
            -- Health: 100-200 -> 0-100%
            local rawHealth = (type(GetEntityHealth) == 'function') and GetEntityHealth(ped) or 200
            local health = H.mapHealth(rawHealth)

            -- Armour: 0-100
            local armour = (type(GetPedArmour) == 'function') and GetPedArmour(ped) or 0

            local statusValues = {
                health = health,
                armour = armour,
            }

            if Config and Config.needs then
                for i = 1, #Config.needs do
                    local nKey = Config.needs[i]
                    local nVal = getLocalNeed(nKey)
                    if nVal ~= nil then
                        statusValues[nKey] = nVal
                    end
                end
            end

            -- Vehicle check
            local inVeh = (type(IsPedInAnyVehicle) == 'function') and IsPedInAnyVehicle(ped, false) or false
            local veh = inVeh and (type(GetVehiclePedIsIn) == 'function' and GetVehiclePedIsIn(ped, false) or 0) or 0
            local isDriver = inVeh and (type(GetPedInVehicleSeat) == 'function' and GetPedInVehicleSeat(veh, -1) == ped or false)

            local vehicleValues = nil
            if isDriver and veh ~= 0 then
                local speedMps = (type(GetEntitySpeed) == 'function') and GetEntitySpeed(veh) or 0
                local unit = settings.speedUnit or 'kmh'
                local speedVal = (unit == 'mph') and H.speedToMph(speedMps) or H.speedToKmh(speedMps)
                local fuel = (type(GetVehicleFuelLevel) == 'function') and GetVehicleFuelLevel(veh) or 100.0

                local rawGear = (type(GetVehicleCurrentGear) == 'function') and GetVehicleCurrentGear(veh) or 0
                local isRev = false
                if type(GetEntitySpeedVector) == 'function' then
                    local speedVec = GetEntitySpeedVector(veh, true)
                    if speedVec and speedVec.y and speedVec.y < -0.1 then
                        isRev = true
                    end
                end
                local gearText = H.gearText(rawGear, isRev)

                vehicleValues = {
                    speed = speedVal,
                    unit = (unit == 'mph') and translate('hudkit.unit.mph') or translate('hudkit.unit.kmh'),
                    gear = gearText,
                    fuel = fuel,
                }
            end

            if isDriver ~= lastVehicleVisible then
                lastVehicleVisible = isDriver
                sendUi({ type = 'hud:visible', id = 'vehicle', visible = isDriver })
            end

            updateMinimapVisibility(inVeh)

            lastInVehicle = (inVeh == true)
            sendSeatbelt(lastInVehicle)

            if voiceDetector.isActive() and type(NetworkIsPlayerTalking) == 'function' then
                local ply = type(PlayerId) == 'function' and PlayerId() or 0
                voiceState.talking = NetworkIsPlayerTalking(ply) == true
                sendVoice()
            end

            -- Street and compass
            local coords = (type(GetEntityCoords) == 'function') and GetEntityCoords(ped) or vector3(0.0, 0.0, 0.0)
            local streetName = ''
            local zoneName = ''
            if type(GetStreetNameAtCoord) == 'function' and type(GetStreetNameFromHashKey) == 'function' then
                local sHash, _ = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
                if sHash then streetName = GetStreetNameFromHashKey(sHash) or '' end
            end
            if type(GetNameOfZone) == 'function' and type(GetLabelText) == 'function' then
                local zTag = GetNameOfZone(coords.x, coords.y, coords.z)
                if zTag then zoneName = GetLabelText(zTag) or '' end
            end

            local camRotZ = 0.0
            local rawCamZ = 0.0
            if type(GetGameplayCamRot) == 'function' then
                local rot = GetGameplayCamRot(2)
                if rot and rot.z then
                    rawCamZ = rot.z
                    camRotZ = (360.0 - rot.z) % 360.0
                end
            end

            -- Compass tape: only when the whole-degree heading changes.
            if compassEnabled() then
                local deg = C.fromCamRot(rawCamZ)
                if deg ~= lastCompassDeg then
                    lastCompassDeg = deg
                    sendUi({ type = 'hud:compass', deg = deg })
                end
            end
            local _, headingKey = H.headingSector(camRotZ)
            local headingText = translate(headingKey)

            local streetValues = {
                street = streetName,
                zone = zoneName,
                heading = headingText,
            }

            local currentSnapshot = {
                status = statusValues,
                vehicle = vehicleValues,
                street = streetValues,
            }

            local hasChanged, diff = H.diffValues(lastValues, currentSnapshot)
            if hasChanged and diff then
                lastValues = currentSnapshot
                sendUi({
                    type = 'hud:values',
                    status = diff.status,
                    vehicle = diff.vehicle,
                    street = diff.street,
                })
            end
        end
    end
end)

-- Resolution & safezone watcher thread
CreateThread(function()
    local lastResW, lastResH, lastSafezone = 0, 0, 0
    while true do
        Wait(1000)
        local curW, curH = 1920, 1080
        if type(GetActiveScreenResolution) == 'function' then
            curW, curH = GetActiveScreenResolution()
        end
        local curSafe = 1.0
        if type(GetSafeZoneSize) == 'function' then
            curSafe = GetSafeZoneSize()
        end

        if curW ~= lastResW or curH ~= lastResH or curSafe ~= lastSafezone then
            lastResW, lastResH, lastSafezone = curW, curH, curSafe
            registerLayoutElements()
        end

        hideBaseHealthArmour()
    end
end)

registerLayoutElements()
checkVoice()
