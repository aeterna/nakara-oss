-- aeterna_invkit client: stash proximity key hints, key mapping (+aeterna_invkit_open),
-- item-use progress bar with animation/prop handling, and refusal event handling.

local L = InvkitLogic

local showingHint = false
local activeUseId = nil

local function logWarn(msg, fields)
    if AeternaCore and AeternaCore.log and type(AeternaCore.log.warn) == 'function' then
        AeternaCore.log.warn(msg, fields)
    end
end

local function logDebug(msg, fields)
    if AeternaCore and AeternaCore.log and type(AeternaCore.log.debug) == 'function' then
        AeternaCore.log.debug(msg, fields)
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

local function showRefusalFeed(reason)
    if type(BeginTextCommandThefeedPost) ~= 'function'
        or type(AddTextComponentSubstringPlayerName) ~= 'function'
        or type(EndTextCommandThefeedPostTicker) ~= 'function' then
        return false
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(reason)
    EndTextCommandThefeedPostTicker(false, false)
    return true
end

local function showStashHint()
    if showingHint then return end
    showingHint = true
    pcall(function()
        exports.aeterna_uikit:keyHints({
            { key = '+aeterna_invkit_open', label = translate('invkit.stash.hint') },
        })
    end)
end

local function hideStashHint()
    if not showingHint then return end
    showingHint = false
    pcall(function()
        exports.aeterna_uikit:clearKeyHints()
    end)
end

local function startAnim(ped, anim, duration)
    if type(anim) ~= 'table' or type(anim.dict) ~= 'string' or type(anim.clip) ~= 'string' then
        return false
    end
    if type(RequestAnimDict) == 'function' then
        RequestAnimDict(anim.dict)
        if type(HasAnimDictLoaded) == 'function' then
            local tries = 0
            while not HasAnimDictLoaded(anim.dict) and tries < 50 do
                tries = tries + 1
                Wait(10)
            end
        end
    end
    if type(TaskPlayAnim) == 'function' then
        TaskPlayAnim(
            ped,
            anim.dict,
            anim.clip,
            8.0,
            -8.0,
            tonumber(duration) or -1,
            tonumber(anim.flag) or 49,
            0.0,
            false,
            false,
            false
        )
        return true
    end
    return false
end

local function stopAnim(ped, anim)
    if type(anim) ~= 'table' then return end
    if type(StopAnimTask) == 'function' and type(anim.dict) == 'string' and type(anim.clip) == 'string' then
        StopAnimTask(ped, anim.dict, anim.clip, 1.0)
    elseif type(ClearPedSecondaryTask) == 'function' then
        ClearPedSecondaryTask(ped)
    end
end

local function attachProp(ped, prop)
    if type(prop) ~= 'table' or prop.model == nil then
        return nil
    end
    if type(CreateObject) ~= 'function' then
        return nil
    end
    local modelHash = prop.model
    if type(modelHash) == 'string' and type(GetHashKey) == 'function' then
        modelHash = GetHashKey(modelHash)
    end
    if type(RequestModel) == 'function' then
        RequestModel(modelHash)
        if type(HasModelLoaded) == 'function' then
            local tries = 0
            while not HasModelLoaded(modelHash) and tries < 50 do
                tries = tries + 1
                Wait(10)
            end
        end
    end
    local coords = type(GetEntityCoords) == 'function' and GetEntityCoords(ped) or { x = 0.0, y = 0.0, z = 0.0 }
    local obj = CreateObject(modelHash, coords.x or 0.0, coords.y or 0.0, coords.z or 0.0, true, true, false)
    if obj and obj ~= 0 and type(AttachEntityToEntity) == 'function' then
        local boneIdx = 0
        if type(GetPedBoneIndex) == 'function' then
            boneIdx = GetPedBoneIndex(ped, tonumber(prop.bone) or 60309)
        end
        local pos = type(prop.pos) == 'table' and prop.pos or { x = 0.0, y = 0.0, z = 0.0 }
        local rot = type(prop.rot) == 'table' and prop.rot or { x = 0.0, y = 0.0, z = 0.0 }
        AttachEntityToEntity(
            obj,
            ped,
            boneIdx,
            tonumber(pos.x) or 0.0,
            tonumber(pos.y) or 0.0,
            tonumber(pos.z) or 0.0,
            tonumber(rot.x) or 0.0,
            tonumber(rot.y) or 0.0,
            tonumber(rot.z) or 0.0,
            true,
            true,
            false,
            true,
            1,
            true
        )
    end
    return obj
end

local function cleanupProp(obj)
    if not obj or obj == 0 then return end
    if type(DetachEntity) == 'function' then
        DetachEntity(obj, true, true)
    end
    if type(DeleteEntity) == 'function' then
        DeleteEntity(obj)
    end
end

-- Proximity loop for stash key hints
CreateThread(function()
    while true do
        local points = (Config and Config.stash and type(Config.stash.points) == 'table') and Config.stash.points or nil
        if points and #points > 0 and type(GetEntityCoords) == 'function' then
            local ped = type(PlayerPedId) == 'function' and PlayerPedId() or 1
            local coords = GetEntityCoords(ped)
            local near = L.nearestPoint(coords, points)
            if near then
                showStashHint()
                Wait(250)
            else
                hideStashHint()
                Wait(500)
            end
        else
            hideStashHint()
            Wait(1000)
        end
    end
end)

-- Server -> Client Net Events
RegisterNetEvent('aeterna_invkit:cl:use', function(data)
    if type(data) ~= 'table' or not L.isValidId(data.useId, 24) then
        logWarn('aeterna_invkit:cl:use invalid payload')
        return
    end
    if activeUseId ~= nil then
        TriggerServerEvent('aeterna_invkit:sv:cancel', { useId = data.useId })
        return
    end

    local useId = data.useId
    local duration = tonumber(data.duration) or 2000
    local label = type(data.label) == 'string' and L.textClean(data.label, 60) or useId
    local cancelable = data.cancelable ~= false

    activeUseId = useId
    local ped = type(PlayerPedId) == 'function' and PlayerPedId() or 1
    local playingAnim = startAnim(ped, data.anim, duration)
    local propObj = attachProp(ped, data.prop)

    local okProg, finished = pcall(function()
        return exports.aeterna_uikit:progress({
            label = label,
            duration = duration,
            cancelable = cancelable,
        })
    end)

    if playingAnim then
        stopAnim(ped, data.anim)
    end
    cleanupProp(propObj)

    if activeUseId == useId then
        activeUseId = nil
    end

    if okProg and finished == true then
        TriggerServerEvent('aeterna_invkit:sv:done', { useId = useId })
    else
        TriggerServerEvent('aeterna_invkit:sv:cancel', { useId = useId })
    end
end)

RegisterNetEvent('aeterna_invkit:cl:refused', function(data)
    local ok, err, clean = L.validateRefusedPayload(data)
    if not ok then
        logWarn('aeterna_invkit:cl:refused invalid payload', { err = err })
        return
    end
    logDebug('item or stash action refused', { item = clean.item, reason = clean.reason })
    showRefusalFeed(translate(clean.reason))
    if AeternaCore and type(AeternaCore.emit) == 'function' then
        AeternaCore.emit('invkit:refused', clean)
    end
end)

AddEventHandler('onResourceStop', function(resName)
    local selfName = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_invkit'
    if resName == selfName then
        hideStashHint()
    end
end)

-- Commands and key mappings (literal names required by fivem-devkit safety)
RegisterCommand('+aeterna_invkit_open', function()
    TriggerServerEvent('aeterna_invkit:sv:open')
end, false)

RegisterCommand('-aeterna_invkit_open', function() end, false)

if AeternaCore and type(AeternaCore.key) == 'function' then
    AeternaCore.key('+aeterna_invkit_open', 'invkit.key.open')
end
