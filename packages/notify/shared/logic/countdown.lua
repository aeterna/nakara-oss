-- Pure logic for aeterna_notify 0.2 countdown announcements: opts, the server clock with marks, the client message
-- check, mm:ss, and the aeterna_announce_countdown command. Natives-free so busted can load it.

NotifyLogic = NotifyLogic or {}
local L = NotifyLogic

L.COUNTDOWN_DEFAULT_MARKS = { 600, 300, 60, 30, 10 }
L.COUNTDOWN_MAX_MARKS = 8
L.COUNTDOWN_MIN_SECONDS = 10
L.COUNTDOWN_MAX_SECONDS = 3600
-- How long one showing of the banner stays up; a showing with no more than twice this left stays until zero.
L.COUNTDOWN_SHOW_MS = 8000

local COUNTDOWN_ALLOWED_KEYS = {
    title = true,
    body = true,
    seconds = true,
    by = true,
    marks = true,
}

local function isFiniteNumber(v)
    return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge
end

local function cleanOptional(value, maxLen, path)
    if value == nil then
        return true, nil, nil
    end
    if type(value) ~= 'string' then
        return false, path .. ': type'
    end
    local c = L.textClean(value, maxLen)
    if L.textLen(c) > 0 then
        return true, nil, c
    end
    return true, nil, nil
end

local function configMarks()
    if type(Config) == 'table' and type(Config.countdown) == 'table' and type(Config.countdown.marks) == 'table' then
        return Config.countdown.marks
    end
    return L.COUNTDOWN_DEFAULT_MARKS
end

-- Whole seconds above 0 and below `seconds`, unique, largest first, at most 8; anything else is dropped.
function L.normalizeMarks(marks, seconds)
    local seen = {}
    local out = {}
    for i = 1, #marks do
        local m = marks[i]
        if isFiniteNumber(m) and m == math.floor(m) and m > 0 and m < seconds and not seen[m] then
            seen[m] = true
            out[#out + 1] = m
        end
    end
    table.sort(out, function(a, b) return a > b end)
    while #out > L.COUNTDOWN_MAX_MARKS do
        table.remove(out)
    end
    return out
end

function L.validateCountdownOpts(opts, defaultMarks)
    if type(opts) ~= 'table' then
        return false, 'opts: type'
    end
    for k in pairs(opts) do
        if not COUNTDOWN_ALLOWED_KEYS[k] then
            return false, tostring(k) .. ': not allowed'
        end
    end

    if type(opts.title) ~= 'string' then
        return false, 'title: type'
    end
    local cleanTitle = L.textClean(opts.title, 80)
    if L.textLen(cleanTitle) < 1 then
        return false, 'title: minLen 1'
    end

    local okBody, errBody, cleanBody = cleanOptional(opts.body, 200, 'body')
    if not okBody then return false, errBody end
    local okBy, errBy, cleanBy = cleanOptional(opts.by, 32, 'by')
    if not okBy then return false, errBy end

    if not isFiniteNumber(opts.seconds) then
        return false, 'seconds: type'
    end
    local seconds = math.floor(opts.seconds)
    if seconds < L.COUNTDOWN_MIN_SECONDS or seconds > L.COUNTDOWN_MAX_SECONDS then
        return false, 'seconds: range'
    end

    local rawMarks = opts.marks
    if rawMarks == nil then
        rawMarks = type(defaultMarks) == 'table' and defaultMarks or configMarks()
    elseif type(rawMarks) ~= 'table' then
        return false, 'marks: type'
    end

    return true, nil, {
        title = cleanTitle,
        body = cleanBody,
        by = cleanBy,
        seconds = seconds,
        marks = L.normalizeMarks(rawMarks, seconds),
    }
end

-- Server clock. deps = { send(payload), fire(endPayload), marks = default marks }.
-- One countdown at a time; `tick(now)` resends the banner when a mark is passed and ends it at zero.
function L.createCountdown(deps)
    local d = type(deps) == 'table' and deps or {}
    local cd = {
        seq = 0,
        current = nil,
    }

    local function send(payload)
        if type(d.send) == 'function' then d.send(payload) end
    end

    local function fire(payload)
        if type(d.fire) == 'function' then d.fire(payload) end
    end

    local function banner(cur, remainingMs)
        return {
            countdownId = cur.id,
            title = cur.title,
            body = cur.body,
            by = cur.by,
            remainingMs = math.max(0, math.floor(remainingMs)),
        }
    end

    function cd:start(opts, now)
        if self.current then
            return nil, 'busy'
        end
        local ok, err, clean = L.validateCountdownOpts(opts, d.marks)
        if not ok then
            return nil, err
        end
        self.seq = self.seq + 1
        local cur = {
            id = 'c' .. L.base36(self.seq),
            title = clean.title,
            body = clean.body,
            by = clean.by,
            endsAt = (tonumber(now) or 0) + clean.seconds * 1000,
            marks = clean.marks,
            nextMark = 1,
        }
        self.current = cur
        send(banner(cur, clean.seconds * 1000))
        return cur.id
    end

    function cd:tick(now)
        local cur = self.current
        if not cur then return end
        local remaining = cur.endsAt - (tonumber(now) or 0)
        if remaining <= 0 then
            self.current = nil
            fire({ countdownId = cur.id, cancelled = false })
            return
        end
        local passed = false
        while cur.nextMark <= #cur.marks and remaining <= cur.marks[cur.nextMark] * 1000 do
            cur.nextMark = cur.nextMark + 1
            passed = true
        end
        if passed then
            send(banner(cur, remaining))
        end
    end

    function cd:cancel(countdownId)
        local cur = self.current
        if not cur or cur.id ~= countdownId then
            return false
        end
        self.current = nil
        send({ countdownId = cur.id, hide = true })
        fire({ countdownId = cur.id, cancelled = true })
        return true
    end

    function cd:active()
        return self.current and self.current.id or nil
    end

    return cd
end

function L.formatClock(ms)
    local total = math.ceil(math.max(0, tonumber(ms) or 0) / 1000)
    return ('%02d:%02d'):format(math.floor(total / 60), total % 60)
end

function L.countdownShowMs(remainingMs)
    local r = math.max(0, math.floor(tonumber(remainingMs) or 0))
    if r <= L.COUNTDOWN_SHOW_MS * 2 then
        return r
    end
    return L.COUNTDOWN_SHOW_MS
end

-- Client check of `aeterna_notify:cl:countdown`.
function L.validateCountdownMessage(msg)
    if type(msg) ~= 'table' then
        return false, 'msg: type'
    end
    if not L.isValidId(msg.countdownId, 24) then
        return false, 'countdownId: pattern'
    end
    if msg.hide == true then
        return true, nil, { countdownId = msg.countdownId, hide = true }
    end
    if type(msg.title) ~= 'string' then
        return false, 'title: type'
    end
    local title = L.textClean(msg.title, 80)
    if L.textLen(title) < 1 then
        return false, 'title: minLen 1'
    end
    local okBody, errBody, body = cleanOptional(msg.body, 200, 'body')
    if not okBody then return false, errBody end
    local okBy, errBy, by = cleanOptional(msg.by, 32, 'by')
    if not okBy then return false, errBy end
    if not isFiniteNumber(msg.remainingMs) then
        return false, 'remainingMs: type'
    end
    local remaining = math.floor(msg.remainingMs)
    if remaining < 0 then remaining = 0 end
    if remaining > L.COUNTDOWN_MAX_SECONDS * 1000 then remaining = L.COUNTDOWN_MAX_SECONDS * 1000 end
    return true, nil, { countdownId = msg.countdownId, title = title, body = body, by = by, remainingMs = remaining }
end

-- `aeterna_announce_countdown <minutes> <text>`; deps = { can, t, notify(src, opts), getPlayerName, start(opts) }.
function L.handleCountdownCommand(src, rawText, deps)
    local d = type(deps) == 'table' and deps or {}
    local translate = d.t or function(k) return k end
    local canFn = d.can or function(s) return tonumber(s) == 0 end
    local numSrc = tonumber(src) or 0

    local function tell(key, toastType)
        local msg = translate(key)
        if numSrc > 0 and type(d.notify) == 'function' then
            d.notify(numSrc, { title = msg, type = toastType })
        end
        return msg
    end

    if numSrc ~= 0 and not canFn(numSrc, 'aeterna.notify.announce') then
        return false, 'notify.announce.denied', tell('notify.announce.denied', 'error')
    end

    local textStr = type(rawText) == 'string' and rawText or ''
    local minutesStr, rest = L.stripControlAndTrim(textStr):match('^(%S+)%s*(.-)$')
    local minutes = tonumber(minutesStr)
    local body = L.textClean(rest or '', 200)
    if not minutes or minutes ~= math.floor(minutes) or minutes < 1 or minutes > 60 or L.textLen(body) < 1 then
        return false, 'notify.countdown.usage', tell('notify.countdown.usage', 'info')
    end

    local byName = nil
    if numSrc ~= 0 and type(d.getPlayerName) == 'function' then
        local pName = d.getPlayerName(numSrc)
        if type(pName) == 'string' and L.stripControlAndTrim(pName) ~= '' then
            byName = pName
        end
    end
    byName = L.textClean(byName or translate('notify.announce.console'), 32)

    local opts = {
        title = translate('notify.countdown.title'),
        body = body,
        seconds = minutes * 60,
        by = byName,
    }
    if type(d.start) ~= 'function' then
        return true, nil, opts
    end
    local id, err = d.start(opts)
    if not id then
        if err == 'busy' then
            return false, 'notify.countdown.busy', tell('notify.countdown.busy', 'warning')
        end
        return false, err, err
    end
    return true, nil, id
end

return NotifyLogic
