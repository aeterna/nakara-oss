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
        local label = def.label
        if type(label) ~= 'string' or #label < 1 or #label > 24 then
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

        if not bars[id] then
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
    return anyChanged, (anyChanged and changed or nil)
end

--- Settings validation and KVP round trip
local VALID_SPEED_UNITS = { kmh = true, mph = true }
local VALID_MINIMAP_MODES = { always = true, vehicle = true, never = true }

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
    end
    return false, 'unknown setting key'
end

function HudLogic.resolveSettings(stored, defaults)
    local def = defaults or {
        numbers = false,
        speedUnit = 'kmh',
        minimapMode = 'always',
    }
    local s = {}
    s.numbers = (stored and type(stored.numbers) == 'boolean') and stored.numbers or def.numbers
    s.speedUnit = (stored and stored.speedUnit and VALID_SPEED_UNITS[stored.speedUnit]) and stored.speedUnit or def.speedUnit
    s.minimapMode = (stored and stored.minimapMode and VALID_MINIMAP_MODES[stored.minimapMode]) and stored.minimapMode or def.minimapMode
    return s
end

return HudLogic
