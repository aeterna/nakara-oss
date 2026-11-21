-- battery.lua -- Pure logic for aeterna_phonekit battery rules.
-- Natives-free so stock Lua 5.1+ can test it.

BatteryLogic = {}
local B = BatteryLogic
local DEF = { tickSec = 10, standby = 0.25, screen = 1.0, call = 1.5, media = 2.5, vehicleSec = 300, saveStep = 5,
    pulseTtlSec = 45, warnAt = { 20, 10, 5 }, startPct = 100 }
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

-- Range per numeric `Config.battery` key: { min, max }.
local RANGES = {
    tickSec = { 5, 60 }, standby = { 0, 100 }, screen = { 0, 100 }, call = { 0, 100 }, media = { 0, 100 },
    vehicleSec = { 0, 86400 }, saveStep = { 1, 100 }, pulseTtlSec = { 1, 3600 }, startPct = { 0, 100 },
}
local KEY_ORDER = { 'tickSec', 'standby', 'screen', 'call', 'media', 'vehicleSec', 'warnAt', 'saveStep', 'pulseTtlSec', 'startPct' }

-- Returns a clean copy of `Config.battery`, or false when it is false (battery off).
-- A bad value falls back to its default and calls warn(key) once.
function B.validateConfig(cfg, warn)
    if cfg == false then return false end
    local src = type(cfg) == 'table' and cfg or {}
    local out = {}
    for _, key in ipairs(KEY_ORDER) do
        local v = src[key]
        if key == 'warnAt' then
            local okList = v == nil
            if type(v) == 'table' then
                okList = true
                for _, w in ipairs(v) do
                    if type(w) ~= 'number' or w <= 0 or w >= 100 then okList = false end
                end
            end
            if okList and v ~= nil then
                local copy = {}
                for i, w in ipairs(v) do copy[i] = w end
                out.warnAt = copy
            else
                out.warnAt = { DEF.warnAt[1], DEF.warnAt[2], DEF.warnAt[3] }
                if not okList and type(warn) == 'function' then warn(key) end
            end
        else
            local r = RANGES[key]
            if v ~= nil and (type(v) ~= 'number' or v ~= v or v < r[1] or v > r[2]) then
                if type(warn) == 'function' then warn(key) end
                v = nil
            end
            out[key] = v == nil and DEF[key] or v
        end
    end
    return out
end

-- Per-device battery state the server keeps in memory.
function B.createState(pct)
    local p = math.max(0, math.min(100, tonumber(pct) or DEF.startPct))
    return { pct = p, shown = B.shown(p), dead = p <= 0 }
end

-- Moves the state to `pct` and reports what the caller must do:
-- { shown, old, changed, save, warn = { values }, power = nil | true | false }.
function B.set(state, pct, cfg)
    local c = type(cfg) == 'table' and cfg or DEF
    local p = math.max(0, math.min(100, tonumber(pct) or 0))
    local old = state.shown
    state.pct = p
    state.shown = B.shown(p)
    local ev = { shown = state.shown, old = old, changed = old ~= state.shown, save = false, warn = {} }
    ev.save = B.shouldSave(old, state.shown, c.saveStep)
    if state.shown > 0 then
        -- several values crossed in one step: only the lowest is shown
        local crossed = B.checkWarnings(old, state.shown, c.warnAt)
        local lowest
        for _, w in ipairs(crossed) do
            if not lowest or w < lowest then lowest = w end
        end
        ev.warn = lowest and { lowest } or {}
    end
    if state.shown == 0 and not state.dead then
        state.dead = true
        ev.power = false
    elseif state.shown > 0 and state.dead then
        state.dead = false
        ev.power = true
    end
    return ev
end

-- One tick of `dtSec`. ctx = { chargers, inVehicle, screen = 'off'|'on'|'media', pulseAge, call, multiplier }.
function B.advance(state, dtSec, ctx, cfg)
    local c = type(cfg) == 'table' and cfg or DEF
    local x = type(ctx) == 'table' and ctx or {}
    local stale = x.pulseAge == nil or B.isPulseStale(x.pulseAge, c.pulseTtlSec)
    local level = stale and 'off' or x.screen
    local nextPct = B.step(state.pct, dtSec, {
        chargers = x.chargers, inVehicle = x.inVehicle, vehicleSec = c.vehicleSec,
        standby = c.standby, screenRate = c.screen, callRate = c.call, mediaRate = c.media,
        screen = level == 'on' or level == 'media', media = level == 'media', call = x.call == true,
        multiplier = x.multiplier,
    })
    return B.set(state, nextPct, c)
end

return BatteryLogic
