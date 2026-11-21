-- shared/logic/hud.lua -- natives-free HUD logic: health, speed, heading, diffing, extra bars, settings.

HudLogic = HudLogic or {}

--- Health mapping: 100-200 -> 0-100%, clamped outside.
--- In FiveM, a normal ped dies at 100 health; 100 is 0% and 200 is 100%.
function HudLogic.mapHealth(rawHealth)
    if type(rawHealth) ~= 'number' then return 0 end
    if rawHealth <= 100 then return 0 end
    if rawHealth >= 200 then return 100 end
    return math.floor((rawHealth - 100) + 0.5)
end

--- Speed conversions: m/s -> km/h and mph rounded to whole numbers.
function HudLogic.speedToKmh(mps)
    local s = tonumber(mps) or 0
    if s <= 0 then return 0 end
    return math.floor(s * 3.6 + 0.5)
end

function HudLogic.speedToMph(mps)
    local s = tonumber(mps) or 0
    if s <= 0 then return 0 end
    return math.floor(s * 2.236936 + 0.5)
end

--- Gear text: 'R' when reverse/moving backward, 'N' at 0, 1-8.
function HudLogic.gearText(gear, isReverse)
    if isReverse == true or gear == -1 or gear == 'R' then
        return 'R'
    end
    local num = tonumber(gear)
    if not num or num == 0 then
        return 'N'
    end
    return tostring(math.floor(num))
end

--- Heading 8 sectors (N, NE, E, SE, S, SW, W, NW) with 360 wrap.
local SECTORS = { 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW' }
local LOCALE_DIRS = {
    N = 'hudkit.dir.n',
    NE = 'hudkit.dir.ne',
    E = 'hudkit.dir.e',
    SE = 'hudkit.dir.se',
    S = 'hudkit.dir.s',
    SW = 'hudkit.dir.sw',
    W = 'hudkit.dir.w',
    NW = 'hudkit.dir.nw',
}

function HudLogic.headingSector(camRotZ)
    local rot = tonumber(camRotZ) or 0.0
    -- Normalize to [0, 360)
    local deg = (rot % 360 + 360) % 360
    -- Adding 22.5 shifts the boundary so [337.5, 360) and [0, 22.5) both map to index 1 ('N')
    local shifted = (deg + 22.5) % 360
    local index = math.floor(shifted / 45) + 1
    local code = SECTORS[index] or 'N'
    return code, LOCALE_DIRS[code]
end

local RESERVED_BAR_IDS = {
    health = true,
    armour = true,
    hunger = true,
    thirst = true,
    stress = true,
}

--- Ring gauge (0.2): the filled fraction of the circle, 0-1, for a 0-100 value; out of range clamps.
--- html/app.js draws rings with a circumference of 100, so the dash length equals the clamped percentage.
function HudLogic.ringArc(value)
    local v = tonumber(value)
    if not v or v <= 0 then return 0 end
    if v >= 100 then return 1 end
    return v / 100
end

--- Stroke dash for a ring of `circumference`: `length` is drawn, `offset` is the stroke-dashoffset.
function HudLogic.ringDash(value, circumference)
    local c = tonumber(circumference) or 100
    local f = HudLogic.ringArc(value)
    return { length = c * f, offset = c * (1 - f) }
end

--- Colour of a bar or ring: 'accent' for health, 'bad' at or below `low`, else 'normal' (--text-2).
function HudLogic.barTone(id, value, low)
    if id == 'health' then return 'accent' end
    local threshold = tonumber(low) or 20
    local v = tonumber(value)
    if v and v <= threshold then return 'bad' end
    return 'normal'
end

--- Extra bars registry
function HudLogic.createBarsRegistry(options)
    local opts = options or {}
    local warn = opts.warn or function() end
    local maxBars = opts.maxBars or 8
    local bars = {} -- id -> barDef

    local M = {}

    function M.add(owner, def)
        if type(def) ~= 'table' then
            warn('aeterna_hudkit: extra bar definition must be a table', { owner = owner })
            return false
        end
        local id = def.id
        if type(id) ~= 'string' or #id < 1 or #id > 32 or not id:match('^[%w_%-]+$') then
            warn('aeterna_hudkit: extra bar invalid id', { owner = owner, id = id })
            return false
        end
        if RESERVED_BAR_IDS[id] then
            warn('aeterna_hudkit: extra bar reserved id', { owner = owner, id = id })
            return false
        end
        local label = def.label
        -- Length in characters, not bytes (Thai is 3 bytes each); invalid UTF-8 (utf8.len -> nil) is refused.
        local labelLen = type(label) == 'string' and utf8.len(label) or nil
        if not labelLen or labelLen < 1 or labelLen > 24 then
            warn('aeterna_hudkit: extra bar invalid label', { owner = owner, id = id })
            return false
        end
        local icon = def.icon
        if type(icon) ~= 'string' or #icon < 1 or #icon > 32 then
            warn('aeterna_hudkit: extra bar invalid icon', { owner = owner, id = id })
            return false
        end
        local val = def.value
        if val ~= nil then
            if type(val) ~= 'number' or val < 0 or val > 100 then
                warn('aeterna_hudkit: extra bar invalid value', { owner = owner, id = id, value = val })
                return false
            end
        end
        local order = tonumber(def.order) or 100

        if bars[id] then
            if bars[id].owner and bars[id].owner ~= owner then
                warn('aeterna_hudkit: extra bar id already owned by another resource', { owner = owner, id = id, currentOwner = bars[id].owner })
                return false
            end
        else
            local count = 0
            for _ in pairs(bars) do count = count + 1 end
            if count >= maxBars then
                warn('aeterna_hudkit: extra bar refused, maximum reached', { owner = owner, id = id, max = maxBars })
                return false
            end
        end

        bars[id] = {
            id = id,
            label = label,
            icon = icon,
            value = val,
            order = order,
            owner = owner,
            hidden = (val == nil),
        }
        return true
    end

    function M.remove(owner, id)
        if not id or not bars[id] then return false end
        if owner and bars[id].owner and bars[id].owner ~= owner then
            return false
        end
        bars[id] = nil
        return true
    end

    function M.removeByOwner(owner)
        if not owner then return 0 end
        local removed = 0
        for id, bar in pairs(bars) do
            if bar.owner == owner then
                bars[id] = nil
                removed = removed + 1
            end
        end
        return removed
    end

    function M.get(id)
        return bars[id]
    end

    function M.count()
        local c = 0
        for _ in pairs(bars) do c = c + 1 end
        return c
    end

    --- Returns bars sorted by order then id
    function M.getSortedBars(visibleOnly)
        local list = {}
        for _, bar in pairs(bars) do
            if not visibleOnly or bar.value ~= nil then
                list[#list + 1] = bar
            end
        end
        table.sort(list, function(a, b)
            if a.order ~= b.order then
                return a.order < b.order
            end
            return a.id < b.id
        end)
        return list
    end

    return M
end

--- Sentinel / JSON null support
local NULL_VALUE = (json and json.null ~= nil) and json.null
if NULL_VALUE == nil then
    local ok, dk = pcall(require, 'dkjson')
    if ok and type(dk) == 'table' and dk.null ~= nil then
        NULL_VALUE = dk.null
    end
end
if NULL_VALUE == nil then
    NULL_VALUE = setmetatable({}, { __tostring = function() return 'null' end })
end
if json and json.null == nil then
    json.null = NULL_VALUE
end
HudLogic.NULL = NULL_VALUE

--- Change detection / diffing
function HudLogic.diffValues(previous, current)
    if not previous then
        return true, current
    end
    if not current then
        return false, nil
    end
    local changed = {}
    local anyChanged = false
    for sectionKey, sectionVal in pairs(current) do
        if type(sectionVal) == 'table' then
            local prevSection = previous[sectionKey]
            local sectionDiff = nil
            for k, v in pairs(sectionVal) do
                if not prevSection or prevSection[k] ~= v then
                    sectionDiff = sectionDiff or {}
                    sectionDiff[k] = v
                    anyChanged = true
                end
            end
            if prevSection and type(prevSection) == 'table' then
                for k in pairs(prevSection) do
                    if sectionVal[k] == nil then
                        sectionDiff = sectionDiff or {}
                        sectionDiff[k] = HudLogic.NULL
                        anyChanged = true
                    end
                end
            end
            if sectionDiff then
                changed[sectionKey] = sectionDiff
            end
        else
            if previous[sectionKey] ~= sectionVal then
                changed[sectionKey] = sectionVal
                anyChanged = true
            end
        end
    end
    for sectionKey, prevVal in pairs(previous) do
        if current[sectionKey] == nil and prevVal ~= nil then
            changed[sectionKey] = HudLogic.NULL
            anyChanged = true
        end
    end
    return anyChanged, (anyChanged and changed or nil)
end

--- Settings validation and KVP round trip
local VALID_SPEED_UNITS = { kmh = true, mph = true }
local VALID_MINIMAP_MODES = { always = true, vehicle = true, never = true }
local VALID_BAR_STYLES = { bar = true, ring = true }

function HudLogic.validateSetting(key, value)
    if key == 'numbers' then
        if type(value) ~= 'boolean' then
            return false, 'value must be boolean'
        end
        return true, nil
    elseif key == 'speedUnit' then
        if type(value) ~= 'string' or not VALID_SPEED_UNITS[value] then
            return false, 'value must be kmh or mph'
        end
        return true, nil
    elseif key == 'minimapMode' then
        if type(value) ~= 'string' or not VALID_MINIMAP_MODES[value] then
            return false, 'value must be always, vehicle, or never'
        end
        return true, nil
    elseif key == 'barStyle' then
        if type(value) ~= 'string' or not VALID_BAR_STYLES[value] then
            return false, 'value must be bar or ring'
        end
        return true, nil
    end
    return false, 'unknown setting key'
end

function HudLogic.resolveSettings(stored, defaults)
    local def = defaults or {
        numbers = false,
        speedUnit = 'kmh',
        minimapMode = 'always',
        barStyle = 'bar',
    }
    local s = {}
    s.numbers = (stored and type(stored.numbers) == 'boolean') and stored.numbers or def.numbers
    s.speedUnit = (stored and stored.speedUnit and VALID_SPEED_UNITS[stored.speedUnit]) and stored.speedUnit or def.speedUnit
    s.minimapMode = (stored and stored.minimapMode and VALID_MINIMAP_MODES[stored.minimapMode]) and stored.minimapMode or def.minimapMode
    -- 0.2: a saved 0.1 value has no barStyle and reads as the default (Config.barStyle).
    s.barStyle = (stored and stored.barStyle and VALID_BAR_STYLES[stored.barStyle]) and stored.barStyle or def.barStyle or 'bar'
    return s
end

return HudLogic
