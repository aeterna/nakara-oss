-- Pure logic for aeterna_uikit: spec validation, action/value filtering, patch validation,
-- menu registry and client prompt validation. Natives-free so stock Lua 5.1+ can test it.

UikitLogic = {}
local L = UikitLogic

local ICON_NAMES = {
    'home', 'bell', 'box', 'user', 'users', 'phone',
    'message-circle', 'calculator', 'file-text', 'settings', 'sliders',
    'map', 'map-pin', 'car', 'wrench', 'shield', 'heart', 'droplet',
    'utensils', 'clock', 'calendar', 'info', 'alert-triangle', 'check',
    'x', 'plus', 'minus', 'search', 'lock', 'unlock', 'key', 'star',
    'flag', 'trash', 'log-out', 'log-in', 'chevron-right', 'chevron-left',
    'arrow-up', 'arrow-down',
}

L.ICONS = {}
for i = 1, #ICON_NAMES do
    L.ICONS[ICON_NAMES[i]] = true
end

L.SIZES = { sm = true, md = true, lg = true }
L.BLOCK_TYPES = {
    text = true,
    list = true,
    field = true,
    toggle = true,
    select = true,
    progress = true,
    divider = true,
    buttons = true,
}
L.VARIANTS = { primary = true, secondary = true, danger = true }
L.DIFFICULTIES = { easy = true, medium = true, hard = true }
L.PATCH_KEYS = { label = true, value = true, items = true, disabled = true }

local BASE36_CHARS = '0123456789abcdefghijklmnopqrstuvwxyz'

function L.isValidIcon(name)
    return type(name) == 'string' and L.ICONS[name] == true
end

function L.isValidId(id, maxLen)
    local limit = maxLen or 32
    if type(id) ~= 'string' then return false end
    if #id < 1 or #id > limit then return false end
    return id:match('^[%w_%-]+$') ~= nil
end

function L.formatPanelId(counter)
    local n = math.floor(tonumber(counter) or 1)
    if n < 1 then n = 1 end
    local digits = {}
    while n > 0 do
        local rem = n % 36
        digits[#digits + 1] = BASE36_CHARS:sub(rem + 1, rem + 1)
        n = math.floor(n / 36)
    end
    local rev = {}
    for i = #digits, 1, -1 do
        rev[#rev + 1] = digits[i]
    end
    local id = 'p' .. table.concat(rev)
    if #id > 24 then
        id = id:sub(1, 24)
    end
    return id
end

-- UTF-8 helpers (portable across Lua 5.1 - 5.4; Thai combining marks count as 0 visible chars)
local function isThaiCombining(b1, b2, b3)
    if b1 ~= 224 then return false end
    if b2 == 184 then
        return b3 == 177 or (b3 >= 180 and b3 <= 186)
    elseif b2 == 185 then
        return b3 >= 135 and b3 <= 142
    end
    return false
end

local function isControlSeq(b1, b2, b3)
    if b1 < 32 or b1 == 127 then return true, 1 end
    if b1 == 226 and b2 == 128 and b3 then
        if (b3 >= 139 and b3 <= 143) or (b3 >= 170 and b3 <= 174) then
            return true, 3
        end
    end
    return false, 0
end

local function utf8SeqLen(b1)
    if not b1 then return 0 end
    if b1 < 128 then return 1 end
    if b1 >= 194 and b1 <= 223 then return 2 end
    if b1 >= 224 and b1 <= 239 then return 3 end
    if b1 >= 240 and b1 <= 244 then return 4 end
    return 1
end

function L.stripControlAndTrim(s)
    if type(s) ~= 'string' then return '' end
    local out = {}
    local i = 1
    local len = #s
    while i <= len do
        local b1 = s:byte(i)
        local b2 = s:byte(i + 1)
        local b3 = s:byte(i + 2)
        local isCtrl, ctrlLen = isControlSeq(b1, b2, b3)
        if isCtrl then
            i = i + ctrlLen
        else
            local seqLen = utf8SeqLen(b1)
            if i + seqLen - 1 > len then
                break
            end
            out[#out + 1] = s:sub(i, i + seqLen - 1)
            i = i + seqLen
        end
    end
    local joined = table.concat(out)
    return joined:match('^%s*(.-)%s*$') or ''
end

function L.textLen(s)
    if AeternaCore and AeternaCore.text and type(AeternaCore.text.len) == 'function' then
        return AeternaCore.text.len(s)
    end
    if type(s) ~= 'string' then return 0 end
    local count = 0
    local i = 1
    local len = #s
    while i <= len do
        local b1 = s:byte(i)
        local seqLen = utf8SeqLen(b1)
        if i + seqLen - 1 > len then break end
        if seqLen == 3 then
            local b2, b3 = s:byte(i + 1), s:byte(i + 2)
            if not isThaiCombining(b1, b2, b3) then
                count = count + 1
            end
        else
            count = count + 1
        end
        i = i + seqLen
    end
    return count
end

function L.textCut(s, maxVisible)
    if AeternaCore and AeternaCore.text and type(AeternaCore.text.cut) == 'function' then
        return AeternaCore.text.cut(s, maxVisible)
    end
    if type(s) ~= 'string' then return '' end
    if maxVisible <= 0 then return '' end
    local visible = 0
    local i = 1
    local len = #s
    local lastEnd = 0
    while i <= len do
        local b1 = s:byte(i)
        local seqLen = utf8SeqLen(b1)
        if i + seqLen - 1 > len then break end
        local combining = false
        if seqLen == 3 then
            local b2, b3 = s:byte(i + 1), s:byte(i + 2)
            combining = isThaiCombining(b1, b2, b3)
        end
        if combining then
            if visible == 0 then
                i = i + seqLen
            else
                lastEnd = i + seqLen - 1
                i = i + seqLen
            end
        else
            if visible >= maxVisible then
                break
            end
            visible = visible + 1
            lastEnd = i + seqLen - 1
            i = i + seqLen
        end
    end
    if lastEnd == 0 then return '' end
    return s:sub(1, lastEnd)
end

function L.textClean(s, maxLen)
    if AeternaCore and AeternaCore.text and type(AeternaCore.text.clean) == 'function' then
        return AeternaCore.text.clean(s, maxLen)
    end
    local stripped = L.stripControlAndTrim(s)
    if maxLen then
        return L.textCut(stripped, maxLen)
    end
    return stripped
end

local function checkCleanString(val, minLen, maxLen, path)
    if type(val) ~= 'string' then
        return false, path .. ': type'
    end
    local stripped = L.stripControlAndTrim(val)
    local vlen = L.textLen(stripped)
    if minLen and vlen < minLen then
        return false, path .. ': minLen ' .. tostring(minLen)
    end
    if maxLen and vlen > maxLen then
        return false, path .. ': maxLen ' .. tostring(maxLen)
    end
    return true, nil, L.textClean(val, maxLen)
end

local function isArrayTable(t)
    if type(t) ~= 'table' then return false end
    local count = 0
    for k in pairs(t) do
        if type(k) ~= 'number' or k < 1 or k ~= math.floor(k) then
            return false
        end
        count = count + 1
    end
    return count == #t
end

local function checkUniqueId(id, seenIds, path)
    if not L.isValidId(id, 32) then
        return false, path .. ': pattern'
    end
    if seenIds[id] then
        return false, path .. ': duplicate'
    end
    seenIds[id] = true
    return true
end

local function validateListItems(items, path, seenIds)
    if not isArrayTable(items) then
        return false, path .. ': type'
    end
    if #items > 50 then
        return false, path .. ': maxItems 50'
    end
    local cleanItems = {}
    for j = 1, #items do
        local item = items[j]
        local ipath = ('%s[%d]'):format(path, j)
        if type(item) ~= 'table' then
            return false, ipath .. ': type'
        end
        local okId, errId = checkUniqueId(item.id, seenIds, ipath .. '.id')
        if not okId then return false, errId end

        local okLbl, errLbl, cleanLbl = checkCleanString(item.label, 1, 60, ipath .. '.label')
        if not okLbl then return false, errLbl end

        local cleanMeta
        if item.meta ~= nil then
            local okMeta, errMeta, cm = checkCleanString(item.meta, 0, 30, ipath .. '.meta')
            if not okMeta then return false, errMeta end
            cleanMeta = cm
        end

        local cleanIcon
        if item.icon ~= nil and item.icon ~= '' then
            if not L.isValidIcon(item.icon) then
                return false, ipath .. '.icon: unknown icon'
            end
            cleanIcon = item.icon
        end

        if item.disabled ~= nil and type(item.disabled) ~= 'boolean' then
            return false, ipath .. '.disabled: type'
        end

        cleanItems[j] = {
            id = item.id,
            label = cleanLbl,
            meta = cleanMeta,
            icon = cleanIcon,
            disabled = item.disabled == true,
        }
    end
    return true, nil, cleanItems
end

local function validateButtonItems(items, path, seenIds)
    if not isArrayTable(items) then
        return false, path .. ': type'
    end
    if #items < 1 then
        return false, path .. ': minItems 1'
    end
    if #items > 4 then
        return false, path .. ': maxItems 4'
    end
    local cleanItems = {}
    for j = 1, #items do
        local btn = items[j]
        local bpath = ('%s[%d]'):format(path, j)
        if type(btn) ~= 'table' then
            return false, bpath .. ': type'
        end
        local okId, errId = checkUniqueId(btn.id, seenIds, bpath .. '.id')
        if not okId then return false, errId end

        local okLbl, errLbl, cleanLbl = checkCleanString(btn.label, 1, 24, bpath .. '.label')
        if not okLbl then return false, errLbl end

        local variant = btn.variant or 'secondary'
        if type(variant) ~= 'string' or not L.VARIANTS[variant] then
            return false, bpath .. '.variant: enum'
        end

        local cleanIcon
        if btn.icon ~= nil and btn.icon ~= '' then
            if not L.isValidIcon(btn.icon) then
                return false, bpath .. '.icon: unknown icon'
            end
            cleanIcon = btn.icon
        end

        if btn.disabled ~= nil and type(btn.disabled) ~= 'boolean' then
            return false, bpath .. '.disabled: type'
        end

        cleanItems[j] = {
            id = btn.id,
            label = cleanLbl,
            variant = variant,
            icon = cleanIcon,
            disabled = btn.disabled == true,
        }
    end
    return true, nil, cleanItems
end

local function validateFieldBlock(b, bpath)
    local okLbl, errLbl, cleanLbl = checkCleanString(b.label, 1, 40, bpath .. '.label')
    if not okLbl then return false, errLbl end

    local inputKind = b.input or 'text'
    if inputKind ~= 'text' and inputKind ~= 'number' then
        return false, bpath .. '.input: enum'
    end

    local minVal = b.min
    local maxVal = b.max
    if minVal ~= nil and (type(minVal) ~= 'number' or minVal ~= minVal) then
        return false, bpath .. '.min: type'
    end
    if maxVal ~= nil and (type(maxVal) ~= 'number' or maxVal ~= maxVal) then
        return false, bpath .. '.max: type'
    end
    if minVal ~= nil and maxVal ~= nil and minVal > maxVal then
        return false, bpath .. '.min: max'
    end

    local maxLen = b.maxLen or 60
    if type(maxLen) ~= 'number' or maxLen ~= math.floor(maxLen) or maxLen < 1 or maxLen > 400 then
        return false, bpath .. '.maxLen: range'
    end

    local cleanPlaceholder
    if b.placeholder ~= nil then
        local okPh, errPh, cph = checkCleanString(b.placeholder, 0, 60, bpath .. '.placeholder')
        if not okPh then return false, errPh end
        cleanPlaceholder = cph
    end

    local cleanVal = b.value
    if inputKind == 'number' then
        if cleanVal ~= nil and cleanVal ~= '' then
            if type(cleanVal) ~= 'number' or cleanVal ~= cleanVal then
                return false, bpath .. '.value: type'
            end
            if minVal ~= nil and cleanVal < minVal then
                return false, bpath .. '.value: min ' .. tostring(minVal)
            end
            if maxVal ~= nil and cleanVal > maxVal then
                return false, bpath .. '.value: max ' .. tostring(maxVal)
            end
        end
    else
        if cleanVal == nil then
            cleanVal = ''
        else
            local okVal, errVal, cv = checkCleanString(cleanVal, 0, maxLen, bpath .. '.value')
            if not okVal then return false, errVal end
            cleanVal = cv
        end
    end

    if b.disabled ~= nil and type(b.disabled) ~= 'boolean' then
        return false, bpath .. '.disabled: type'
    end

    return true, nil, {
        id = b.id,
        type = 'field',
        label = cleanLbl,
        input = inputKind,
        value = cleanVal,
        min = minVal,
        max = maxVal,
        maxLen = maxLen,
        placeholder = cleanPlaceholder,
        disabled = b.disabled == true,
    }
end

function L.validateSpec(spec)
    if type(spec) ~= 'table' then
        return false, 'spec: type'
    end

    local okTitle, errTitle, cleanTitle = checkCleanString(spec.title, 1, 60, 'title')
    if not okTitle then return false, errTitle end

    local cleanSubtitle
    if spec.subtitle ~= nil then
        local okSub, errSub, cs = checkCleanString(spec.subtitle, 0, 120, 'subtitle')
        if not okSub then return false, errSub end
        cleanSubtitle = cs
    end

    local size = spec.size or 'md'
    if type(size) ~= 'string' or not L.SIZES[size] then
        return false, 'size: enum'
    end

    if not isArrayTable(spec.blocks) then
        return false, 'blocks: type'
    end
    if #spec.blocks > 40 then
        return false, 'blocks: maxItems 40'
    end

    local seenIds = {}
    local cleanBlocks = {}

    for i = 1, #spec.blocks do
        local b = spec.blocks[i]
        local bpath = ('blocks[%d]'):format(i)
        if type(b) ~= 'table' then
            return false, bpath .. ': type'
        end

        local okId, errId = checkUniqueId(b.id, seenIds, bpath .. '.id')
        if not okId then return false, errId end

        local btype = b.type
        if type(btype) ~= 'string' or not L.BLOCK_TYPES[btype] then
            return false, bpath .. '.type: unknown type'
        end

        if btype == 'text' then
            local okLbl, errLbl, cleanLbl = checkCleanString(b.label, 1, 400, bpath .. '.label')
            if not okLbl then return false, errLbl end
            cleanBlocks[i] = { id = b.id, type = 'text', label = cleanLbl }

        elseif btype == 'list' then
            local cleanLbl
            if b.label ~= nil then
                local okLbl, errLbl, cl = checkCleanString(b.label, 0, 40, bpath .. '.label')
                if not okLbl then return false, errLbl end
                cleanLbl = cl
            end
            local okItems, errItems, cleanItems = validateListItems(b.items, bpath .. '.items', seenIds)
            if not okItems then return false, errItems end
            cleanBlocks[i] = { id = b.id, type = 'list', label = cleanLbl, items = cleanItems }

        elseif btype == 'field' then
            local okField, errField, cleanField = validateFieldBlock(b, bpath)
            if not okField then return false, errField end
            cleanBlocks[i] = cleanField

        elseif btype == 'toggle' then
            local okLbl, errLbl, cleanLbl = checkCleanString(b.label, 1, 40, bpath .. '.label')
            if not okLbl then return false, errLbl end
            if b.value ~= nil and type(b.value) ~= 'boolean' then
                return false, bpath .. '.value: type'
            end
            if b.disabled ~= nil and type(b.disabled) ~= 'boolean' then
                return false, bpath .. '.disabled: type'
            end
            cleanBlocks[i] = {
                id = b.id,
                type = 'toggle',
                label = cleanLbl,
                value = b.value == true,
                disabled = b.disabled == true,
            }

        elseif btype == 'select' then
            local okLbl, errLbl, cleanLbl = checkCleanString(b.label, 1, 40, bpath .. '.label')
            if not okLbl then return false, errLbl end
            if not isArrayTable(b.options) or #b.options < 1 or #b.options > 50 then
                return false, bpath .. '.options: range'
            end
            local cleanOpts = {}
            local optSet = {}
            for j = 1, #b.options do
                local opt = b.options[j]
                local opath = ('%s.options[%d]'):format(bpath, j)
                if type(opt) ~= 'table' then
                    return false, opath .. ': type'
                end
                local okOptId, errOptId = checkUniqueId(opt.id, seenIds, opath .. '.id')
                if not okOptId then return false, errOptId end
                local okOptLbl, errOptLbl, cleanOptLbl = checkCleanString(opt.label, 1, 40, opath .. '.label')
                if not okOptLbl then return false, errOptLbl end
                optSet[opt.id] = true
                cleanOpts[j] = { id = opt.id, label = cleanOptLbl }
            end
            local selVal = b.value
            if selVal == nil then
                selVal = cleanOpts[1].id
            elseif type(selVal) ~= 'string' or not optSet[selVal] then
                return false, bpath .. '.value: option'
            end
            if b.disabled ~= nil and type(b.disabled) ~= 'boolean' then
                return false, bpath .. '.disabled: type'
            end
            cleanBlocks[i] = {
                id = b.id,
                type = 'select',
                label = cleanLbl,
                options = cleanOpts,
                value = selVal,
                disabled = b.disabled == true,
            }

        elseif btype == 'progress' then
            local okLbl, errLbl, cleanLbl = checkCleanString(b.label, 1, 40, bpath .. '.label')
            if not okLbl then return false, errLbl end
            if type(b.value) ~= 'number' or b.value ~= b.value or b.value < 0 or b.value > 1 then
                return false, bpath .. '.value: range'
            end
            cleanBlocks[i] = {
                id = b.id,
                type = 'progress',
                label = cleanLbl,
                value = b.value,
            }

        elseif btype == 'divider' then
            cleanBlocks[i] = { id = b.id, type = 'divider' }

        elseif btype == 'buttons' then
            local okBtns, errBtns, cleanBtns = validateButtonItems(b.items, bpath .. '.items', seenIds)
            if not okBtns then return false, errBtns end
            cleanBlocks[i] = { id = b.id, type = 'buttons', items = cleanBtns }
        end
    end

    return true, nil, {
        title = cleanTitle,
        subtitle = cleanSubtitle,
        size = size,
        blocks = cleanBlocks,
    }
end

function L.validateValues(spec, values)
    if type(spec) ~= 'table' or type(spec.blocks) ~= 'table' then
        return false, 'spec: invalid'
    end
    if values == nil then
        return true, nil, {}
    end
    if type(values) ~= 'table' then
        return false, 'values: type'
    end

    local valueBlocks = {}
    for i = 1, #spec.blocks do
        local b = spec.blocks[i]
        if b and (b.type == 'field' or b.type == 'toggle' or b.type == 'select') then
            valueBlocks[b.id] = b
        end
    end

    local keyCount = 0
    local cleanValues = {}
    for k, v in pairs(values) do
        keyCount = keyCount + 1
        if keyCount > 40 then
            return false, 'values: maxKeys 40'
        end
        if type(k) ~= 'string' then
            return false, 'values: key type'
        end
        local b = valueBlocks[k]
        if not b then
            return false, ('values.%s: extra key not allowed'):format(k)
        end

        if b.type == 'field' then
            if b.input == 'number' then
                if type(v) ~= 'number' or v ~= v then
                    return false, ('values.%s: type'):format(k)
                end
                if b.min ~= nil and v < b.min then
                    return false, ('values.%s: min %s'):format(k, tostring(b.min))
                end
                if b.max ~= nil and v > b.max then
                    return false, ('values.%s: max %s'):format(k, tostring(b.max))
                end
                cleanValues[k] = v
            else
                local maxLen = b.maxLen or 60
                local okStr, errStr, cleanStr = checkCleanString(v, 0, maxLen, 'values.' .. k)
                if not okStr then
                    return false, errStr
                end
                cleanValues[k] = cleanStr
            end

        elseif b.type == 'toggle' then
            if type(v) ~= 'boolean' then
                return false, ('values.%s: type'):format(k)
            end
            cleanValues[k] = v

        elseif b.type == 'select' then
            if type(v) ~= 'string' then
                return false, ('values.%s: type'):format(k)
            end
            local found = false
            if type(b.options) == 'table' then
                for j = 1, #b.options do
                    if b.options[j].id == v then
                        found = true
                        break
                    end
                end
            end
            if not found then
                return false, ('values.%s: option not in list'):format(k)
            end
            cleanValues[k] = v
        end
    end

    return true, nil, cleanValues
end

local function isActionInSpec(spec, action)
    if action == '__close' then return true end
    if not L.isValidId(action, 32) then return false end
    for i = 1, #spec.blocks do
        local b = spec.blocks[i]
        if b and (b.type == 'list' or b.type == 'buttons') and type(b.items) == 'table' then
            for j = 1, #b.items do
                local item = b.items[j]
                if item and item.id == action then
                    return item.disabled ~= true
                end
            end
        end
    end
    return false
end

function L.validateAction(openPanel, payload)
    if type(openPanel) ~= 'table' or type(openPanel.spec) ~= 'table' then
        return false, 'panel: closed'
    end
    if type(payload) ~= 'table' then
        return false, 'payload: type'
    end
    if type(payload.panelId) ~= 'string' or #payload.panelId > 24 or payload.panelId ~= openPanel.panelId then
        return false, 'panelId: mismatch'
    end
    local action = payload.action
    if type(action) ~= 'string' or #action < 1 or #action > 32 then
        return false, 'action: invalid'
    end
    if not isActionInSpec(openPanel.spec, action) then
        return false, 'action: not in spec'
    end

    local okVal, errVal, cleanValues = L.validateValues(openPanel.spec, payload.values)
    if not okVal then
        return false, errVal
    end

    return true, nil, {
        owner = openPanel.owner,
        panelId = openPanel.panelId,
        action = action,
        values = cleanValues,
    }
end

function L.validatePatch(spec, patch)
    if type(spec) ~= 'table' or type(spec.blocks) ~= 'table' then
        return false, 'spec: invalid'
    end
    if type(patch) ~= 'table' or type(patch.blocks) ~= 'table' then
        return false, 'patch: type'
    end
    for k in pairs(patch) do
        if k ~= 'blocks' then
            return false, ('patch.%s: extra key'):format(tostring(k))
        end
    end

    local blockMap = {}
    local seenIds = {}
    for i = 1, #spec.blocks do
        local b = spec.blocks[i]
        blockMap[b.id] = b
        seenIds[b.id] = true
        local pb = patch.blocks[b.id]
        local replacingItems = (b.type == 'list' or b.type == 'buttons') and type(pb) == 'table' and pb.items ~= nil
        if not replacingItems and type(b.items) == 'table' then
            for j = 1, #b.items do
                if b.items[j] and b.items[j].id then
                    seenIds[b.items[j].id] = true
                end
            end
        end
        if type(b.options) == 'table' then
            for j = 1, #b.options do
                if b.options[j] and b.options[j].id then
                    seenIds[b.options[j].id] = true
                end
            end
        end
    end

    local hasAny = false
    local cleanBlocksPatch = {}

    for blockId, partial in pairs(patch.blocks) do
        hasAny = true
        if type(blockId) ~= 'string' or not blockMap[blockId] then
            return false, ('blocks.%s: unknown block'):format(tostring(blockId))
        end
        if type(partial) ~= 'table' then
            return false, ('blocks.%s: type'):format(blockId)
        end

        local target = blockMap[blockId]
        local btype = target.type
        local cleanPartial = {}

        for k in pairs(partial) do
            if not L.PATCH_KEYS[k] then
                return false, ('blocks.%s.%s: field not allowed'):format(blockId, tostring(k))
            end
        end

        if partial.disabled ~= nil then
            if type(partial.disabled) ~= 'boolean' then
                return false, ('blocks.%s.disabled: type'):format(blockId)
            end
            cleanPartial.disabled = partial.disabled
        end

        if partial.label ~= nil then
            if btype == 'divider' or btype == 'buttons' then
                return false, ('blocks.%s.label: not supported'):format(blockId)
            end
            local maxLbl = btype == 'text' and 400 or 40
            local minLbl = btype == 'list' and 0 or 1
            local okLbl, errLbl, cl = checkCleanString(partial.label, minLbl, maxLbl, ('blocks.%s.label'):format(blockId))
            if not okLbl then return false, errLbl end
            cleanPartial.label = cl
        end

        if partial.items ~= nil then
            if btype == 'list' then
                local okIt, errIt, ci = validateListItems(partial.items, ('blocks.%s.items'):format(blockId), seenIds)
                if not okIt then return false, errIt end
                cleanPartial.items = ci
            elseif btype == 'buttons' then
                local okBt, errBt, cb = validateButtonItems(partial.items, ('blocks.%s.items'):format(blockId), seenIds)
                if not okBt then return false, errBt end
                cleanPartial.items = cb
            else
                return false, ('blocks.%s.items: not supported'):format(blockId)
            end
        end

        if partial.value ~= nil then
            if btype == 'field' then
                if target.input == 'number' then
                    if type(partial.value) ~= 'number' or partial.value ~= partial.value then
                        return false, ('blocks.%s.value: type'):format(blockId)
                    end
                    if target.min ~= nil and partial.value < target.min then
                        return false, ('blocks.%s.value: min'):format(blockId)
                    end
                    if target.max ~= nil and partial.value > target.max then
                        return false, ('blocks.%s.value: max'):format(blockId)
                    end
                    cleanPartial.value = partial.value
                else
                    local okVal, errVal, cv = checkCleanString(partial.value, 0, target.maxLen or 60, ('blocks.%s.value'):format(blockId))
                    if not okVal then return false, errVal end
                    cleanPartial.value = cv
                end
            elseif btype == 'toggle' then
                if type(partial.value) ~= 'boolean' then
                    return false, ('blocks.%s.value: type'):format(blockId)
                end
                cleanPartial.value = partial.value
            elseif btype == 'select' then
                if type(partial.value) ~= 'string' then
                    return false, ('blocks.%s.value: type'):format(blockId)
                end
                local found = false
                for j = 1, #target.options do
                    if target.options[j].id == partial.value then
                        found = true
                        break
                    end
                end
                if not found then
                    return false, ('blocks.%s.value: option'):format(blockId)
                end
                cleanPartial.value = partial.value
            elseif btype == 'progress' then
                if type(partial.value) ~= 'number' or partial.value ~= partial.value or partial.value < 0 or partial.value > 1 then
                    return false, ('blocks.%s.value: range'):format(blockId)
                end
                cleanPartial.value = partial.value
            else
                return false, ('blocks.%s.value: not supported'):format(blockId)
            end
        end

        cleanBlocksPatch[blockId] = cleanPartial
    end

    if not hasAny then
        return false, 'patch.blocks: empty'
    end

    for blockId, cleanPartial in pairs(cleanBlocksPatch) do
        local target = blockMap[blockId]
        for k, v in pairs(cleanPartial) do
            target[k] = v
        end
    end

    return true, nil, { blocks = cleanBlocksPatch }
end

function L.createPanelManager()
    local pm = {
        seq = 0,
        byPlayer = {},
    }

    function pm:open(src, owner, spec)
        local key = tonumber(src) or src
        if not key then return nil, 'src: invalid' end
        local ok, err, cleanSpec = L.validateSpec(spec)
        if not ok then
            return nil, err
        end
        local replaced = self.byPlayer[key]
        self.seq = self.seq + 1
        local panelId = L.formatPanelId(self.seq)
        self.byPlayer[key] = {
            src = key,
            owner = owner or 'aeterna_uikit',
            panelId = panelId,
            spec = cleanSpec,
        }
        return panelId, nil, replaced
    end

    function pm:update(src, panelId, patch)
        local key = tonumber(src) or src
        local cur = self.byPlayer[key]
        if not cur or cur.panelId ~= panelId then
            return false, 'panel: not open'
        end
        local ok, err, cleanPatch = L.validatePatch(cur.spec, patch)
        if not ok then
            return false, err
        end
        return true, nil, cleanPatch
    end

    function pm:close(src, panelId, reason)
        local key = tonumber(src) or src
        local cur = self.byPlayer[key]
        if not cur then
            return false, nil
        end
        if panelId ~= nil and cur.panelId ~= panelId then
            return false, nil
        end
        self.byPlayer[key] = nil
        cur.closeReason = reason or 'closed'
        return true, cur
    end

    function pm:isOpen(src)
        local key = tonumber(src) or src
        local cur = self.byPlayer[key]
        if cur then return cur.panelId end
        return nil
    end

    function pm:getOpen(src)
        local key = tonumber(src) or src
        return self.byPlayer[key]
    end

    function pm:handleAction(src, payload)
        local key = tonumber(src) or src
        local cur = self.byPlayer[key]
        local ok, err, result = L.validateAction(cur, payload)
        if not ok then
            return false, err
        end
        if result.action == '__close' then
            self.byPlayer[key] = nil
        end
        return true, nil, result
    end

    function pm:removeByOwner(owner)
        local closed = {}
        for src, panel in pairs(self.byPlayer) do
            if panel.owner == owner then
                self.byPlayer[src] = nil
                closed[#closed + 1] = panel
            end
        end
        return closed
    end

    function pm:removePlayer(src)
        local key = tonumber(src) or src
        local cur = self.byPlayer[key]
        self.byPlayer[key] = nil
        return cur
    end

    return pm
end

function L.createMenuManager()
    local mm = {
        entries = {},
    }

    function mm:add(owner, entry)
        if type(owner) ~= 'string' or #owner < 1 or #owner > 64 then
            return false, 'owner: invalid'
        end
        if type(entry) ~= 'table' then
            return false, 'entry: type'
        end
        if not L.isValidId(entry.id, 32) then
            return false, 'id: pattern'
        end
        local okLbl, errLbl, cleanLbl = checkCleanString(entry.label, 1, 60, 'label')
        if not okLbl then
            return false, errLbl
        end
        local cleanIcon
        if entry.icon ~= nil and entry.icon ~= '' then
            if not L.isValidIcon(entry.icon) then
                return false, 'icon: unknown icon'
            end
            cleanIcon = entry.icon
        end
        local order = entry.order
        if order == nil then
            order = 100
        elseif type(order) ~= 'number' or order ~= order then
            return false, 'order: type'
        end
        local group = entry.group or 'general'
        if not L.isValidId(group, 32) then
            return false, 'group: pattern'
        end
        local ace = entry.ace
        if ace ~= nil and ace ~= '' then
            if type(ace) ~= 'string' or not ace:match('^aeterna%.[%w_%.%-]+$') then
                return false, 'ace: pattern'
            end
        else
            ace = nil
        end

        local cleanEntry = {
            owner = owner,
            id = entry.id,
            label = cleanLbl,
            icon = cleanIcon,
            order = order,
            group = group,
            ace = ace,
        }

        local key = owner .. '/' .. entry.id
        self.entries[key] = cleanEntry
        return true, nil, cleanEntry
    end

    function mm:remove(owner, id)
        if type(owner) ~= 'string' or type(id) ~= 'string' then
            return false
        end
        local key = owner .. '/' .. id
        if self.entries[key] then
            self.entries[key] = nil
            return true
        end
        return false
    end

    function mm:removeByOwner(owner)
        local removed = 0
        for key, entry in pairs(self.entries) do
            if entry.owner == owner then
                self.entries[key] = nil
                removed = removed + 1
            end
        end
        return removed
    end

    function mm:listForPlayer(src, canFn)
        local out = {}
        for _, entry in pairs(self.entries) do
            local allowed = true
            if entry.ace then
                allowed = type(canFn) == 'function' and canFn(src, entry.ace) == true or false
            end
            if allowed then
                out[#out + 1] = {
                    owner = entry.owner,
                    id = entry.id,
                    label = entry.label,
                    icon = entry.icon,
                    order = entry.order,
                    group = entry.group,
                }
            end
        end
        table.sort(out, function(a, b)
            if a.order ~= b.order then
                return a.order < b.order
            end
            if a.label ~= b.label then
                return a.label < b.label
            end
            if a.owner ~= b.owner then
                return a.owner < b.owner
            end
            return a.id < b.id
        end)
        return out
    end

    function mm:pick(src, owner, id, canFn)
        if type(owner) ~= 'string' or #owner < 1 or #owner > 64 then
            return false, 'owner: invalid'
        end
        if not L.isValidId(id, 32) then
            return false, 'id: pattern'
        end
        local key = owner .. '/' .. id
        local entry = self.entries[key]
        if not entry then
            return false, 'entry: not found'
        end
        if entry.ace then
            local allowed = type(canFn) == 'function' and canFn(src, entry.ace) == true or false
            if not allowed then
                return false, 'entry: ace denied'
            end
        end
        return true, nil, { owner = entry.owner, id = entry.id }
    end

    return mm
end

-- Client prompt validation helpers
function L.validateConfirmOpts(opts, defaultOk, defaultCancel)
    if type(opts) ~= 'table' then return false, 'opts: type' end
    local okTitle, errTitle, cleanTitle = checkCleanString(opts.title, 1, 60, 'title')
    if not okTitle then return false, errTitle end

    local cleanBody
    if opts.body ~= nil then
        local okBody, errBody, cb = checkCleanString(opts.body, 0, 400, 'body')
        if not okBody then return false, errBody end
        cleanBody = cb
    end

    local okLabel = defaultOk or 'Confirm'
    if opts.confirm ~= nil then
        local okC, errC, cc = checkCleanString(opts.confirm, 1, 24, 'confirm')
        if not okC then return false, errC end
        okLabel = cc
    end

    local cancelLabel = defaultCancel or 'Cancel'
    if opts.cancel ~= nil then
        local okCa, errCa, cca = checkCleanString(opts.cancel, 1, 24, 'cancel')
        if not okCa then return false, errCa end
        cancelLabel = cca
    end

    if opts.danger ~= nil and type(opts.danger) ~= 'boolean' then
        return false, 'danger: type'
    end

    return true, nil, {
        title = cleanTitle,
        body = cleanBody,
        confirm = okLabel,
        cancel = cancelLabel,
        danger = opts.danger == true,
    }
end

function L.validateInputOpts(opts)
    if type(opts) ~= 'table' then return false, 'opts: type' end
    local okTitle, errTitle, cleanTitle = checkCleanString(opts.title, 1, 60, 'title')
    if not okTitle then return false, errTitle end

    if not isArrayTable(opts.fields) or #opts.fields < 1 or #opts.fields > 6 then
        return false, 'fields: range'
    end

    local seenIds = {}
    local cleanFields = {}
    for i = 1, #opts.fields do
        local f = opts.fields[i]
        local fpath = ('fields[%d]'):format(i)
        if type(f) ~= 'table' then return false, fpath .. ': type' end
        local okId, errId = checkUniqueId(f.id, seenIds, fpath .. '.id')
        if not okId then return false, errId end
        local okField, errField, cleanField = validateFieldBlock(f, fpath)
        if not okField then return false, errField end
        cleanFields[i] = cleanField
    end

    return true, nil, {
        title = cleanTitle,
        fields = cleanFields,
    }
end

function L.validateInputValues(fields, values)
    if type(fields) ~= 'table' or type(values) ~= 'table' then
        return false, 'values: type'
    end
    return L.validateValues({ blocks = fields }, values)
end

function L.validateProgressOpts(opts)
    if type(opts) ~= 'table' then return false, 'opts: type' end
    local okLbl, errLbl, cleanLbl = checkCleanString(opts.label, 1, 60, 'label')
    if not okLbl then return false, errLbl end

    local dur = opts.duration
    if type(dur) ~= 'number' or dur ~= dur or dur < 300 or dur > 60000 then
        return false, 'duration: range'
    end

    local cancelable = true
    if opts.cancelable ~= nil then
        if type(opts.cancelable) ~= 'boolean' then return false, 'cancelable: type' end
        cancelable = opts.cancelable
    end

    local disable = {}
    if opts.disable ~= nil then
        if type(opts.disable) ~= 'table' then return false, 'disable: type' end
        disable = {
            move = opts.disable.move == true,
            car = opts.disable.car == true,
            combat = opts.disable.combat == true,
            mouse = opts.disable.mouse == true,
        }
    end

    return true, nil, {
        label = cleanLbl,
        duration = math.floor(dur),
        cancelable = cancelable,
        disable = disable,
    }
end

function L.validateSkillOpts(opts)
    if type(opts) ~= 'table' then return false, 'opts: type' end
    local diff = opts.difficulty or 'medium'
    if type(diff) ~= 'string' or not L.DIFFICULTIES[diff] then
        return false, 'difficulty: enum'
    end
    local rounds = opts.rounds or 1
    if type(rounds) ~= 'number' or rounds ~= math.floor(rounds) or rounds < 1 or rounds > 5 then
        return false, 'rounds: range'
    end
    return true, nil, {
        difficulty = diff,
        rounds = rounds,
    }
end

function L.validateKeyHints(list)
    if not isArrayTable(list) or #list < 1 or #list > 4 then
        return false, 'list: range'
    end
    local clean = {}
    for i = 1, #list do
        local row = list[i]
        local rpath = ('list[%d]'):format(i)
        if type(row) ~= 'table' then return false, rpath .. ': type' end
        if type(row.key) ~= 'string' or #row.key < 1 or #row.key > 64 then
            return false, rpath .. '.key: range'
        end
        local okLbl, errLbl, cleanLbl = checkCleanString(row.label, 1, 30, rpath .. '.label')
        if not okLbl then return false, errLbl end
        clean[i] = {
            key = row.key,
            label = cleanLbl,
        }
    end
    return true, nil, clean
end

function L.formatKeyBinding(rawButton, unboundLabel)
    local fallback = unboundLabel or 'Unbound'
    if type(rawButton) ~= 'string' or rawButton == '' then
        return fallback
    end
    if rawButton == 't_' or rawButton == 'b_-1' or rawButton == 'null' or rawButton == 'NONE' then
        return fallback
    end
    local stripped = rawButton:gsub('^[tb]_', '')
    if stripped == '' or stripped == '-1' or stripped == 'NULL' then
        return fallback
    end
    return stripped
end

return L
