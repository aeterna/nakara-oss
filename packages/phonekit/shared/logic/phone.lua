-- phone.lua -- Pure logic for aeterna_phonekit:
-- Notes & Contacts storage and validation (16 KB KVP limit),
-- App registry and ACE filtering,
-- Screen spec and action validation (reusing uikit panel spec rules),
-- Opening check controller (Config.ask = true),
-- Badge clamping and notification routing,
-- and layout helper definitions.
-- Natives-free so stock Lua 5.1+ can test it.

PhoneLogic = {}
local L = PhoneLogic

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
L.PATCH_KEYS = { label = true, value = true, items = true, disabled = true }

local BASE36_CHARS = '0123456789abcdefghijklmnopqrstuvwxyz'
local MAX_KVP_BYTES = 16384
local MAX_NOTES_COUNT = 50
local MAX_CONTACTS_COUNT = 100

function L.isValidIcon(name)
    return type(name) == 'string' and L.ICONS[name] == true
end

function L.isValidId(id, maxLen)
    local limit = maxLen or 32
    if type(id) ~= 'string' then return false end
    if #id < 1 or #id > limit then return false end
    return id:match('^[%w_%-]+$') ~= nil
end

function L.formatScreenId(counter)
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
    local id = 's' .. table.concat(rev)
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
            if i + seqLen - 1 > len then break end
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
            if visible >= maxVisible then break end
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

--------------------------------------------------------------------------------
-- 1. Notes & Contacts Storage and Validation (Client KVP)
--------------------------------------------------------------------------------

local function defaultEncodeJson(tbl)
    if type(json) == 'table' and type(json.encode) == 'function' then
        return json.encode(tbl)
    end
    -- Fallback simple JSON serializer for tests if json library is absent
    local parts = {}
    for i = 1, #tbl do
        local item = tbl[i]
        local itemParts = {}
        for k, v in pairs(item) do
            itemParts[#itemParts + 1] = string.format('%q:%q', tostring(k), tostring(v))
        end
        parts[#parts + 1] = '{' .. table.concat(itemParts, ',') .. '}'
    end
    return '[' .. table.concat(parts, ',') .. ']'
end

function L.validateNote(note)
    if type(note) ~= 'table' then
        return false, 'note: type'
    end
    local id = note.id
    if not L.isValidId(id, 32) then
        return false, 'note.id: pattern'
    end
    local okTitle, errTitle, cleanTitle = checkCleanString(note.title, 1, 60, 'note.title')
    if not okTitle then
        return false, errTitle
    end
    local bodyStr = type(note.body) == 'string' and note.body or ''
    local cleanBody = L.textClean(bodyStr, 2000)

    return true, nil, {
        id = id,
        title = cleanTitle,
        body = cleanBody,
        updatedAt = tonumber(note.updatedAt) or (os.time and os.time() or 0),
    }
end

function L.createNotesStore(initialData)
    local store = {
        notes = {},
        seq = 0,
    }

    if type(initialData) == 'table' then
        for i = 1, #initialData do
            local ok, _, clean = L.validateNote(initialData[i])
            if ok then
                store.notes[#store.notes + 1] = clean
                local num = tonumber(clean.id:match('^n(%d+)$'))
                if num and num > store.seq then
                    store.seq = num
                end
            end
        end
    end

    function store:list()
        local out = {}
        for i = 1, #self.notes do
            out[i] = self.notes[i]
        end
        return out
    end

    function store:get(id)
        for i = 1, #self.notes do
            if self.notes[i].id == id then
                return self.notes[i]
            end
        end
        return nil
    end

    function store:save(note, encodeFn)
        local n = type(note) == 'table' and note or {}
        local targetId = n.id
        local existingIdx = nil

        if targetId ~= nil then
            for i = 1, #self.notes do
                if self.notes[i].id == targetId then
                    existingIdx = i
                    break
                end
            end
        end

        if not existingIdx and #self.notes >= MAX_NOTES_COUNT then
            return false, 'phonekit.notes.full'
        end

        if not targetId or targetId == '' then
            self.seq = self.seq + 1
            targetId = 'n' .. tostring(self.seq)
        end

        local noteWithId = {
            id = targetId,
            title = n.title or '',
            body = n.body or '',
            updatedAt = n.updatedAt,
        }
        local okVal, errVal, clean = L.validateNote(noteWithId)
        if not okVal then
            return false, errVal
        end

        -- Prepare candidate list to test 16 KB boundary
        local candidate = {}
        for i = 1, #self.notes do
            if i == existingIdx then
                candidate[i] = clean
            else
                candidate[i] = self.notes[i]
            end
        end
        if not existingIdx then
            candidate[#candidate + 1] = clean
        end

        local encoder = encodeFn or defaultEncodeJson
        local okEnc, encoded = pcall(encoder, candidate)
        if not okEnc or type(encoded) ~= 'string' or #encoded > MAX_KVP_BYTES then
            return false, 'phonekit.notes.full'
        end

        self.notes = candidate
        return true, nil, clean
    end

    function store:delete(id)
        for i = 1, #self.notes do
            if self.notes[i].id == id then
                table.remove(self.notes, i)
                return true
            end
        end
        return false
    end

    function store:count()
        return #self.notes
    end

    return store
end

function L.validateContact(contact)
    if type(contact) ~= 'table' then
        return false, 'contact: type'
    end
    local id = contact.id
    if not L.isValidId(id, 32) then
        return false, 'contact.id: pattern'
    end
    local okName, errName, cleanName = checkCleanString(contact.name, 1, 40, 'contact.name')
    if not okName then
        return false, errName
    end
    local numStr = type(contact.number) == 'string' and contact.number or ''
    local cleanNum = L.textClean(numStr, 20)
    if L.textLen(cleanNum) < 1 then
        return false, 'contact.number: minLen 1'
    end

    return true, nil, {
        id = id,
        name = cleanName,
        number = cleanNum,
    }
end

function L.createContactsStore(initialData)
    local store = {
        contacts = {},
        seq = 0,
    }

    if type(initialData) == 'table' then
        for i = 1, #initialData do
            local ok, _, clean = L.validateContact(initialData[i])
            if ok then
                store.contacts[#store.contacts + 1] = clean
                local num = tonumber(clean.id:match('^c(%d+)$'))
                if num and num > store.seq then
                    store.seq = num
                end
            end
        end
    end

    function store:list()
        local out = {}
        for i = 1, #self.contacts do
            out[i] = self.contacts[i]
        end
        table.sort(out, function(a, b)
            return tostring(a.name) < tostring(b.name)
        end)
        return out
    end

    function store:get(id)
        for i = 1, #self.contacts do
            if self.contacts[i].id == id then
                return self.contacts[i]
            end
        end
        return nil
    end

    function store:save(contact, encodeFn)
        local c = type(contact) == 'table' and contact or {}
        local targetId = c.id
        local existingIdx = nil

        if targetId ~= nil then
            for i = 1, #self.contacts do
                if self.contacts[i].id == targetId then
                    existingIdx = i
                    break
                end
            end
        end

        if not existingIdx and #self.contacts >= MAX_CONTACTS_COUNT then
            return false, 'phonekit.contacts.full'
        end

        if not targetId or targetId == '' then
            self.seq = self.seq + 1
            targetId = 'c' .. tostring(self.seq)
        end

        local contactWithId = {
            id = targetId,
            name = c.name or '',
            number = c.number or '',
        }
        local okVal, errVal, clean = L.validateContact(contactWithId)
        if not okVal then
            return false, errVal
        end

        -- Check 16 KB boundary
        local candidate = {}
        for i = 1, #self.contacts do
            if i == existingIdx then
                candidate[i] = clean
            else
                candidate[i] = self.contacts[i]
            end
        end
        if not existingIdx then
            candidate[#candidate + 1] = clean
        end

        local encoder = encodeFn or defaultEncodeJson
        local okEnc, encoded = pcall(encoder, candidate)
        if not okEnc or type(encoded) ~= 'string' or #encoded > MAX_KVP_BYTES then
            return false, 'phonekit.contacts.full'
        end

        self.contacts = candidate
        return true, nil, clean
    end

    function store:delete(id)
        for i = 1, #self.contacts do
            if self.contacts[i].id == id then
                table.remove(self.contacts, i)
                return true
            end
        end
        return false
    end

    function store:count()
        return #self.contacts
    end

    return store
end

--------------------------------------------------------------------------------
-- 2. App Registry (Server)
--------------------------------------------------------------------------------

function L.createAppRegistry(config)
    local cfg = type(config) == 'table' and config or {}
    local maxApps = tonumber(cfg.maxApps) or 24
    local warnFn = type(cfg.warn) == 'function' and cfg.warn or nil

    local reg = {
        maxApps = maxApps,
        apps = {},
    }

    local function emitWarn(msg, fields)
        if warnFn then
            warnFn(msg, fields)
        elseif AeternaCore and AeternaCore.log and type(AeternaCore.log.warn) == 'function' then
            AeternaCore.log.warn(msg, fields)
        end
    end

    function reg:addTile(owner, app)
        if type(owner) ~= 'string' or owner == '' then
            return false, 'owner: type'
        end
        if type(app) ~= 'table' then
            return false, 'app: type'
        end
        if not L.isValidId(app.id, 32) then
            return false, 'id: pattern'
        end
        local okLbl, errLbl, cleanLbl = checkCleanString(app.label, 1, 24, 'label')
        if not okLbl then
            return false, errLbl
        end
        if type(app.icon) ~= 'string' or not L.isValidIcon(app.icon) then
            return false, 'icon: invalid'
        end
        local orderNum = tonumber(app.order) or 100
        local aceStr = nil
        if app.ace ~= nil then
            if type(app.ace) ~= 'string' or #app.ace < 1 or #app.ace > 64 then
                return false, 'ace: type'
            end
            aceStr = app.ace
        end

        local key = owner .. ':' .. app.id
        local existing = self.apps[key]

        if not existing then
            local totalCustom = 0
            for _ in pairs(self.apps) do
                totalCustom = totalCustom + 1
            end
            if totalCustom >= self.maxApps then
                emitWarn('phonekit maximum custom apps reached', {
                    max = self.maxApps,
                    owner = owner,
                    id = app.id,
                })
                return false, 'maxApps'
            end
        end

        self.apps[key] = {
            owner = owner,
            id = app.id,
            label = cleanLbl,
            icon = app.icon,
            order = orderNum,
            ace = aceStr,
        }
        return true
    end

    function reg:removeTile(owner, id)
        local key = tostring(owner) .. ':' .. tostring(id)
        if self.apps[key] then
            self.apps[key] = nil
            return true
        end
        return false
    end

    function reg:removeOwner(owner)
        if type(owner) ~= 'string' then return 0 end
        local removed = 0
        for k, app in pairs(self.apps) do
            if app.owner == owner then
                self.apps[k] = nil
                removed = removed + 1
            end
        end
        return removed
    end

    function reg:find(owner, id)
        if owner ~= nil then
            return self.apps[tostring(owner) .. ':' .. tostring(id)]
        end
        for _, app in pairs(self.apps) do
            if app.id == id then
                return app
            end
        end
        return nil
    end

    function reg:getVisibleApps(src, canFn)
        local visible = {}
        for _, app in pairs(self.apps) do
            local allowed = true
            if app.ace then
                if type(canFn) == 'function' then
                    allowed = canFn(src, app.ace) == true
                else
                    allowed = false
                end
            end
            if allowed then
                visible[#visible + 1] = {
                    owner = app.owner,
                    id = app.id,
                    label = app.label,
                    icon = app.icon,
                    order = app.order,
                }
            end
        end

        table.sort(visible, function(a, b)
            if a.order ~= b.order then
                return a.order < b.order
            end
            return a.id < b.id
        end)

        return visible
    end

    function reg:count()
        local c = 0
        for _ in pairs(self.apps) do c = c + 1 end
        return c
    end

    return reg
end

--------------------------------------------------------------------------------
-- 3. Screen Spec & Action Validation (reusing uikit rules)
--------------------------------------------------------------------------------

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

function L.validateAction(activeScreen, payload)
    if type(activeScreen) ~= 'table' or type(activeScreen.spec) ~= 'table' then
        return false, 'screen: closed'
    end
    if type(payload) ~= 'table' then
        return false, 'payload: type'
    end
    if type(payload.screenId) ~= 'string' or #payload.screenId > 24 or payload.screenId ~= activeScreen.screenId then
        return false, 'screenId: mismatch'
    end
    local action = payload.action
    if type(action) ~= 'string' or #action < 1 or #action > 32 then
        return false, 'action: invalid'
    end
    if not isActionInSpec(activeScreen.spec, action) then
        return false, 'action: not in spec'
    end

    local okVal, errVal, cleanValues = L.validateValues(activeScreen.spec, payload.values)
    if not okVal then
        return false, errVal
    end

    return true, nil, {
        owner = activeScreen.owner,
        id = activeScreen.id,
        screenId = activeScreen.screenId,
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
    end

    local cleanBlocksPatch = {}
    for blockId, partial in pairs(patch.blocks) do
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
                    local maxLen = target.maxLen or 60
                    local okVal, errVal, cv = checkCleanString(partial.value, 0, maxLen, ('blocks.%s.value'):format(blockId))
                    if not okVal then return false, errVal end
                    cleanPartial.value = cv
                end
            elseif btype == 'toggle' then
                if type(partial.value) ~= 'boolean' then
                    return false, ('blocks.%s.value: type'):format(blockId)
                end
                cleanPartial.value = partial.value
            elseif btype == 'select' then
                local found = false
                for j = 1, #target.options do
                    if target.options[j].id == partial.value then
                        found = true
                        break
                    end
                end
                if not found then
                    return false, ('blocks.%s.value: option not in list'):format(blockId)
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

    return true, nil, { blocks = cleanBlocksPatch }
end

--------------------------------------------------------------------------------
-- 4. Opening Check Manager (Config.ask = true)
--------------------------------------------------------------------------------

function L.createOpeningCheckManager(options)
    local opts = type(options) == 'table' and options or {}
    local setTimeoutFn = opts.setTimeout
    local clearTimeoutFn = opts.clearTimeout

    local mgr = {
        hasListeners = false,
        pendingChecks = {},
        seq = 0,
    }

    function mgr:listenOpen()
        self.hasListeners = true
        return true
    end

    function mgr:createCheck(src, onResolve)
        self.seq = self.seq + 1
        local checkId = 'chk_' .. tostring(self.seq)

        local check = {
            id = checkId,
            src = src,
            resolved = false,
            timer = nil,
            onResolve = onResolve,
        }

        if type(setTimeoutFn) == 'function' then
            check.timer = setTimeoutFn(1000, function()
                self:handleTimeout(checkId)
            end)
        end

        self.pendingChecks[checkId] = check
        return checkId
    end

    function mgr:allowOpen(checkId)
        local check = self.pendingChecks[checkId]
        if not check or check.resolved then
            return false, 'stale'
        end

        check.resolved = true
        if check.timer and type(clearTimeoutFn) == 'function' then
            clearTimeoutFn(check.timer)
        end
        self.pendingChecks[checkId] = nil

        if type(check.onResolve) == 'function' then
            check.onResolve(check.src, true, nil)
        end
        return true
    end

    function mgr:denyOpen(checkId, reasonKey)
        local check = self.pendingChecks[checkId]
        if not check or check.resolved then
            return false, 'stale'
        end

        check.resolved = true
        if check.timer and type(clearTimeoutFn) == 'function' then
            clearTimeoutFn(check.timer)
        end
        self.pendingChecks[checkId] = nil

        local reason = (type(reasonKey) == 'string' and reasonKey ~= '') and reasonKey or 'phonekit.refused.default'
        if type(check.onResolve) == 'function' then
            check.onResolve(check.src, false, reason)
        end
        return true
    end

    function mgr:handleTimeout(checkId)
        local check = self.pendingChecks[checkId]
        if not check or check.resolved then
            return
        end

        check.resolved = true
        self.pendingChecks[checkId] = nil

        if self.hasListeners then
            -- Silence with listeners counts as denied
            if type(check.onResolve) == 'function' then
                check.onResolve(check.src, false, 'phonekit.refused.default')
            end
        else
            -- Silence without listeners counts as allowed
            if type(check.onResolve) == 'function' then
                check.onResolve(check.src, true, nil)
            end
        end
    end

    return mgr
end

--------------------------------------------------------------------------------
-- 5. Badge & Notification Manager
--------------------------------------------------------------------------------

function L.clampBadge(count)
    local n = math.floor(tonumber(count) or 0)
    if n < 0 then return 0 end
    if n > 99 then return 99 end
    return n
end

function L.createBadgeManager()
    local mgr = {
        players = {},
    }

    local function getPlayer(src)
        local s = tostring(src)
        if not mgr.players[s] then
            mgr.players[s] = {
                phoneOpen = false,
                currentApp = nil,
                badges = {},
            }
        end
        return mgr.players[s]
    end

    function mgr:setPhoneOpen(src, isOpen)
        local p = getPlayer(src)
        p.phoneOpen = isOpen == true
        if not p.phoneOpen then
            p.currentApp = nil
        end
    end

    function mgr:setCurrentApp(src, appId)
        local p = getPlayer(src)
        p.currentApp = appId
    end

    function mgr:setBadge(src, id, count)
        local p = getPlayer(src)
        local clamped = L.clampBadge(count)
        p.badges[tostring(id)] = clamped
        return clamped
    end

    function mgr:getBadge(src, id)
        local p = getPlayer(src)
        return p.badges[tostring(id)] or 0
    end

    function mgr:notifyApp(src, id, opts, appInfo, notifyFn, bannerFn)
        local p = getPlayer(src)
        local strId = tostring(id)
        local isOnScreen = (p.phoneOpen and p.currentApp == strId)

        if not isOnScreen then
            local current = p.badges[strId] or 0
            p.badges[strId] = L.clampBadge(current + 1)
        end

        local titleClean = L.textClean(opts and opts.title or '', 60)
        local bodyClean = L.textClean(opts and opts.body or '', 160)

        if p.phoneOpen then
            if type(bannerFn) == 'function' then
                bannerFn(src, {
                    id = strId,
                    title = titleClean,
                    body = bodyClean,
                })
            end
        else
            if type(notifyFn) == 'function' then
                local icon = (appInfo and appInfo.icon) or 'bell'
                notifyFn(src, {
                    title = titleClean,
                    description = bodyClean,
                    icon = icon,
                })
            end
        end

        return p.badges[strId] or 0
    end

    function mgr:removePlayer(src)
        mgr.players[tostring(src)] = nil
    end

    return mgr
end

--------------------------------------------------------------------------------
-- 6. Position & Layout Helpers
--------------------------------------------------------------------------------

function L.positionToAnchor(pos)
    if pos == 'bottom-left' then
        return { x = 0.0125, y = 0.9778, ax = 0, ay = 1 }
    end
    -- Default 'bottom-right' (24 px inset on 1920x1080)
    return { x = 0.9875, y = 0.9778, ax = 1, ay = 1 }
end

function L.buildLayoutDefs(pos, label)
    local anchor = L.positionToAnchor(pos)
    local lbl = 'Phone'
    if type(label) == 'string' and L.stripControlAndTrim(label) ~= '' then
        lbl = L.textClean(label, 32)
    end
    return {
        {
            id = 'phone',
            label = lbl,
            w = 320,
            h = 640,
            x = anchor.x,
            y = anchor.y,
            ax = anchor.ax,
            ay = anchor.ay,
            scalable = true,
            hideable = false,
        },
    }
end

function L.validateLayoutPlace(place)
    if type(place) ~= 'table' then
        return false, 'place: type'
    end
    local x = tonumber(place.x)
    local y = tonumber(place.y)
    local ax = tonumber(place.ax)
    local ay = tonumber(place.ay)
    local scale = place.scale ~= nil and tonumber(place.scale) or 1.0

    if not x or x < 0 or x > 1 then
        return false, 'place.x: range'
    end
    if not y or y < 0 or y > 1 then
        return false, 'place.y: range'
    end
    if ax ~= 0 and ax ~= 0.5 and ax ~= 1 then
        return false, 'place.ax: enum'
    end
    if ay ~= 0 and ay ~= 0.5 and ay ~= 1 then
        return false, 'place.ay: enum'
    end
    if not scale or scale ~= scale or scale <= 0 or scale > 4 then
        return false, 'place.scale: range'
    end

    return true, nil, {
        x = x,
        y = y,
        ax = ax,
        ay = ay,
        scale = scale,
        hidden = false,
    }
end

return PhoneLogic
