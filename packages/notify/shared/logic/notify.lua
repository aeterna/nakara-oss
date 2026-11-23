-- Pure logic for aeterna_notify: toast opts (0.2: actions, sound, history, merge) and queue (0.2: merging, expiry,
-- sound throttle), announcement opts and queue (0.2: pause for a countdown), MOTD validation and state controller,
-- aeterna_announce command handler, and layout helpers.
-- Natives-free so stock Lua 5.1+ can test it.

NotifyLogic = {}
local L = NotifyLogic

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

L.TOAST_TYPES = {
    info = true,
    success = true,
    warning = true,
    error = true,
}

L.POSITIONS = {
    ['top-left'] = true,
    ['top-right'] = true,
    ['bottom-left'] = true,
    ['bottom-right'] = true,
}

local ANNOUNCE_ALLOWED_KEYS = {
    id = true,
    title = true,
    body = true,
    duration = true,
    by = true,
}

local MOTD_ALLOWED_KEYS = {
    version = true,
    eyebrow = true,
    title = true,
    lines = true,
    buttons = true,
}

function L.isValidIcon(name)
    return type(name) == 'string' and L.ICONS[name] == true
end

function L.isValidId(id, maxLen)
    local limit = maxLen or 32
    if type(id) ~= 'string' then return false end
    if #id < 1 or #id > limit then return false end
    return id:match('^[%w_%-]+$') ~= nil
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

local function checkStrictString(val, minLen, maxLen, path)
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

local function clampNumber(n, minVal, maxVal)
    local v = math.floor(n)
    if v < minVal then return minVal end
    if v > maxVal then return maxVal end
    return v
end

--------------------------------------------------------------------------------
-- Toasts: opts validation & queue
--------------------------------------------------------------------------------

-- Longest toastId a press may carry (`aeterna_notify:sv:action`, NUI `toastAction`).
L.TOAST_ID_MAX = 24

L.ACTION_VARIANTS = {
    primary = true,
    secondary = true,
}

-- A merged copy plays its sound only when the last sound of that toast started more than this long ago.
L.SOUND_THROTTLE_MS = 1000

local function warnVia(warnFn, msg, fields)
    if type(warnFn) == 'function' then
        warnFn(msg, fields)
    elseif AeternaCore and AeternaCore.log and type(AeternaCore.log.warn) == 'function' then
        AeternaCore.log.warn(msg, fields)
    end
end

local BASE36_DIGITS = '0123456789abcdefghijklmnopqrstuvwxyz'

function L.base36(n)
    local v = math.floor(tonumber(n) or 0)
    if v <= 0 then return '0' end
    local out = {}
    while v > 0 do
        local d = v % 36
        table.insert(out, 1, BASE36_DIGITS:sub(d + 1, d + 1))
        v = math.floor(v / 36)
    end
    return table.concat(out)
end

-- 1-2 entries; id <= 32 matching ^[%w_%-]+$ and unique; label 1-20 visible chars; variant primary|secondary.
function L.validateActions(actions)
    if type(actions) ~= 'table' or not isArrayTable(actions) then
        return false, 'actions: type'
    end
    local n = #actions
    if n < 1 then return false, 'actions: minItems 1' end
    if n > 2 then return false, 'actions: maxItems 2' end
    local seen = {}
    local out = {}
    for i = 1, n do
        local a = actions[i]
        local path = ('actions[%d]'):format(i)
        if type(a) ~= 'table' then
            return false, path .. ': type'
        end
        if not L.isValidId(a.id, 32) then
            return false, path .. '.id: pattern'
        end
        if seen[a.id] then
            return false, path .. '.id: unique'
        end
        seen[a.id] = true
        if type(a.label) ~= 'string' then
            return false, path .. '.label: type'
        end
        local labelLen = L.textLen(L.stripControlAndTrim(a.label))
        if labelLen < 1 then
            return false, path .. '.label: minLen 1'
        end
        if labelLen > 20 then
            return false, path .. '.label: maxLen 20'
        end
        local variant = 'secondary'
        if type(a.variant) == 'string' and L.ACTION_VARIANTS[a.variant] then
            variant = a.variant
        end
        out[i] = { id = a.id, label = L.textClean(a.label, 20), variant = variant }
    end
    return true, nil, out
end

local function flagDefaultTrue(v)
    return v ~= false
end

function L.validateToastOpts(opts, toastCfg, warnFn)
    if type(opts) ~= 'table' then
        return false, 'opts: type'
    end

    local cleanId = nil
    if opts.id ~= nil then
        if not L.isValidId(opts.id, 32) then
            return false, 'id: pattern'
        end
        cleanId = opts.id
    end

    local cleanDesc = nil
    if opts.description ~= nil then
        if type(opts.description) ~= 'string' then
            return false, 'description: type'
        end
        local cd = L.textClean(opts.description, 160)
        if L.textLen(cd) > 0 then
            cleanDesc = cd
        end
    end

    local cleanTitle = nil
    if opts.title ~= nil then
        if type(opts.title) ~= 'string' then
            return false, 'title: type'
        end
        local ct = L.textClean(opts.title, 60)
        if L.textLen(ct) > 0 then
            cleanTitle = ct
        end
    end
    if not cleanTitle and cleanDesc then
        cleanTitle = L.textClean(cleanDesc, 60)
        cleanDesc = nil
    end
    if not cleanTitle then
        return false, 'title: minLen 1'
    end

    local toastType = 'info'
    if type(opts.type) == 'string' and L.TOAST_TYPES[opts.type] then
        toastType = opts.type
    end

    local cfg = toastCfg
    if type(cfg) ~= 'table' then
        cfg = (type(Config) == 'table' and Config.toast) or nil
    end

    local cleanActions = nil
    if opts.actions ~= nil then
        -- An action press carries the toastId (= id) in at most 24 characters.
        if cleanId and #cleanId > L.TOAST_ID_MAX then
            return false, 'id: maxLen 24 with actions'
        end
        local okAct, errAct, ca = L.validateActions(opts.actions)
        if okAct then
            cleanActions = ca
        else
            warnVia(warnFn or (type(cfg) == 'table' and cfg.warn) or nil, 'toast actions dropped', { err = errAct })
        end
    end

    local defDur = (type(cfg) == 'table' and tonumber(cfg.defaultDuration)) or 4000
    if cleanActions then
        defDur = (type(cfg) == 'table' and tonumber(cfg.actionDuration)) or 8000
    end
    local rawDur = defDur
    if opts.duration ~= nil then
        if type(opts.duration) ~= 'number' or opts.duration ~= opts.duration or opts.duration == math.huge or opts.duration == -math.huge then
            return false, 'duration: type'
        end
        rawDur = opts.duration
    end
    local cleanDuration = clampNumber(rawDur, 1000, 15000)

    local cleanIcon = nil
    if type(opts.icon) == 'string' and opts.icon ~= '' and L.isValidIcon(opts.icon) then
        cleanIcon = opts.icon
    end

    return true, nil, {
        id = cleanId,
        title = cleanTitle,
        description = cleanDesc,
        type = toastType,
        duration = cleanDuration,
        icon = cleanIcon,
        actions = cleanActions,
        sound = flagDefaultTrue(opts.sound),
        history = flagDefaultTrue(opts.history),
        merge = flagDefaultTrue(opts.merge),
    }
end

-- Duplicate key: owner resource + type + title + description after cleaning (cleaned text holds no newline).
function L.mergeKey(owner, toast)
    return table.concat({
        tostring(owner or ''),
        tostring(toast.type or ''),
        tostring(toast.title or ''),
        tostring(toast.description or ''),
    }, '\n')
end

function L.formatCount(n)
    local v = math.floor(tonumber(n) or 0)
    if v < 2 then return '' end
    if v > 99 then return '×99+' end
    return '×' .. tostring(v)
end

-- Owner (Config.sound.enabled), player (settings KVP) and toast (`sound ~= false`) must all allow it.
function L.soundGate(ownerEnabled, playerEnabled, toastSound)
    return ownerEnabled == true and playerEnabled == true and toastSound ~= false
end

function L.formatKeyLabel(rawButton, unboundLabel)
    local fallback = unboundLabel or ''
    if type(rawButton) ~= 'string' or rawButton == '' then
        return fallback
    end
    local stripped = rawButton:gsub('^[tb]_', '')
    if stripped == '' or stripped == '-1' or stripped == 'NULL' or stripped == 'NONE' or stripped == 'null' then
        return fallback
    end
    return L.textClean(stripped, 16)
end

function L.createToastQueue(cfg)
    local maxVisible = 4
    local defaultDuration = 4000
    local actionDuration = 8000
    local mergeOn = true
    local warnFn = nil
    local src = nil
    if type(cfg) == 'number' then
        maxVisible = math.max(1, math.floor(cfg))
    elseif type(cfg) == 'table' then
        src = cfg
    elseif type(Config) == 'table' and type(Config.toast) == 'table' then
        src = Config.toast
    end
    if src then
        if tonumber(src.max) then
            maxVisible = math.max(1, math.floor(tonumber(src.max)))
        end
        if tonumber(src.defaultDuration) then
            defaultDuration = math.floor(tonumber(src.defaultDuration))
        end
        if tonumber(src.actionDuration) then
            actionDuration = clampNumber(tonumber(src.actionDuration), 1000, 15000)
        end
        mergeOn = src.merge ~= false
        if type(src.warn) == 'function' then
            warnFn = src.warn
        end
    end

    local q = {
        max = maxVisible,
        defaultDuration = defaultDuration,
        actionDuration = actionDuration,
        merge = mergeOn,
        warn = warnFn,
        items = {},
        seq = 0,
    }

    local function soundFor(item, clean, c, t)
        if c.soundAllowed ~= true or clean.sound == false then
            return false
        end
        if item.soundAt ~= nil and t - item.soundAt <= L.SOUND_THROTTLE_MS then
            return false
        end
        item.soundAt = t
        return true
    end

    -- ctx = { now = ms, owner = resource, origin = 'client'|'server', toastId = string?, soundAllowed = boolean }
    function q:push(opts, ctx)
        local c = type(ctx) == 'table' and ctx or {}
        local now = tonumber(c.now)
        if now then
            self:prune(now)
        end
        local t = now or 0

        local ok, err, clean = L.validateToastOpts(opts, {
            defaultDuration = self.defaultDuration,
            actionDuration = self.actionDuration,
        }, self.warn)
        if not ok then
            return false, err
        end

        local owner = type(c.owner) == 'string' and c.owner or nil

        if self.merge and clean.id == nil and clean.actions == nil and clean.merge then
            local key = L.mergeKey(owner, clean)
            for i = 1, #self.items do
                local item = self.items[i]
                if item.mergeKey == key then
                    item.count = item.count + 1
                    item.expiresAt = t + item.duration
                    return true, nil, {
                        toast = item,
                        replaced = false,
                        merged = true,
                        index = i,
                        evicted = nil,
                        sound = soundFor(item, clean, c, t),
                    }
                end
            end
            clean.mergeKey = key
        end

        self.seq = self.seq + 1
        local toastId
        if clean.id then
            toastId = clean.id
        elseif type(c.toastId) == 'string' and L.isValidId(c.toastId, 24) then
            toastId = c.toastId
        else
            -- Client-made auto ids are c + base-36; server-made ones are s + base-36 (set by the server).
            toastId = 'c' .. L.base36(self.seq)
        end
        clean.toastId = toastId
        clean.key = clean.id or ('#' .. L.base36(self.seq))
        clean.owner = owner
        clean.origin = c.origin == 'server' and 'server' or 'client'
        clean.count = 1
        clean.expiresAt = t + clean.duration
        local sound = soundFor(clean, clean, c, t)

        if clean.id then
            for i = 1, #self.items do
                if self.items[i].id == clean.id then
                    self.items[i] = clean
                    return true, nil, {
                        toast = clean,
                        replaced = true,
                        merged = false,
                        index = i,
                        evicted = nil,
                        sound = sound,
                    }
                end
            end
        end

        self.items[#self.items + 1] = clean
        local evicted = nil
        if #self.items > self.max then
            evicted = table.remove(self.items, 1)
        end

        return true, nil, {
            toast = clean,
            replaced = false,
            merged = false,
            index = #self.items,
            evicted = evicted,
            sound = sound,
        }
    end

    q.add = q.push
    q.notify = q.push

    -- Drops toasts whose timer ran out (a timed-out toast fires nothing).
    function q:prune(now)
        local t = tonumber(now)
        if not t then return end
        for i = #self.items, 1, -1 do
            local exp = self.items[i].expiresAt
            if exp ~= nil and exp <= t then
                table.remove(self.items, i)
            end
        end
    end

    function q:clear(id)
        if id == nil then
            self.items = {}
            return true
        end
        if type(id) ~= 'string' then
            return false
        end
        for i = 1, #self.items do
            if self.items[i].id == id then
                table.remove(self.items, i)
                return true
            end
        end
        return false
    end

    q.remove = q.clear

    function q:removeItem(item)
        for i = 1, #self.items do
            if self.items[i] == item then
                table.remove(self.items, i)
                return true
            end
        end
        return false
    end

    -- Newest on-screen toast with this toastId whose actions include `action`.
    function q:findAction(toastId, action, now)
        self:prune(now)
        if type(toastId) ~= 'string' or type(action) ~= 'string' then
            return nil
        end
        for i = #self.items, 1, -1 do
            local item = self.items[i]
            if item.toastId == toastId and item.actions then
                for j = 1, #item.actions do
                    if item.actions[j].id == action then
                        return item
                    end
                end
            end
        end
        return nil
    end

    function q:newestWithActions(now)
        self:prune(now)
        for i = #self.items, 1, -1 do
            if self.items[i].actions then
                return self.items[i]
            end
        end
        return nil
    end

    function q:list()
        local out = {}
        for i = 1, #self.items do
            out[i] = self.items[i]
        end
        return out
    end

    function q:count()
        return #self.items
    end

    function q:get(indexOrId)
        if type(indexOrId) == 'number' then
            return self.items[indexOrId]
        end
        for i = 1, #self.items do
            if self.items[i].id == indexOrId then
                return self.items[i]
            end
        end
        return nil
    end

    return q
end

--------------------------------------------------------------------------------
-- Announcements: opts validation, queue & command logic
--------------------------------------------------------------------------------

function L.validateAnnounceOpts(opts)
    if type(opts) ~= 'table' then
        return false, 'opts: type'
    end
    for k in pairs(opts) do
        if not ANNOUNCE_ALLOWED_KEYS[k] then
            return false, tostring(k) .. ': not allowed'
        end
    end

    local cleanId = nil
    if opts.id ~= nil then
        if not L.isValidId(opts.id, 32) then
            return false, 'id: pattern'
        end
        cleanId = opts.id
    end

    if type(opts.title) ~= 'string' then
        return false, 'title: type'
    end
    local cleanTitle = L.textClean(opts.title, 80)
    if L.textLen(cleanTitle) < 1 then
        return false, 'title: minLen 1'
    end

    local cleanBody = nil
    if opts.body ~= nil then
        if type(opts.body) ~= 'string' then
            return false, 'body: type'
        end
        local cb = L.textClean(opts.body, 200)
        if L.textLen(cb) > 0 then
            cleanBody = cb
        end
    end

    local rawDur = 8000
    if opts.duration ~= nil then
        if type(opts.duration) ~= 'number' or opts.duration ~= opts.duration or opts.duration == math.huge or opts.duration == -math.huge then
            return false, 'duration: type'
        end
        rawDur = opts.duration
    end
    local cleanDuration = clampNumber(rawDur, 3000, 30000)

    local cleanBy = nil
    if opts.by ~= nil then
        if type(opts.by) ~= 'string' then
            return false, 'by: type'
        end
        local cb = L.textClean(opts.by, 32)
        if L.textLen(cb) > 0 then
            cleanBy = cb
        end
    end

    return true, nil, {
        id = cleanId,
        title = cleanTitle,
        body = cleanBody,
        duration = cleanDuration,
        by = cleanBy,
    }
end

function L.createAnnounceQueue(cfg)
    local maxWaiting = 5
    local warnFn = nil
    local onShowFn = nil

    if type(cfg) == 'number' then
        maxWaiting = math.max(0, math.floor(cfg))
    elseif type(cfg) == 'table' then
        local m = tonumber(cfg.max) or tonumber(cfg.queue)
        if m ~= nil then
            maxWaiting = math.max(0, math.floor(m))
        end
        if type(cfg.warn) == 'function' then
            warnFn = cfg.warn
        end
        if type(cfg.onShow) == 'function' then
            onShowFn = cfg.onShow
        end
    elseif type(Config) == 'table' and type(Config.announce) == 'table' and tonumber(Config.announce.queue) then
        maxWaiting = math.max(0, math.floor(tonumber(Config.announce.queue)))
    end

    local function emitWarn(msg, fields)
        if warnFn then
            warnFn(msg, fields)
        elseif AeternaCore and AeternaCore.log and type(AeternaCore.log.warn) == 'function' then
            AeternaCore.log.warn(msg, fields)
        end
    end

    local aq = {
        max = maxWaiting,
        current = nil,
        waiting = {},
        seq = 0,
        paused = false,
    }

    function aq:push(opts)
        local ok, err, clean = L.validateAnnounceOpts(opts)
        if not ok then
            emitWarn('announce invalid opts', { err = err })
            return false, err, { status = 'invalid' }
        end

        if not clean.id then
            self.seq = self.seq + 1
            clean.id = 'a' .. tostring(self.seq)
        end

        if self.current == nil and not self.paused then
            self.current = clean
            if onShowFn then
                onShowFn(clean)
            end
            return true, nil, {
                status = 'shown',
                announce = clean,
            }
        end

        if #self.waiting >= self.max then
            emitWarn('announce queue full; dropping announcement', {
                max = self.max,
                title = clean.title,
            })
            return false, 'queue: full', {
                status = 'dropped',
                announce = clean,
            }
        end

        self.waiting[#self.waiting + 1] = clean
        return true, nil, {
            status = 'queued',
            announce = clean,
            position = #self.waiting,
        }
    end

    aq.enqueue = aq.push
    aq.add = aq.push
    aq.announce = aq.push

    function aq:next()
        if self.paused then
            return nil
        end
        if #self.waiting == 0 then
            self.current = nil
            return nil
        end
        self.current = table.remove(self.waiting, 1)
        if onShowFn then
            onShowFn(self.current)
        end
        return self.current
    end

    aq.advance = aq.next
    aq.pop = aq.next

    function aq:getCurrent()
        return self.current
    end

    function aq:getWaiting()
        local out = {}
        for i = 1, #self.waiting do
            out[i] = self.waiting[i]
        end
        return out
    end

    function aq:waitingCount()
        return #self.waiting
    end

    function aq:isShowing()
        return self.current ~= nil
    end

    function aq:clear()
        self.current = nil
        self.waiting = {}
    end

    -- A countdown banner goes ahead: the banner on screen goes back to the front of the line (it already counted
    -- against the cap), and nothing is shown until resume().
    function aq:pause()
        if self.paused then return nil end
        self.paused = true
        local held = self.current
        if held then
            table.insert(self.waiting, 1, held)
            self.current = nil
        end
        return held
    end

    function aq:resume()
        if not self.paused then return nil end
        self.paused = false
        if self.current == nil then
            return self:next()
        end
        return nil
    end

    function aq:isPaused()
        return self.paused == true
    end

    return aq
end

function L.extractCommandText(args, rawCommand, cmdName)
    local cmd = cmdName or 'aeterna_announce'
    if type(rawCommand) == 'string' and rawCommand ~= '' then
        local pat = '^%s*' .. cmd .. '%s*(.*)$'
        local rest = rawCommand:match(pat)
        if rest and L.stripControlAndTrim(rest) ~= '' then
            return rest
        end
        if not rawCommand:match('^%s*' .. cmd .. '%s*$') and not rest then
            return rawCommand
        end
    end
    if type(args) == 'table' and #args > 0 then
        local parts = {}
        for i = 1, #args do
            parts[i] = tostring(args[i])
        end
        return table.concat(parts, ' ')
    end
    return ''
end

function L.handleAnnounceCommand(src, rawText, deps)
    local d = type(deps) == 'table' and deps or {}
    local translate = d.t or function(k)
        if AeternaCore and type(AeternaCore.t) == 'function' then
            return AeternaCore.t(k)
        end
        if Locales and Locales.en and Locales.en[k] then
            return Locales.en[k]
        end
        return k
    end
    local canFn = d.can or function(s, action)
        if tonumber(s) == 0 then return true end
        if AeternaCore and type(AeternaCore.can) == 'function' then
            return AeternaCore.can(s, action)
        end
        return false
    end

    local numSrc = tonumber(src) or 0
    if numSrc ~= 0 then
        if not canFn(numSrc, 'aeterna.notify.announce') then
            local msg = translate('notify.announce.denied')
            if type(d.notify) == 'function' then
                d.notify(numSrc, { title = msg, type = 'error' })
            end
            return false, 'notify.announce.denied', msg
        end
    end

    local textStr = type(rawText) == 'string' and rawText or ''
    local stripped = L.stripControlAndTrim(textStr)
    if L.textLen(stripped) < 1 then
        local msg = translate('notify.announce.usage')
        if numSrc > 0 and type(d.notify) == 'function' then
            d.notify(numSrc, { title = msg, type = 'info' })
        end
        return false, 'notify.announce.usage', msg
    end

    local body = L.textClean(stripped, 200)
    local byName
    if numSrc == 0 then
        byName = translate('notify.announce.console')
    else
        local pName = type(d.getPlayerName) == 'function' and d.getPlayerName(numSrc) or nil
        if type(pName) == 'string' and L.stripControlAndTrim(pName) ~= '' then
            byName = pName
        else
            byName = translate('notify.announce.console')
        end
    end
    byName = L.textClean(byName, 32)

    local announceOpts = {
        title = translate('notify.announce.title'),
        body = body,
        duration = 8000,
        by = byName,
    }

    if type(d.announce) == 'function' then
        local ok, err, res = d.announce(announceOpts)
        if not ok then
            return false, err, res
        end
        return true, nil, res or announceOpts
    end

    return true, nil, announceOpts
end

--------------------------------------------------------------------------------
-- MOTD: validation & state controller
--------------------------------------------------------------------------------

function L.validateMotd(data)
    if type(data) ~= 'table' or isArrayTable(data) then
        return false, 'motd: type'
    end
    for k in pairs(data) do
        if not MOTD_ALLOWED_KEYS[k] then
            return false, tostring(k) .. ': not allowed'
        end
    end

    local okVer, errVer, cleanVer = checkStrictString(data.version, 1, 40, 'version')
    if not okVer then
        return false, errVer
    end

    local cleanEyebrow = nil
    if data.eyebrow ~= nil then
        local okEye, errEye, ce = checkStrictString(data.eyebrow, 0, 60, 'eyebrow')
        if not okEye then
            return false, errEye
        end
        if L.textLen(ce) > 0 then
            cleanEyebrow = ce
        end
    end

    local okTitle, errTitle, cleanTitle = checkStrictString(data.title, 1, 80, 'title')
    if not okTitle then
        return false, errTitle
    end

    if not isArrayTable(data.lines) then
        return false, 'lines: type'
    end
    if #data.lines < 1 then
        return false, 'lines: minItems 1'
    end
    if #data.lines > 8 then
        return false, 'lines: maxItems 8'
    end

    local cleanLines = {}
    for i = 1, #data.lines do
        local lpath = ('lines[%d]'):format(i)
        local okLine, errLine, cl = checkStrictString(data.lines[i], 1, 160, lpath)
        if not okLine then
            return false, errLine
        end
        cleanLines[i] = cl
    end

    local showDismiss = true
    if data.buttons ~= nil then
        if type(data.buttons) ~= 'table' or isArrayTable(data.buttons) then
            return false, 'buttons: type'
        end
        for k in pairs(data.buttons) do
            if k ~= 'dismiss' then
                return false, 'buttons.' .. tostring(k) .. ': not allowed'
            end
        end
        if data.buttons.dismiss ~= nil then
            if type(data.buttons.dismiss) ~= 'boolean' then
                return false, 'buttons.dismiss: type'
            end
            showDismiss = data.buttons.dismiss
        end
    end

    return true, nil, {
        version = cleanVer,
        eyebrow = cleanEyebrow,
        title = cleanTitle,
        lines = cleanLines,
        buttons = {
            dismiss = showDismiss,
        },
    }
end

function L.loadMotdJson(rawJson, decodeFn, warnFn)
    local function emitWarn(pathErr)
        if type(warnFn) == 'function' then
            warnFn('invalid config/motd.json; MOTD disabled', { path = pathErr })
        elseif AeternaCore and AeternaCore.log and type(AeternaCore.log.warn) == 'function' then
            AeternaCore.log.warn('invalid config/motd.json; MOTD disabled', { path = pathErr })
        end
    end

    if type(rawJson) ~= 'string' or L.stripControlAndTrim(rawJson) == '' then
        emitWarn('motd: empty')
        return nil, 'motd: empty'
    end

    local decoder = decodeFn or (type(json) == 'table' and json.decode) or nil
    if type(decoder) ~= 'function' then
        emitWarn('motd: decode unavailable')
        return nil, 'motd: decode unavailable'
    end

    local okDec, decoded = pcall(decoder, rawJson)
    if not okDec or type(decoded) ~= 'table' then
        emitWarn('motd: invalid json')
        return nil, 'motd: invalid json'
    end

    local okVal, errVal, clean = L.validateMotd(decoded)
    if not okVal then
        emitWarn(errVal)
        return nil, errVal
    end

    return clean, nil
end

function L.shouldShowMotd(motd, seenVersion, enabled, sessionSeenVersion)
    if enabled == false then
        return false, 'disabled'
    end
    if type(motd) ~= 'table' or type(motd.version) ~= 'string' then
        return false, 'invalid'
    end
    if type(sessionSeenVersion) == 'string' and sessionSeenVersion == motd.version then
        return false, 'session'
    end
    if type(seenVersion) == 'string' and seenVersion == motd.version then
        return false, 'seen'
    end
    return true, nil
end

function L.createMotdController(opts)
    local o = type(opts) == 'table' and opts or {}
    local enabled = (o.enabled ~= false)
    local motd = nil
    local loadErr = nil

    if not enabled then
        loadErr = 'disabled'
    elseif type(o.motd) == 'table' then
        local ok, err, clean = L.validateMotd(o.motd)
        if ok then
            motd = clean
        else
            loadErr = err
            if type(o.warn) == 'function' then
                o.warn('invalid config/motd.json; MOTD disabled', { path = err })
            end
        end
    else
        motd, loadErr = L.loadMotdJson(o.rawJson, o.decode, o.warn)
    end

    local ctrl = {
        enabled = enabled and (motd ~= nil),
        motd = motd,
        err = loadErr,
        sessionSeen = nil,
    }

    function ctrl:isValid()
        return self.enabled and self.motd ~= nil
    end

    function ctrl:getMotd()
        return self.motd
    end

    function ctrl:shouldShow(seenVersion)
        return L.shouldShowMotd(self.motd, seenVersion, self.enabled, self.sessionSeen)
    end

    function ctrl:markClosed(dismiss, setSeenFn)
        if not self.motd then return nil end
        local ver = self.motd.version
        self.sessionSeen = ver
        if dismiss == true and self.motd.buttons and self.motd.buttons.dismiss ~= false then
            if type(setSeenFn) == 'function' then
                setSeenFn(ver)
            end
        end
        return ver
    end

    return ctrl
end

--------------------------------------------------------------------------------
-- Position and aeterna_layout helpers
--------------------------------------------------------------------------------

function L.normalizePosition(pos)
    if type(pos) == 'string' and L.POSITIONS[pos] then
        return pos
    end
    return 'top-left'
end

function L.positionToAnchor(pos)
    local p = L.normalizePosition(pos)
    if p == 'top-right' then
        return { x = 0.9875, y = 0.0222, ax = 1, ay = 0 }
    elseif p == 'bottom-left' then
        return { x = 0.0125, y = 0.9778, ax = 0, ay = 1 }
    elseif p == 'bottom-right' then
        return { x = 0.9875, y = 0.9778, ax = 1, ay = 1 }
    end
    return { x = 0.0125, y = 0.0222, ax = 0, ay = 0 }
end

function L.buildLayoutDefs(position, announceLabel)
    local tAnchor = L.positionToAnchor(position)
    local annLbl = 'Announcement'
    if type(announceLabel) == 'string' and L.stripControlAndTrim(announceLabel) ~= '' then
        annLbl = L.textClean(announceLabel, 32)
    end
    return {
        {
            id = 'toasts',
            label = 'Toasts',
            w = 320,
            h = 280,
            x = tAnchor.x,
            y = tAnchor.y,
            ax = tAnchor.ax,
            ay = tAnchor.ay,
            scalable = true,
            hideable = false,
        },
        {
            id = 'announce',
            label = annLbl,
            w = 480,
            h = 88,
            x = 0.5,
            y = 0.0222,
            ax = 0.5,
            ay = 0,
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

return NotifyLogic
