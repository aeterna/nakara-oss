-- battery.lua -- Pure logic for aeterna_phonekit battery rules.
-- Natives-free so stock Lua 5.1+ can test it.

BatteryLogic = {}
local B = BatteryLogic
local DEF = { standby = 0.25, screen = 1.0, call = 1.5, media = 2.5, vehicleSec = 300, saveStep = 5, pulseTtlSec = 45, warnAt = { 20, 10, 5 } }
B.DEFAULTS = DEF

function B.shown(pct)
    local n = tonumber(pct) or 0
    return n <= 0 and 0 or math.min(100, math.ceil(n))
end

function B.isPulseStale(pulseAge, ttl)
    return (tonumber(pulseAge) or 0) > (tonumber(ttl) or DEF.pulseTtlSec)
end

function B.fastestCharger(chargers, inVehicle, vehicleSec)
    local fastest
    if inVehicle then
        local v = tonumber(vehicleSec)
        if v == nil then v = DEF.vehicleSec end
        if v > 0 then fastest = v end
    end
    if type(chargers) == 'table' then
        for _, c in pairs(chargers) do
            local sec = type(c) == 'table' and tonumber(c.secToFull) or tonumber(c)
            if sec and sec > 0 and (not fastest or sec < fastest) then fastest = sec end
        end
    end
    return fastest
end

function B.drainRate(opts)
    opts = opts or {}
    if opts.charging then return 0 end
    local standby = tonumber(opts.standby) or DEF.standby
    local screenRate = (opts.screen and not opts.stalePulse) and (tonumber(opts.screenRate) or DEF.screen) or 0
    local callRate = opts.call and (tonumber(opts.callRate) or DEF.call) or 0
    local mediaRate = opts.media and (tonumber(opts.mediaRate) or DEF.media) or 0
    local mult = tonumber(opts.multiplier) or 1
    return (standby + math.max(screenRate, math.max(callRate, mediaRate))) / (mult > 0 and mult or 1)
end

function B.step(currentPct, dtSec, opts)
    opts = opts or {}
    local pct, dt = tonumber(currentPct) or 0, tonumber(dtSec) or 0
    if dt <= 0 then return pct end
    local fastest = opts.fastestSec or B.fastestCharger(opts.chargers, opts.inVehicle, opts.vehicleSec)
    if fastest and fastest > 0 then
        return math.min(100, pct + (100 / fastest) * dt)
    end
    return math.max(0, pct - (B.drainRate(opts) / 60) * dt)
end

function B.shouldSave(oldShown, newShown, saveStep)
    if oldShown == newShown then return false end
    if newShown == 0 or newShown == 100 then return true end
    local s = tonumber(saveStep) or DEF.saveStep
    if s <= 0 then return false end
    if newShown < oldShown then
        return math.floor((oldShown - 1) / s) > math.floor((newShown - 1) / s)
    end
    return math.floor(newShown / s) > math.floor(oldShown / s)
end

function B.checkWarnings(oldShown, newShown, warnAt)
    if newShown >= oldShown then return {} end
    local crossed = {}
    for _, w in ipairs(warnAt or DEF.warnAt) do
        local val = tonumber(w)
        if val and val > 0 and oldShown > val and newShown <= val then
            crossed[#crossed + 1] = val
        end
    end
    return crossed
end

return BatteryLogic
