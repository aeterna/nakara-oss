-- shared/logic/voice.lua -- natives-free voice indicator logic (spec aeterna_hudkit.md § Voice indicator).
-- pma-voice is detected at run time only: never a dependency, never an export call.

VoiceLogic = VoiceLogic or {}

VoiceLogic.RESOURCE = 'pma-voice'

--- Tracks whether the voice element is registered. update(state) takes a GetResourceState value and returns
--- 'register' (became started), 'remove' (was started, is not now) or nil (no change). Disabled = always nil.
function VoiceLogic.createDetector(opts)
    local enabled = not (type(opts) == 'table' and opts.enabled == false)
    local active = false
    local d = {}

    function d.update(state)
        if not enabled then return nil end
        local started = (state == 'started')
        if started and not active then
            active = true
            return 'register'
        elseif not started and active then
            active = false
            return 'remove'
        end
        return nil
    end

    function d.isActive()
        return active
    end

    return d
end

local function formatMeters(distance)
    if distance == math.floor(distance) then
        return string.format('%d', distance)
    end
    return (string.format('%.1f', distance):gsub('%.0$', ''))
end

--- Label of the proximity state bag value { index, distance, mode }:
--- index 1-3 -> { key = 'hudkit.voice.mode.<index>' }; otherwise { meters = '<distance>' }; nothing usable -> nil.
function VoiceLogic.modeLabel(proximity)
    if type(proximity) ~= 'table' then return nil end
    local index = tonumber(proximity.index)
    if index and index >= 1 and index <= 3 and index == math.floor(index) then
        return { key = 'hudkit.voice.mode.' .. index }
    end
    local distance = tonumber(proximity.distance)
    if distance and distance > 0 then
        return { meters = formatMeters(distance) }
    end
    return nil
end

--- radioChannel state bag value: a number above 0 means on a channel.
function VoiceLogic.radioOn(channel)
    local c = tonumber(channel)
    return c ~= nil and c > 0
end

return VoiceLogic
