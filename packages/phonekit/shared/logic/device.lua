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

function D.isAppAllowed(parsedSpecOrStr, appId, appMeta, modelId)
    if appId == 'settings' then return true end
    local m = D.MODELS[modelId]
    if m and m.calls == false and appMeta and appMeta.needs == 'voice' then return false end
    local spec = type(parsedSpecOrStr) == 'table' and parsedSpecOrStr or D.parseAppSpec(parsedSpecOrStr)
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

function D.validateGateAnswer(answer)
    if not answer or answer.allow == false then return false, (answer and answer.reason) or 'denied' end
    local list = answer.devices
    if not list and answer.id and answer.model then
        list = { { id = answer.id, model = answer.model, battery = answer.battery, fold = answer.fold, color = answer.color } }
    end
    if type(list) ~= 'table' then return false, 'phonekit.refused.nodevice' end
    local valid, seen = {}, {}
    for _, d in ipairs(list) do
        if type(d) == 'table' and type(d.id) == 'string' and #d.id > 0 and #d.id <= 64 and D.MODELS[d.model] and not seen[d.id] then
            seen[d.id] = true
            valid[#valid + 1] = d
        end
    end
    return #valid > 0 and true or false, #valid > 0 and valid or 'phonekit.refused.nodevice'
end

function D.resolveMode(configDevices)
    return configDevices == 'items' and 'items' or 'single'
end

return DeviceLogic
