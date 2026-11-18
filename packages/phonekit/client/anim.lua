-- anim.lua -- Animation and prop controller for aeterna_phonekit.
-- Ped holds a phone prop and plays the base-game phone animation while open.
-- Prop and animation constants are isolated here for easy testing / Enhanced smoke checks.

PhoneAnim = {}

PhoneAnim.ANIM_DICT = 'cellphone@'
PhoneAnim.ANIM_NAME = 'cellphone_text_read_base'
PhoneAnim.PROP_MODEL = 'prop_npc_phone_02'
PhoneAnim.PROP_BONE = 28422 -- Right hand (PH_R_HAND / SKEL_R_Finger20)
PhoneAnim.PROP_OFFSET = vector3(0.0, 0.0, 0.0)
PhoneAnim.PROP_ROTATION = vector3(0.0, 0.0, 0.0)

local currentProp = nil
local isPlaying = false

function PhoneAnim.isActive()
    return isPlaying
end

function PhoneAnim.start()
    if isPlaying then return end
    if type(PlayerPedId) ~= 'function' then return end

    local ped = PlayerPedId()
    if not ped or ped == 0 or (type(DoesEntityExist) == 'function' and not DoesEntityExist(ped)) then
        return
    end

    isPlaying = true

    -- Request animation dictionary
    if type(RequestAnimDict) == 'function' and type(HasAnimDictLoaded) == 'function' then
        RequestAnimDict(PhoneAnim.ANIM_DICT)
        local timeout = 50
        while not HasAnimDictLoaded(PhoneAnim.ANIM_DICT) and timeout > 0 do
            if type(Wait) == 'function' then Wait(10) end
            timeout = timeout - 1
        end
        if type(TaskPlayAnim) == 'function' and HasAnimDictLoaded(PhoneAnim.ANIM_DICT) then
            TaskPlayAnim(ped, PhoneAnim.ANIM_DICT, PhoneAnim.ANIM_NAME, 3.0, 3.0, -1, 50, 0, false, false, false)
        end
    end

    -- Create and attach prop
    if type(GetHashKey) == 'function' and type(RequestModel) == 'function' and type(HasModelLoaded) == 'function' and type(CreateObject) == 'function' then
        local modelHash = GetHashKey(PhoneAnim.PROP_MODEL)
        RequestModel(modelHash)
        local timeout = 50
        while not HasModelLoaded(modelHash) and timeout > 0 do
            if type(Wait) == 'function' then Wait(10) end
            timeout = timeout - 1
        end

        if HasModelLoaded(modelHash) and type(GetEntityCoords) == 'function' then
            local coords = GetEntityCoords(ped)
            local prop = CreateObject(modelHash, coords.x, coords.y, coords.z, true, true, false)
            if prop and prop ~= 0 then
                currentProp = prop
                if type(GetPedBoneIndex) == 'function' and type(AttachEntityToEntity) == 'function' then
                    local boneIdx = GetPedBoneIndex(ped, PhoneAnim.PROP_BONE)
                    local off = PhoneAnim.PROP_OFFSET
                    local rot = PhoneAnim.PROP_ROTATION
                    AttachEntityToEntity(prop, ped, boneIdx, off.x, off.y, off.z, rot.x, rot.y, rot.z, true, true, false, true, 2, true)
                end
                if type(SetModelAsNoLongerNeeded) == 'function' then
                    SetModelAsNoLongerNeeded(modelHash)
                end
            end
        end
    end
end

function PhoneAnim.stop()
    if not isPlaying then return end
    isPlaying = false

    if type(PlayerPedId) == 'function' then
        local ped = PlayerPedId()
        if ped and ped ~= 0 and type(StopAnimTask) == 'function' then
            StopAnimTask(ped, PhoneAnim.ANIM_DICT, PhoneAnim.ANIM_NAME, 2.0)
        end
    end

    if currentProp and currentProp ~= 0 then
        if type(DeleteObject) == 'function' then
            DeleteObject(currentProp)
        elseif type(DeleteEntity) == 'function' then
            DeleteEntity(currentProp)
        end
        currentProp = nil
    end

    if type(RemoveAnimDict) == 'function' then
        RemoveAnimDict(PhoneAnim.ANIM_DICT)
    end
end
