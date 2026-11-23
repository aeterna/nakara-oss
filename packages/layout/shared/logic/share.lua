-- Pure logic for aeterna_layout 0.2 export / import as text: `aeterna-layout:1:` followed by JSON
-- `{ "v": 1, "places": { "<owner>/<id>": { x, y, ax, ay, scale, hidden } } }`. Natives-free; loads after layout.lua.

local L = LayoutLogic

L.EXPORT_PREFIX = 'aeterna-layout:1:'
L.EXPORT_VERSION = 1
L.MAX_TEXT_BYTES = 8192

local function defaultEncode(value)
    return json.encode(value)
end

local function defaultDecode(text)
    return json.decode(text)
end

-- Saved places (never defaults) of the registered elements in `keys`, at most maxElements of them, so the text
-- always passes import. Returns text, or nil and 'text: max 8192 bytes' when it would be too long to import.
function L.encodeExport(places, keys, config, encodeFn)
    local out = {}
    local maxEl = L.resolveMaxElements(type(config) == 'table' and config.maxElements or nil)
    local count = 0
    if type(places) == 'table' and type(keys) == 'table' then
        for _, key in ipairs(keys) do
            local p = places[key]
            if count < maxEl and L.parsePlaceKey(key) and type(p) == 'table' then
                out[key] = { x = p.x, y = p.y, ax = p.ax, ay = p.ay, scale = p.scale, hidden = p.hidden == true }
                count = count + 1
            end
        end
    end
    local encode = type(encodeFn) == 'function' and encodeFn or defaultEncode
    local text = L.EXPORT_PREFIX .. encode({ v = L.EXPORT_VERSION, places = out })
    if #text > L.MAX_TEXT_BYTES then
        return nil, 'text: max ' .. L.MAX_TEXT_BYTES .. ' bytes'
    end
    return text
end

local function keyPath(key)
    local shown = tostring(key)
    if #shown > 80 then shown = shown:sub(1, 80) end
    return 'places["' .. shown .. '"]'
end

-- Returns ok, err, places, kind. err is the first error path ('places["a/b"].scale: out of range'); kind is
-- 'version' for an unsupported `v` and 'invalid' for everything else. A text with any error is refused whole.
function L.decodeImport(text, config, decodeFn)
    local function fail(err, kind)
        return false, err, nil, kind or 'invalid'
    end
    if type(text) ~= 'string' then return fail('text: type') end
    if #text > L.MAX_TEXT_BYTES then return fail('text: max ' .. L.MAX_TEXT_BYTES .. ' bytes') end
    if text:sub(1, #L.EXPORT_PREFIX) ~= L.EXPORT_PREFIX then return fail('text: prefix') end

    local decode = type(decodeFn) == 'function' and decodeFn or defaultDecode
    local ok, body = pcall(decode, text:sub(#L.EXPORT_PREFIX + 1))
    if not ok or type(body) ~= 'table' then return fail('text: json') end

    local extras = {}
    for k in pairs(body) do
        if k ~= 'v' and k ~= 'places' then extras[#extras + 1] = tostring(k) end
    end
    if #extras > 0 then
        table.sort(extras)
        return fail(extras[1] .. ': not allowed')
    end
    if body.v ~= L.EXPORT_VERSION then return fail('v: version', 'version') end
    if type(body.places) ~= 'table' then return fail('places: type') end

    local keys = {}
    for key in pairs(body.places) do keys[#keys + 1] = key end
    local maxEl = L.resolveMaxElements(type(config) == 'table' and config.maxElements or nil)
    if #keys > maxEl then return fail('places: max ' .. maxEl) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

    local scaleCfg = L.resolveScaleConfig(type(config) == 'table' and config.scale or nil)
    local places = {}
    for _, key in ipairs(keys) do
        if not L.parsePlaceKey(key) then return fail(keyPath(key) .. ': key') end
        local okPlace, field, rule, clean = L.checkPlace(body.places[key], scaleCfg, { hidden = true })
        if not okPlace then
            return fail(keyPath(key) .. (field and ('.' .. field) or '') .. ': ' .. rule)
        end
        places[key] = clean
    end
    return true, nil, places, nil
end

-- NUI callback `import {text}`: the size is checked before any parsing.
function L.validateImportCallback(payload)
    if type(payload) ~= 'table' then return false, 'payload: type', nil end
    for k in pairs(payload) do
        if k ~= 'text' then return false, tostring(k) .. ': not allowed', nil end
    end
    if type(payload.text) ~= 'string' then return false, 'text: type', nil end
    if #payload.text > L.MAX_TEXT_BYTES then return false, 'text: max ' .. L.MAX_TEXT_BYTES .. ' bytes', nil end
    return true, nil, { text = payload.text }
end

return L
