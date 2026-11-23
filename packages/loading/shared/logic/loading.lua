-- Pure logic for aeterna_loading: config validation, the stage reducer, tip rotation and the shutdown
-- fallback. Natives-free so stock Lua can test it. html/logic.js is the page's twin of these rules;
-- spec/loading_spec.lua and spec/logic.test.js run the same cases against both.

LoadingLogic = {}
local L = LoadingLogic

L.IMAGE_EXT = { '.jpg', '.png', '.webp' }
L.AUDIO_EXT = { '.ogg', '.mp3' }
L.STAGE = { NONE = 0, MAP = 1, SCRIPTS = 2, CHARACTER = 3 }
L.STILL_MS = 20000

local LANGS = { th = true, en = true }
local PRESETS = { asphalt = true, paper = true, ['night-market'] = true }

function L.defaults()
    return {
        version = 1,
        serverName = 'My Server',
        tagline = '',
        lang = 'en',
        preset = 'asphalt',
        background = '',
        tips = { 'Bind your keys in Settings → Key Bindings → FiveM' },
        tipSeconds = 8,
        audio = { src = '', autoplay = false, volume = 0.3 },
        shutdown = { fallbackSeconds = 30 },
    }
end

local function isNumber(v)
    return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge
end

-- Characters, not bytes: Thai text is 3 bytes per character. Invalid UTF-8 counts as too long.
local function textOk(v, minLen, maxLen)
    if type(v) ~= 'string' then return false end
    local n = utf8.len(v)
    return n ~= nil and n >= minLen and n <= maxLen
end

local function endsWith(s, suffix)
    return #s >= #suffix and s:sub(-#suffix) == suffix
end

--- A path inside this resource's html/ folder: relative, no `..`, `:` or `//`, ending in one of `exts`.
function L.isLocalPath(p, exts)
    if not textOk(p, 1, 120) then return false end
    if p:sub(1, 1) == '/' or p:find('..', 1, true) or p:find(':', 1, true) or p:find('//', 1, true) then
        return false
    end
    for i = 1, #exts do
        if endsWith(p, exts[i]) then return true end
    end
    return false
end

local function optionalPath(exts)
    return function(v) return v == '' or L.isLocalPath(v, exts) end
end

-- A list. Lua JSON decoders cannot tell {} from [], so an empty object counts as an empty list (same in logic.js).
local function tipsOk(v)
    if type(v) ~= 'table' then return false end
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    if n ~= #v or n > 30 then return false end
    for i = 1, n do
        if not textOk(v[i], 1, 160) then return false end
    end
    return true
end

local function rangeOk(lo, hi)
    return function(v) return isNumber(v) and v >= lo and v <= hi end
end

-- Field name, path into the config, check. Order is the order of the spec's table.
local FIELDS = {
    { 'serverName', { 'serverName' }, function(v) return textOk(v, 1, 40) end },
    { 'tagline', { 'tagline' }, function(v) return textOk(v, 0, 80) end },
    { 'lang', { 'lang' }, function(v) return LANGS[v] == true end },
    { 'preset', { 'preset' }, function(v) return PRESETS[v] == true end },
    { 'background', { 'background' }, optionalPath(L.IMAGE_EXT) },
    { 'tips', { 'tips' }, tipsOk },
    { 'tipSeconds', { 'tipSeconds' }, rangeOk(4, 30) },
    { 'audio.src', { 'audio', 'src' }, optionalPath(L.AUDIO_EXT) },
    { 'audio.autoplay', { 'audio', 'autoplay' }, function(v) return type(v) == 'boolean' end },
    { 'audio.volume', { 'audio', 'volume' }, rangeOk(0, 1) },
    { 'shutdown.fallbackSeconds', { 'shutdown', 'fallbackSeconds' }, rangeOk(10, 120) },
}

local function copyList(t)
    local out = {}
    for i = 1, #t do out[i] = t[i] end
    return out
end

--- Validate a decoded html/config.json. Returns the clean config and a list of { field, reason }.
--- A failing field falls back to its default; a missing field takes the default without an error.
function L.validateConfig(raw)
    local cfg = L.defaults()
    local errors = {}
    if type(raw) ~= 'table' then
        errors[1] = { field = 'config', reason = 'not a JSON object' }
        return cfg, errors
    end
    for i = 1, #FIELDS do
        local name, path, check = FIELDS[i][1], FIELDS[i][2], FIELDS[i][3]
        local v = raw
        for j = 1, #path do
            if type(v) ~= 'table' then v = nil break end
            v = v[path[j]]
        end
        if v ~= nil then
            if check(v) then
                local target = cfg
                for j = 1, #path - 1 do target = target[path[j]] end
                target[path[#path]] = (type(v) == 'table') and copyList(v) or v
            else
                errors[#errors + 1] = { field = name, reason = 'outside its limits' }
            end
        end
    end
    return cfg, errors
end

--------------------------------------------------------------------------------
-- Stage reducer
--------------------------------------------------------------------------------

function L.newState()
    return {
        stage = L.STAGE.NONE,
        percent = nil,
        closing = false,
        mapTotal = 0,
        mapDone = 0,
        orderBase = 0,
        orderCount = 0,
        orderIdx = 0,
        loadFraction = 0,
    }
end

local function copy(s)
    local out = {}
    for k, v in pairs(s) do out[k] = v end
    return out
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function wholePercent(done, total)
    if total <= 0 then return 0 end
    return math.floor(clamp(done / total, 0, 1) * 100)
end

local function enter(s, stage)
    s.stage = stage
    if stage == L.STAGE.CHARACTER then
        s.percent = nil -- indeterminate bar
    else
        s.percent = 0
    end
end

local function raise(s, p)
    if s.percent == nil or p > s.percent then s.percent = p end
end

local function scriptsPercent(s)
    local fromInit = wholePercent(s.orderBase + s.orderIdx, s.orderBase + s.orderCount)
    local fromLoad = math.floor(clamp(s.loadFraction, 0, 1) * 100)
    return math.max(fromInit, fromLoad)
end

local HANDLERS = {
    startDataFileEntries = function(s, m)
        if not isNumber(m.count) or m.count < 0 or s.stage > L.STAGE.MAP then return false end
        if s.stage < L.STAGE.MAP then enter(s, L.STAGE.MAP) end
        s.mapTotal = s.mapTotal + m.count
        raise(s, wholePercent(s.mapDone, s.mapTotal))
        return true
    end,
    onDataFileEntry = function(s)
        if s.stage ~= L.STAGE.MAP then return false end
        s.mapDone = math.min(s.mapDone + 1, s.mapTotal)
        raise(s, wholePercent(s.mapDone, s.mapTotal))
        return true
    end,
    startInitFunctionOrder = function(s, m)
        if not isNumber(m.count) or m.count < 0 or s.stage > L.STAGE.SCRIPTS then return false end
        if s.stage < L.STAGE.SCRIPTS then
            enter(s, L.STAGE.SCRIPTS)
        else
            s.orderBase = s.orderBase + s.orderCount
        end
        s.orderCount = m.count
        s.orderIdx = 0
        raise(s, scriptsPercent(s))
        return true
    end,
    initFunctionInvoking = function(s, m)
        if not isNumber(m.idx) or s.stage ~= L.STAGE.SCRIPTS then return false end
        s.orderIdx = clamp(m.idx, 0, s.orderCount)
        raise(s, scriptsPercent(s))
        return true
    end,
    loadProgress = function(s, m)
        if not isNumber(m.loadFraction) then return false end
        s.loadFraction = math.max(s.loadFraction, clamp(m.loadFraction, 0, 1))
        if s.stage == L.STAGE.SCRIPTS then raise(s, scriptsPercent(s)) end
        return true
    end,
}

--- Apply one loading-screen message. Returns a new state; the given one is not changed.
--- A message the page does not know is ignored. A stage never goes backwards; a percentage never decreases.
function L.reduce(state, msg)
    if type(msg) ~= 'table' then return state end
    local s = copy(state)
    if type(msg.eventName) == 'string' then
        local handler = HANDLERS[msg.eventName]
        if handler and handler(s, msg) then return s end
        return state
    end
    if msg.type == 'aeterna_loading:stage' and msg.stage == 'character' then
        if s.stage >= L.STAGE.CHARACTER then return state end
        enter(s, L.STAGE.CHARACTER)
        return s
    end
    if msg.type == 'aeterna_loading:closing' then
        s.closing = true
        return s
    end
    return state
end

--- True when no message arrived for STILL_MS.
function L.isStill(lastAt, now)
    return now - lastAt >= L.STILL_MS
end

--------------------------------------------------------------------------------
-- Tips and shutdown
--------------------------------------------------------------------------------

function L.clampTipSeconds(n)
    if not isNumber(n) then return 8 end
    return clamp(n, 4, 30)
end

--- 1-based index of the tip to show after `elapsedMs`, or nil to hide the tip line.
function L.tipAt(tips, tipSeconds, elapsedMs)
    if type(tips) ~= 'table' or #tips == 0 then return nil end
    local step = L.clampTipSeconds(tipSeconds) * 1000
    return math.floor(math.max(elapsedMs, 0) / step) % #tips + 1
end

--- True when `fallbackSeconds` have passed since the session started (nil = not started yet).
function L.fallbackDue(sessionStartedAt, now, fallbackSeconds)
    if sessionStartedAt == nil then return false end
    return now - sessionStartedAt >= fallbackSeconds * 1000
end

--- True when the client script should close the page: `fallbackSeconds` after the session started, or, while
--- the session has not started, `fallbackSeconds` after the resource started (hard cap, so a session that never
--- starts cannot leave the player on a manually shut-down loading screen).
function L.closeDue(resourceStartedAt, sessionStartedAt, now, fallbackSeconds)
    if sessionStartedAt ~= nil then return L.fallbackDue(sessionStartedAt, now, fallbackSeconds) end
    return L.fallbackDue(resourceStartedAt, now, fallbackSeconds)
end

return L
