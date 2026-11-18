-- @aeterna_core/import.lua -- shared AeternaCore library loaded into every Starter Kit resource.

AeternaCoreLogic = AeternaCoreLogic or {}
Locales = Locales or {}
Locales.en = Locales.en or {}
Locales.th = Locales.th or {}
AeternaCore = AeternaCore or {}

local DEFAULT_EN = {
    ['core.month.1'] = 'January',
    ['core.month.2'] = 'February',
    ['core.month.3'] = 'March',
    ['core.month.4'] = 'April',
    ['core.month.5'] = 'May',
    ['core.month.6'] = 'June',
    ['core.month.7'] = 'July',
    ['core.month.8'] = 'August',
    ['core.month.9'] = 'September',
    ['core.month.10'] = 'October',
    ['core.month.11'] = 'November',
    ['core.month.12'] = 'December',
    ['core.wday.1'] = 'Sunday',
    ['core.wday.2'] = 'Monday',
    ['core.wday.3'] = 'Tuesday',
    ['core.wday.4'] = 'Wednesday',
    ['core.wday.5'] = 'Thursday',
    ['core.wday.6'] = 'Friday',
    ['core.wday.7'] = 'Saturday',
    ['core.selftest.pass'] = 'PASS {name} ({ms} ms)',
    ['core.selftest.fail'] = 'FAIL {name} ({ms} ms): {detail}',
    ['core.selftest.total'] = '{passed}/{total} passed',
}

local DEFAULT_TH = {
    ['core.month.1'] = 'มกราคม',
    ['core.month.2'] = 'กุมภาพันธ์',
    ['core.month.3'] = 'มีนาคม',
    ['core.month.4'] = 'เมษายน',
    ['core.month.5'] = 'พฤษภาคม',
    ['core.month.6'] = 'มิถุนายน',
    ['core.month.7'] = 'กรกฎาคม',
    ['core.month.8'] = 'สิงหาคม',
    ['core.month.9'] = 'กันยายน',
    ['core.month.10'] = 'ตุลาคม',
    ['core.month.11'] = 'พฤศจิกายน',
    ['core.month.12'] = 'ธันวาคม',
    ['core.wday.1'] = 'วันอาทิตย์',
    ['core.wday.2'] = 'วันจันทร์',
    ['core.wday.3'] = 'วันอังคาร',
    ['core.wday.4'] = 'วันพุธ',
    ['core.wday.5'] = 'วันพฤหัสบดี',
    ['core.wday.6'] = 'วันศุกร์',
    ['core.wday.7'] = 'วันเสาร์',
    ['core.selftest.pass'] = 'ผ่าน {name} ({ms} ms)',
    ['core.selftest.fail'] = 'ไม่ผ่าน {name} ({ms} ms): {detail}',
    ['core.selftest.total'] = 'ผ่าน {passed}/{total} รายการ',
}

for k, v in pairs(DEFAULT_EN) do
    if Locales.en[k] == nil then Locales.en[k] = v end
end
for k, v in pairs(DEFAULT_TH) do
    if Locales.th[k] == nil then Locales.th[k] = v end
end

local LOG_LEVELS = {
    debug = 1,
    info = 2,
    warn = 3,
    error = 4,
}

local LOG_LABELS = {
    debug = 'DEBUG',
    info = 'INFO',
    warn = 'WARN',
    error = 'ERROR',
}

local warnedConvars = {}

local function resourceTag()
    local res = tostring(GetCurrentResourceName() or 'core')
    if res:sub(1, 8) == 'aeterna_' then
        return res
    end
    return 'aeterna_' .. res
end

--------------------------------------------------------------------------------
-- Text helpers (uses AeternaCoreLogic.text when loaded, with self-contained fallback)
--------------------------------------------------------------------------------

local textMod = AeternaCoreLogic.text
if not textMod then
    local function isCont(b)
        return b ~= nil and b >= 0x80 and b <= 0xBF
    end

    local function decodeNext(s, i, len)
        local b1 = s:byte(i)
        if b1 <= 0x7F then
            return b1, i + 1
        elseif b1 >= 0xC2 and b1 <= 0xDF then
            if i + 1 > len then return nil, i + 1 end
            local b2 = s:byte(i + 1)
            if not isCont(b2) then return nil, i + 1 end
            return (b1 - 0xC0) * 64 + (b2 - 0x80), i + 2
        elseif b1 >= 0xE0 and b1 <= 0xEF then
            if i + 2 > len then return nil, i + 1 end
            local b2, b3 = s:byte(i + 1, i + 2)
            if not isCont(b2) or not isCont(b3) then return nil, i + 1 end
            if b1 == 0xE0 and b2 < 0xA0 then return nil, i + 1 end
            if b1 == 0xED and b2 > 0x9F then return nil, i + 1 end
            return (b1 - 0xE0) * 4096 + (b2 - 0x80) * 64 + (b3 - 0x80), i + 3
        elseif b1 >= 0xF0 and b1 <= 0xF4 then
            if i + 3 > len then return nil, i + 1 end
            local b2, b3, b4 = s:byte(i + 1, i + 3)
            if not isCont(b2) or not isCont(b3) or not isCont(b4) then return nil, i + 1 end
            if b1 == 0xF0 and b2 < 0x90 then return nil, i + 1 end
            if b1 == 0xF4 and b2 > 0x8F then return nil, i + 1 end
            return (b1 - 0xF0) * 262144 + (b2 - 0x80) * 4096 + (b3 - 0x80) * 64 + (b4 - 0x80), i + 4
        end
        return nil, i + 1
    end

    local function isCombining(cp)
        return cp == 0x0E31
            or (cp >= 0x0E34 and cp <= 0x0E3A)
            or (cp >= 0x0E47 and cp <= 0x0E4E)
    end

    local function isControl(cp)
        return (cp >= 0x0000 and cp <= 0x001F)
            or cp == 0x007F
            or (cp >= 0x200B and cp <= 0x200F)
            or (cp >= 0x202A and cp <= 0x202E)
    end

    textMod = {}

    function textMod.len(s)
        if type(s) ~= 'string' then
            if s == nil then return 0 end
            s = tostring(s)
        end
        local byteLen = #s
        local i = 1
        local count = 0
        while i <= byteLen do
            local cp, nextIdx = decodeNext(s, i, byteLen)
            if cp ~= nil and not isCombining(cp) then
                count = count + 1
            end
            i = nextIdx
        end
        return count
    end

    function textMod.cut(s, n)
        if type(s) ~= 'string' then
            if s == nil then return '' end
            s = tostring(s)
        end
        if n ~= nil and n <= 0 then
            return ''
        end
        local byteLen = #s
        local i = 1
        local count = 0
        local hasBase = false
        local out = {}
        while i <= byteLen do
            local cp, nextIdx = decodeNext(s, i, byteLen)
            if cp ~= nil then
                if isCombining(cp) then
                    if hasBase then
                        out[#out + 1] = s:sub(i, nextIdx - 1)
                    end
                else
                    if n ~= nil and count >= n then
                        break
                    end
                    count = count + 1
                    hasBase = true
                    out[#out + 1] = s:sub(i, nextIdx - 1)
                end
            end
            i = nextIdx
        end
        return table.concat(out)
    end

    function textMod.clean(s, maxLen)
        if type(s) ~= 'string' then
            if s == nil then return '' end
            s = tostring(s)
        end
        local byteLen = #s
        local i = 1
        local buf = {}
        while i <= byteLen do
            local cp, nextIdx = decodeNext(s, i, byteLen)
            if cp ~= nil and not isControl(cp) then
                buf[#buf + 1] = s:sub(i, nextIdx - 1)
            end
            i = nextIdx
        end
        local stripped = table.concat(buf)
        local trimmed = stripped:match('^%s*(.-)%s*$') or ''
        return textMod.cut(trimmed, maxLen)
    end
end

AeternaCore.text = {
    len = textMod.len,
    cut = textMod.cut,
    clean = textMod.clean,
}

--------------------------------------------------------------------------------
-- Logging
--------------------------------------------------------------------------------

local function formatLogLine(levelName, msg, fields)
    local prefix = '[' .. resourceTag() .. '] ' .. (LOG_LABELS[levelName] or 'INFO') .. ' ' .. tostring(msg or '')
    if type(fields) ~= 'table' then
        return prefix
    end
    local keys = {}
    for k in pairs(fields) do
        keys[#keys + 1] = k
    end
    if #keys == 0 then
        return prefix
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = { prefix }
    for i = 1, #keys do
        local k = keys[i]
        local v = textMod.cut(tostring(fields[k]), 200)
        parts[#parts + 1] = tostring(k) .. '=' .. v
    end
    return table.concat(parts, ' ')
end

local function currentLogLevel()
    local raw = GetConvar('aeterna_core_log_level', 'info')
    local lvl = LOG_LEVELS[raw]
    if lvl then
        return lvl
    end
    if warnedConvars.aeterna_core_log_level ~= raw then
        warnedConvars.aeterna_core_log_level = raw
        print(formatLogLine('warn', 'invalid aeterna_core_log_level; falling back to info', { value = raw }))
    end
    return LOG_LEVELS.info
end

local function writeLog(levelName, msg, fields)
    local target = LOG_LEVELS[levelName] or LOG_LEVELS.info
    if target < currentLogLevel() then
        return nil
    end
    print(formatLogLine(levelName, msg, fields))
    return nil
end

AeternaCore.log = {
    debug = function(msg, fields) return writeLog('debug', msg, fields) end,
    info = function(msg, fields) return writeLog('info', msg, fields) end,
    warn = function(msg, fields) return writeLog('warn', msg, fields) end,
    error = function(msg, fields) return writeLog('error', msg, fields) end,
}

--------------------------------------------------------------------------------
-- Event bus (local to one side of one resource)
--------------------------------------------------------------------------------

function AeternaCore.on(name, fn)
    local handle = { active = true }
    handle.id = AddEventHandler('aeterna_core:bus:' .. tostring(name), function(...)
        if handle.active then
            fn(...)
        end
    end)
    return handle
end

function AeternaCore.off(handle)
    if type(handle) == 'table' then
        handle.active = false
        if handle.id then
            RemoveEventHandler(handle.id)
        end
    elseif handle ~= nil then
        RemoveEventHandler(handle)
    end
    return nil
end

function AeternaCore.emit(name, ...)
    TriggerEvent('aeterna_core:bus:' .. tostring(name), ...)
    return nil
end

--------------------------------------------------------------------------------
-- Locale
--------------------------------------------------------------------------------

function AeternaCore.lang()
    local raw = GetConvar('aeterna_locale', 'en')
    if raw == 'th' or raw == 'en' then
        return raw
    end
    if warnedConvars.aeterna_locale ~= raw then
        warnedConvars.aeterna_locale = raw
        AeternaCore.log.warn('invalid aeterna_locale; falling back to en', { value = raw })
    end
    return 'en'
end

local localeMod = AeternaCoreLogic.locale
function AeternaCore.t(key, vars)
    local lang = AeternaCore.lang()
    if localeMod and localeMod.t then
        return localeMod.t(Locales, lang, key, vars)
    end
    if key == nil then return '' end
    local keyStr = tostring(key)
    local str = (Locales[lang] and Locales[lang][keyStr]) or (Locales.en and Locales.en[keyStr]) or keyStr
    if type(vars) == 'table' then
        str = str:gsub('{([%w_]+)}', function(k)
            local v = vars[k]
            if v == nil then return '{' .. k .. '}' end
            return tostring(v)
        end)
    end
    return str
end

--------------------------------------------------------------------------------
-- Time
--------------------------------------------------------------------------------

local timeMod = AeternaCoreLogic.time
if not timeMod then
    timeMod = {}
    function timeMod.parseOffset(tzStr)
        if type(tzStr) ~= 'string' then return nil end
        local sign, h, m = tzStr:match('^([%+%-])(%d%d):(%d%d)$')
        if not sign then return nil end
        local hh, mm = tonumber(h), tonumber(m)
        if not hh or not mm or hh < 0 or hh > 23 or mm < 0 or mm > 59 then return nil end
        local total = hh * 3600 + mm * 60
        if sign == '-' then return -total end
        return total
    end

    function timeMod.parts(ts, tzStr)
        local unix = math.floor(tonumber(ts) or 0)
        local offset = timeMod.parseOffset(tzStr or '+00:00') or 0
        local localTs = unix + offset
        local days = math.floor(localTs / 86400)
        local rem = localTs - days * 86400
        local hour = math.floor(rem / 3600)
        rem = rem - hour * 3600
        local min = math.floor(rem / 60)
        local sec = math.floor(rem - min * 60)
        local wday = ((days + 4) % 7) + 1
        local z = days + 719468
        local era = math.floor((z >= 0 and z or (z - 146096)) / 146097)
        local doe = z - era * 146097
        local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
        local y = yoe + era * 400
        local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
        local mp = math.floor((5 * doy + 2) / 153)
        local d = doy - math.floor((153 * mp + 2) / 5) + 1
        local m = mp + (mp < 10 and 3 or -9)
        if m <= 2 then y = y + 1 end
        return { year = y, month = m, day = d, hour = hour, min = min, sec = sec, wday = wday }
    end

    function timeMod.format(ts, pattern, tzStr, translateFn)
        local p = timeMod.parts(ts, tzStr)
        local pat = tostring(pattern or 'YYYY-MM-DD HH:mm:ss')
        local tFn = translateFn or function(k) return k end
        local tokens = {
            YYYY = string.format('%04d', p.year),
            MMMM = tostring(tFn('core.month.' .. tostring(p.month))),
            dddd = tostring(tFn('core.wday.' .. tostring(p.wday))),
            WWWW = tostring(tFn('core.wday.' .. tostring(p.wday))),
            MM   = string.format('%02d', p.month),
            DD   = string.format('%02d', p.day),
            HH   = string.format('%02d', p.hour),
            mm   = string.format('%02d', p.min),
            ss   = string.format('%02d', p.sec),
        }
        local out = {}
        local i = 1
        local len = #pat
        while i <= len do
            local sub4 = (i + 3 <= len) and pat:sub(i, i + 3) or nil
            local sub2 = (i + 1 <= len) and pat:sub(i, i + 1) or nil
            if sub4 and tokens[sub4] then
                out[#out + 1] = tokens[sub4]
                i = i + 4
            elseif sub2 and tokens[sub2] then
                out[#out + 1] = tokens[sub2]
                i = i + 2
            else
                out[#out + 1] = pat:sub(i, i)
                i = i + 1
            end
        end
        return table.concat(out)
    end
end

local function currentTimezone()
    local raw = GetConvar('aeterna_timezone', '+00:00')
    if timeMod.parseOffset(raw) ~= nil then
        return raw
    end
    if warnedConvars.aeterna_timezone ~= raw then
        warnedConvars.aeterna_timezone = raw
        AeternaCore.log.warn('invalid aeterna_timezone; falling back to +00:00', { value = raw })
    end
    return '+00:00'
end

AeternaCore.time = {
    now = function()
        return os.time()
    end,
    parts = function(ts)
        local targetTs = ts ~= nil and ts or os.time()
        return timeMod.parts(targetTs, currentTimezone())
    end,
    format = function(ts, pattern)
        local targetTs = ts ~= nil and ts or os.time()
        return timeMod.format(targetTs, pattern, currentTimezone(), AeternaCore.t)
    end,
}

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

local validateMod = AeternaCoreLogic.validate
if not validateMod then
    local function inEnum(val, list)
        for i = 1, #list do
            if list[i] == val then return true end
        end
        return false
    end

    local function isArrayTable(t)
        local n = #t
        local count = 0
        for k in pairs(t) do
            if type(k) ~= 'number' or k < 1 or k > n or math.floor(k) ~= k then
                return false, 0
            end
            count = count + 1
        end
        return count == n, n
    end

    local function validateNode(value, schema, path)
        local p = (path and path ~= '') and path or 'value'
        if type(schema) ~= 'table' then return false, p .. ': schema', nil end
        if value == nil then
            if schema.optional == true then return true, nil, schema.default end
            return false, p .. ': type', nil
        end
        local kind = schema.type
        if kind == 'string' then
            if type(value) ~= 'string' then return false, p .. ': type', nil end
            local cleaned = textMod.clean(value, schema.maxLen)
            if schema.minLen ~= nil and textMod.len(cleaned) < schema.minLen then
                return false, p .. ': minLen ' .. tostring(schema.minLen), nil
            end
            if type(schema.enum) == 'table' and not inEnum(cleaned, schema.enum) then
                return false, p .. ': enum', nil
            end
            if type(schema.pattern) == 'string' and not cleaned:find(schema.pattern) then
                return false, p .. ': pattern', nil
            end
            return true, nil, cleaned
        elseif kind == 'number' then
            if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then
                return false, p .. ': type', nil
            end
            if schema.integer == true and math.floor(value) ~= value then
                return false, p .. ': integer', nil
            end
            if schema.min ~= nil and value < schema.min then
                return false, p .. ': min ' .. tostring(schema.min), nil
            end
            if schema.max ~= nil and value > schema.max then
                return false, p .. ': max ' .. tostring(schema.max), nil
            end
            if type(schema.enum) == 'table' and not inEnum(value, schema.enum) then
                return false, p .. ': enum', nil
            end
            return true, nil, value
        elseif kind == 'boolean' then
            if type(value) ~= 'boolean' then return false, p .. ': type', nil end
            return true, nil, value
        elseif kind == 'table' then
            if type(value) ~= 'table' then return false, p .. ': type', nil end
            local fields = schema.fields
            local allowExtra = (schema.extra == true)
            if schema.maxKeys ~= nil then
                local kc = 0
                for _ in pairs(value) do kc = kc + 1 end
                if kc > schema.maxKeys then
                    return false, p .. ': maxKeys ' .. tostring(schema.maxKeys), nil
                end
            end
            if type(fields) == 'table' and not allowExtra then
                local extras = {}
                for k in pairs(value) do
                    if fields[k] == nil then extras[#extras + 1] = tostring(k) end
                end
                if #extras > 0 then
                    table.sort(extras)
                    local extraKey = extras[1]
                    local extraPath = (path and path ~= '') and (path .. '.' .. extraKey) or extraKey
                    return false, extraPath .. ': not allowed', nil
                end
            end
            local clean = {}
            if type(fields) == 'table' then
                local keys = {}
                for k in pairs(fields) do keys[#keys + 1] = k end
                table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
                for i = 1, #keys do
                    local k = keys[i]
                    local childPath = (path and path ~= '') and (path .. '.' .. tostring(k)) or tostring(k)
                    local ok, err, cVal = validateNode(value[k], fields[k], childPath)
                    if not ok then return false, err, nil end
                    clean[k] = cVal
                end
            end
            if allowExtra or type(fields) ~= 'table' then
                for k, v in pairs(value) do
                    if type(fields) ~= 'table' or fields[k] == nil then
                        if type(v) == 'string' then clean[k] = textMod.clean(v) else clean[k] = v end
                    end
                end
            end
            return true, nil, clean
        elseif kind == 'array' then
            if type(value) ~= 'table' then return false, p .. ': type', nil end
            local isArr, n = isArrayTable(value)
            if not isArr then return false, p .. ': type', nil end
            if schema.minItems ~= nil and n < schema.minItems then
                return false, p .. ': minItems ' .. tostring(schema.minItems), nil
            end
            if schema.maxItems ~= nil and n > schema.maxItems then
                return false, p .. ': maxItems ' .. tostring(schema.maxItems), nil
            end
            local clean = {}
            for i = 1, n do
                if type(schema.items) == 'table' then
                    local itemPath = p .. '[' .. tostring(i) .. ']'
                    local ok, err, cItem = validateNode(value[i], schema.items, itemPath)
                    if not ok then return false, err, nil end
                    clean[i] = cItem
                elseif type(value[i]) == 'string' then
                    clean[i] = textMod.clean(value[i])
                else
                    clean[i] = value[i]
                end
            end
            return true, nil, clean
        end
        return false, p .. ': type', nil
    end

    validateMod = {
        validate = function(value, schema)
            return validateNode(value, schema, '')
        end,
    }
end

function AeternaCore.validate(value, schema)
    return validateMod.validate(value, schema)
end

--------------------------------------------------------------------------------
-- Rate limit (server) & ACE (server)
--------------------------------------------------------------------------------

local rlMod = AeternaCoreLogic.ratelimit
local limiter
if rlMod and rlMod.new then
    limiter = rlMod.new(function() return GetGameTimer() end)
else
    local buckets = {}
    limiter = {
        check = function(src, key, max, windowMs)
            if src == nil or key == nil or type(max) ~= 'number' or max < 1 or type(windowMs) ~= 'number' or windowMs <= 0 then
                return false
            end
            local now = GetGameTimer()
            local sKey = tostring(src)
            local aKey = tostring(key)
            buckets[sKey] = buckets[sKey] or {}
            local win = buckets[sKey][aKey]
            if not win then
                win = {}
                buckets[sKey][aKey] = win
            end
            local cutoff = now - windowMs
            local kept = 0
            local total = #win
            for i = 1, total do
                if win[i] > cutoff then
                    kept = kept + 1
                    win[kept] = win[i]
                end
            end
            for i = total, kept + 1, -1 do win[i] = nil end
            if kept >= max then return false end
            win[kept + 1] = now
            return true
        end,
        drop = function(src)
            if src ~= nil then buckets[tostring(src)] = nil end
        end,
    }
end

function AeternaCore.rateLimit(src, key, max, windowMs)
    return limiter.check(src, key, max, windowMs)
end

if IsDuplicityVersion() then
    AddEventHandler('playerDropped', function()
        if source ~= nil then
            limiter.drop(source)
        end
    end)
end

function AeternaCore.can(src, action)
    if type(action) ~= 'string' or action:sub(1, 8) ~= 'aeterna.' or #action <= 8 then
        return false
    end
    local numSrc = tonumber(src)
    if numSrc == 0 then
        return true
    end
    if numSrc == nil or numSrc < 0 then
        return false
    end
    return IsPlayerAceAllowed(src, action) == true
end

--------------------------------------------------------------------------------
-- Client KVP & Keys
--------------------------------------------------------------------------------

local kvpMod = AeternaCoreLogic.kvp
local kvpInstance
if kvpMod and kvpMod.new then
    kvpInstance = kvpMod.new({
        resource = function() return GetCurrentResourceName() end,
        getString = function(k) return GetResourceKvpString(k) end,
        setString = function(k, v) SetResourceKvp(k, v) end,
        delete = function(k) DeleteResourceKvp(k) end,
        encode = function(v) return json.encode(v) end,
        decode = function(s) return json.decode(s) end,
        warn = function(msg) AeternaCore.log.warn(msg) end,
    })
else
    local warnedKvp = {}
    local function kvpKey(name, version)
        local res = tostring(GetCurrentResourceName() or 'core')
        local pkg = res:sub(1, 8) == 'aeterna_' and res:sub(9) or res
        return 'aeterna_' .. pkg .. ':' .. tostring(name) .. ':v' .. tostring(version)
    end
    kvpInstance = {
        get = function(name, version, default)
            local key = kvpKey(name, version)
            local raw = GetResourceKvpString(key)
            if raw == nil or raw == '' then return default end
            local ok, decoded = pcall(json.decode, raw)
            if not ok or (decoded == nil and raw ~= 'null') then
                if warnedKvp[key] ~= raw then
                    warnedKvp[key] = raw
                    AeternaCore.log.warn('invalid JSON in KVP key ' .. key)
                end
                return default
            end
            return decoded
        end,
        set = function(name, version, value)
            local key = kvpKey(name, version)
            local ok, encoded = pcall(json.encode, value)
            if not ok or type(encoded) ~= 'string' or #encoded > 16384 then
                AeternaCore.log.warn('refused KVP write for ' .. key)
                return nil
            end
            SetResourceKvp(key, encoded)
            return nil
        end,
    }
    kvpInstance.migrate = function(name, from, to, fn)
        local fromKey = kvpKey(name, from)
        local toKey = kvpKey(name, to)
        local rawFrom = GetResourceKvpString(fromKey)
        local rawTo = GetResourceKvpString(toKey)
        if rawFrom ~= nil and rawFrom ~= '' and (rawTo == nil or rawTo == '') then
            local oldVal = kvpInstance.get(name, from, nil)
            if oldVal ~= nil and type(fn) == 'function' then
                kvpInstance.set(name, to, fn(oldVal))
            end
            DeleteResourceKvp(fromKey)
        end
        return nil
    end
end

AeternaCore.kvp = {
    get = function(name, version, default)
        return kvpInstance.get(name, version, default)
    end,
    set = function(name, version, value)
        return kvpInstance.set(name, version, value)
    end,
    migrate = function(name, from, to, fn)
        return kvpInstance.migrate(name, from, to, fn)
    end,
}

function AeternaCore.key(command, description)
    if type(command) ~= 'string' or command:sub(1, 9) ~= '+aeterna_' or #command <= 9 then
        AeternaCore.log.warn('refused key mapping: command must start with +aeterna_', { command = tostring(command) })
        return nil
    end
    RegisterKeyMapping(command, AeternaCore.t(description), 'keyboard', '')
    return nil
end

return AeternaCore
