-- shared/logic/seatbelt.lua -- natives-free seatbelt display state (spec aeterna_hudkit.md § Seatbelt state).
-- hudkit has no seatbelt system: it shows the last state another resource fired.

SeatbeltLogic = SeatbeltLogic or {}

function SeatbeltLogic.create(opts)
    local warn = (type(opts) == 'table' and opts.warn) or function() end
    local state = nil -- true | false | nil
    local owner = nil
    local S = {}

    --- payload { on = boolean } sets the state; nil clears it. Returns false (and warns) for anything else.
    function S.set(by, payload)
        if payload == nil then
            state, owner = nil, nil
            return true
        end
        if type(payload) ~= 'table' or type(payload.on) ~= 'boolean' then
            warn('aeterna_hudkit: seatbelt payload must be { on = boolean } or nil', { owner = by })
            return false
        end
        state, owner = payload.on, by
        return true
    end

    --- The owning resource stopped: hide the icon. Returns true when that changed something.
    function S.ownerStopped(res)
        if owner == nil or res ~= owner then return false end
        state, owner = nil, nil
        return true
    end

    --- What the vehicle part shows: true (fastened), false (unfastened) or nil (hidden).
    function S.display(inVehicle)
        if inVehicle ~= true then return nil end
        return state
    end

    function S.owner()
        return owner
    end

    return S
end

return SeatbeltLogic
