-- device.lua -- Pure logic for aeterna_phonekit models, frames, apps and device modes.
-- Natives-free so stock Lua 5.1+ can test it.

DeviceLogic = {}
local D = DeviceLogic

D.MODELS = {
    keypad = { name = 'Keypad', w = 300, h = 660, folds = false, calls = true, batteryMultiplier = 4, rank = 1, tiles = 12 },
    burner = { name = 'Burner', w = 300, h = 660, folds = false, calls = true, batteryMultiplier = 3, rank = 0, tiles = 12, defaultApps = '*,-contacts' },
    qwerty = { name = 'Qwerty', w = 392, h = 760, folds = false, calls = true, batteryMultiplier = 2, rank = 2, tiles = 8 },
    slab = { name = 'Slab', w = 392, h = 812, folds = false, calls = true, batteryMultiplier = 1, rank = 4, tiles = 12 },
    fold = { name = 'Fold', w = 380, h = 842, closedW = 380, closedH = 430, folds = true, defaultFold = 'open', calls = true, batteryMultiplier = 1, rank = 5, tiles = 12 },
    pro = { name = 'Pro', w = 392, h = 812, folds = false, calls = true, batteryMultiplier = 1.2, rank = 6, tiles = 12 },
    book = { name = 'Book', w = 780, h = 700, closedW = 380, closedH = 812, folds = true, defaultFold = 'closed', calls = true, batteryMultiplier = 1, rank = 7, tiles = 12, openTiles = 24 },
    pad = { name = 'Pad', w = 600, h = 812, folds = false, calls = false, batteryMultiplier = 1.5, rank = 3, tiles = 20 },
}

function D.getFrameSize(modelId, foldState)
    local m = D.MODELS[modelId] or D.MODELS.slab
    if m.folds and foldState == 'closed' then return m.closedW or m.w, m.closedH or m.h end
    return m.w, m.h
end

function D.validateFold(modelId, foldState)
    local m = D.MODELS[modelId]
    if not m or not m.folds then return nil end
    return (foldState == 'open' or foldState == 'closed') and foldState or (m.defaultFold or 'open')
end

function D.toggleFold(modelId, currentFold)
    local m = D.MODELS[modelId]
    if not m or not m.folds then return currentFold end
    return D.validateFold(modelId, currentFold) == 'open' and 'closed' or 'open'
end

function D.getTilesPerPage(modelId, foldState)
    local m = D.MODELS[modelId] or D.MODELS.slab
    return (modelId == 'book' and foldState == 'open') and (m.openTiles or 24) or (m.tiles or 12)
end

function D.supportsTwoPanes(modelId, foldState)
    return modelId == 'book' and foldState == 'open'
end

function D.calcFit(w, h, vw, vh)
    return math.max(0, math.min(1, (vh - 0.048 * vh) / h, (vw - 0.048 * vh) / w))
end

function D.parseAppSpec(specStr)
    local spec = { wildcard = false, included = {}, excluded = {} }
    for token in string.gmatch(type(specStr) == 'string' and specStr or '*', '[^,%s]+') do
        if token == '*' then spec.wildcard = true
        elseif token:sub(1, 1) == '-' then spec.excluded[token:sub(2)] = true
        else spec.included[token] = true end
    end
    return spec
end

-- A nil spec means "no config spec": the model's shipped default applies (burner '*,-contacts', else '*').
function D.isAppAllowed(parsedSpecOrStr, appId, appMeta, modelId)
    if appId == 'settings' then return true end
    local m = D.MODELS[modelId]
    if m and m.calls == false and appMeta and appMeta.needs == 'voice' then return false end
    local specIn = parsedSpecOrStr
    if specIn == nil then specIn = (m and m.defaultApps) or '*' end
    local spec = type(specIn) == 'table' and specIn or D.parseAppSpec(specIn)
    if spec.excluded[appId] then return false end
    if spec.included[appId] then return true end
    return spec.wildcard == true
end

function D.pickActiveDevice(devices, lastChosenId)
    if type(devices) ~= 'table' or #devices == 0 then return nil end
    if lastChosenId then
        for _, d in ipairs(devices) do
            if d.id == lastChosenId then return d end
        end
    end
    local best
    for _, d in ipairs(devices) do
        local rank = (D.MODELS[d.model] and D.MODELS[d.model].rank) or -1
        if not best then
            best = d
        else
            local bRank = (D.MODELS[best.model] and D.MODELS[best.model].rank) or -1
            if rank > bRank or (rank == bRank and tostring(d.id) < tostring(best.id)) then best = d end
        end
    end
    return best
end

D.MAX_DEVICES = 8

local function cleanDevice(d)
    if type(d) ~= 'table' or type(d.id) ~= 'string' or #d.id < 1 or #d.id > 64 or not D.MODELS[d.model] then
        return nil
    end
    local battery = tonumber(d.battery)
    if battery and (battery ~= battery or battery < 0 or battery > 100) then battery = nil end
    local fold = (d.fold == 'open' or d.fold == 'closed') and d.fold or nil
    local color = tonumber(d.color)
    if color and (color < 0 or color ~= math.floor(color)) then color = nil end
    return { id = d.id, model = d.model, battery = battery, fold = fold, color = color }
end

-- Returns true, devices (1-8 cleaned entries) or false, reasonKey.
function D.validateGateAnswer(answer)
    if type(answer) ~= 'table' then return false, 'phonekit.refused.default' end
    if answer.allow == false then
        local reason = (type(answer.reason) == 'string' and answer.reason ~= '') and answer.reason or 'phonekit.refused.default'
        return false, reason
    end
    local list = answer.devices
    if list == nil and answer.id ~= nil then
        list = { { id = answer.id, model = answer.model, battery = answer.battery, fold = answer.fold, color = answer.color } }
    end
    if type(list) ~= 'table' then return false, 'phonekit.refused.nodevice' end
    local valid, seen = {}, {}
    for _, d in ipairs(list) do
        local c = cleanDevice(d)
        if c and not seen[c.id] then
            seen[c.id] = true
            valid[#valid + 1] = c
            if #valid >= D.MAX_DEVICES then break end
        end
    end
    if #valid == 0 then return false, 'phonekit.refused.nodevice' end
    return true, valid
end

function D.resolveMode(configDevices)
    return configDevices == 'items' and 'items' or 'single'
end

D.UNIVERSE_NAMES = {
    keypad = 'Whiz Keypad', burner = 'Badger Burner', qwerty = 'Badger Qwerty', slab = 'Facade Slab',
    fold = 'Facade Fold', pro = 'iFruit Pro', book = 'iFruit Book', pad = 'iFruit Pad',
}

D.COLORS = {
    keypad = { '#33363B', '#3A5F8F', '#D9762B' },
    burner = { '#18191B', '#4B5240' },
    qwerty = { '#2B2D30', '#B8BCC2' },
    slab = { '#3D4046', '#C9CCD1', '#CDBB9A', '#5C7FA8' },
    fold = { '#36383D', '#D4C3A3', '#6F8F7A' },
    pro = { '#45474B', '#BDBFC2', '#3F536E', '#B9A584' },
    book = { '#404247', '#CED0D3' },
    pad = { '#C4C7CB', '#4E5056', '#6C8DB3' },
}

local function cleanColors(list)
    if type(list) ~= 'table' then return nil end
    local out = {}
    for _, c in ipairs(list) do
        if type(c) == 'string' and c:match('^#%x%x%x%x%x%x$') then out[#out + 1] = c end
    end
    return #out > 0 and out or nil
end

local function plainLabel(s)
    if type(s) ~= 'string' then return nil end
    local clean = s:gsub('[%c]', ''):match('^%s*(.-)%s*$')
    if clean == '' then return nil end
    local ok, n = pcall(utf8.len, clean)
    if not ok or not n or n > 24 then return nil end
    return clean
end

-- Per-model settings: `Config.models[m]` keys win, missing keys take the shipped default.
-- opts = { names = 'neutral' | 'universe', t = translate fn, prop = Config.prop }
function D.resolveModel(modelId, cfgModels, opts)
    local id = D.MODELS[modelId] and modelId or 'slab'
    local m = D.MODELS[id]
    local o = type(opts) == 'table' and opts or {}
    local cfg = type(cfgModels) == 'table' and type(cfgModels[id]) == 'table' and cfgModels[id] or {}
    local label = plainLabel(cfg.label)
    if not label then
        if o.names == 'universe' then
            label = D.UNIVERSE_NAMES[id]
        elseif type(o.t) == 'function' then
            label = o.t('phonekit.model.' .. id)
        else
            label = m.name
        end
    end
    local apps = type(cfg.apps) == 'string' and cfg.apps or (m.defaultApps or '*')
    local prop = (type(cfg.prop) == 'string' and cfg.prop ~= '') and cfg.prop
        or ((type(o.prop) == 'string' and o.prop ~= '') and o.prop or 'prop_npc_phone_02')
    return { id = id, label = label, apps = apps, colors = cleanColors(cfg.colors) or D.COLORS[id], prop = prop,
        voice = m.calls ~= false }
end

-- Hex colour for a 0-based index into the model's colours (gate answers send 0 for the first);
-- missing or out of range = the first colour.
function D.colorAt(modelId, cfgModels, index)
    local colors = D.resolveModel(modelId, cfgModels, {}).colors
    local i = tonumber(index)
    return (i and colors[i + 1]) or colors[1]
end

-- Server resource KVP owner part: `cid:<character id>` when known, else `lic:<license>`.
function D.whoKey(cid, license)
    if type(cid) == 'string' and cid ~= '' then return 'cid:' .. cid end
    if type(license) == 'string' and license ~= '' then return 'lic:' .. license end
    return nil
end

return DeviceLogic
