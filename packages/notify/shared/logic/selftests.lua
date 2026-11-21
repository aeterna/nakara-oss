-- Pure self-test logic for aeterna_notify 0.2 (docs/specs/aeterna_notify.md § Self-tests (0.2)): the rows registered
-- with aeterna_core, their skip reasons, the four server checks, and the plans and pass rules of the client tests.
-- Natives-free; loads after the other shared/logic files.

NotifySelftests = {}
local M = NotifySelftests

M.PREFIX = 'aeterna_notify.'

-- Exactly the spec table. `expect` = the row has an Expect text (locale key notify.selftest.<name>).
M.ROWS = {
    { name = 'toast_opts', kind = 'headless' },
    { name = 'merge_key', kind = 'headless' },
    { name = 'action_forged', kind = 'headless' },
    { name = 'countdown_clock', kind = 'headless' },
    { name = 'toast_types', kind = 'eye', expect = true },
    { name = 'stack_merge', kind = 'eye', expect = true },
    { name = 'action_press', kind = 'ped', expect = true },
    { name = 'sound_plays', kind = 'eye', expect = true },
    { name = 'countdown_banner', kind = 'eye', expect = true },
    { name = 'history_pull', kind = 'headless', side = 'client' },
    { name = 'motion_reduced', kind = 'eye', expect = true },
}

local BY_NAME = {}
for i = 1, #M.ROWS do
    BY_NAME[M.ROWS[i].name] = M.ROWS[i]
end

M.TYPES = { 'info', 'success', 'warning', 'error' }
M.SOUND_STEP_MS = 1200

function M.register(add, t)
    local count = 0
    for i = 1, #M.ROWS do
        local row = M.ROWS[i]
        local meta = { kind = row.kind }
        if row.side then
            meta.side = row.side
        end
        if row.expect then
            meta.expect = t('notify.selftest.' .. row.name)
        end
        if add(M.PREFIX .. row.name, meta) ~= nil then
            count = count + 1
        end
    end
    return count
end

function M.shortName(fullName)
    if type(fullName) ~= 'string' or fullName:sub(1, #M.PREFIX) ~= M.PREFIX then
        return nil
    end
    local short = fullName:sub(#M.PREFIX + 1)
    return BY_NAME[short] and short or nil
end

-- The spec's "Skip when" column, the only reasons a test may report SKIP. cfg = Config.
function M.skipReason(short, cfg)
    local c = type(cfg) == 'table' and cfg or {}
    if short == 'sound_plays' and not (type(c.sound) == 'table' and c.sound.enabled == true) then
        return 'Config.sound.enabled = false'
    end
    if short == 'history_pull' and type(c.history) == 'table' and tonumber(c.history.max) == 0 then
        return 'Config.history.max = 0'
    end
    return nil
end

-- Runs checks in order; each returns a reason string when it fails. Returns ok, detail.
local function runChecks(checks)
    for i = 1, #checks do
        local why = checks[i].fn()
        if why then
            return false, checks[i].label .. ': ' .. why
        end
    end
    return true, #checks .. ' cases held'
end

local TOAST_CFG = { defaultDuration = 4000, actionDuration = 8000 }

-- toast_opts: the 0.2 toast fields and their fallbacks.
local function toastOpts(L)
    local function case(label, opts, verify)
        return { label = label, fn = function()
            local warns = {}
            local ok, err, clean = L.validateToastOpts(opts, TOAST_CFG, function(msg) warns[#warns + 1] = msg end)
            return verify(ok, err, clean, warns)
        end }
    end
    local function action(id, label) return { id = id, label = label or 'Go' } end
    local function droppedWithOneWarn(ok, err, clean, warns)
        if not ok then return 'refused (' .. tostring(err) .. ')' end
        if clean.actions ~= nil then return 'actions kept' end
        if #warns ~= 1 then return #warns .. ' warnings' end
        return nil
    end
    return runChecks({
        case('three actions fall back to none', { title = 'T', actions = { action('a'), action('b'), action('c') } },
            droppedWithOneWarn),
        case('a bad action id falls back to none', { title = 'T', actions = { action('bad id') } }, droppedWithOneWarn),
        case('a 21-character action label falls back to none', { title = 'T', actions = { action('a', ('ก'):rep(21)) } },
            droppedWithOneWarn),
        case('two good actions are kept', { title = 'T', actions = { action('a'), action('b') } }, function(ok, _, clean)
            if not ok or type(clean.actions) ~= 'table' or #clean.actions ~= 2 then return 'actions dropped' end
            if clean.duration ~= TOAST_CFG.actionDuration then return 'duration ' .. tostring(clean.duration) end
            return nil
        end),
        case('an id over 24 characters with actions is refused', { id = ('a'):rep(25), title = 'T', actions = { action('a') } },
            function(ok, err)
                return (ok or err ~= 'id: maxLen 24 with actions') and 'got ' .. tostring(err) or nil
            end),
        case('a toast with no title is refused', {}, function(ok) return ok and 'accepted' or nil end),
        case('duration clamps to 15000', { title = 'T', duration = 99999 }, function(ok, _, clean)
            return (not ok or clean.duration ~= 15000) and 'duration ' .. tostring(ok and clean.duration) or nil
        end),
        case('sound as a string reads as true', { title = 'T', sound = 'bell' }, function(ok, _, clean)
            return (not ok or clean.sound ~= true) and 'sound ' .. tostring(ok and clean.sound) or nil
        end),
        case('sound = false stays off', { title = 'T', sound = false }, function(ok, _, clean)
            return (not ok or clean.sound ~= false) and 'sound ' .. tostring(ok and clean.sound) or nil
        end),
    })
end

-- merge_key: identical toasts merge with a count; anything that differs, or opts out, never merges.
local function mergeKey(L)
    local q = L.createToastQueue({ max = 8, defaultDuration = 4000, merge = true })
    local base = { title = 'Same', description = 'Text', type = 'info' }
    local function with(extra)
        local o = {}
        for k, v in pairs(base) do o[k] = v end
        for k, v in pairs(extra or {}) do o[k] = v end
        return o
    end
    local function push(opts, owner, now)
        local ok, err, res = q:push(opts, { now = now, owner = owner or 'res_a', origin = 'client' })
        if not ok then return nil, err end
        return res
    end
    local function notMerged(label, opts, owner)
        return { label = label, fn = function()
            local res, err = push(opts, owner, 2000)
            if not res then return 'refused (' .. tostring(err) .. ')' end
            return res.merged and 'merged' or nil
        end }
    end
    return runChecks({
        { label = 'first toast', fn = function()
            local res = push(with(), nil, 0)
            return (not res or res.merged) and 'not added' or nil
        end },
        { label = 'same toast twice', fn = function()
            local res = push(with(), nil, 1000)
            if not res or not res.merged then return 'not merged' end
            if res.toast.count ~= 2 then return 'count ' .. tostring(res.toast.count) end
            if res.toast.expiresAt ~= 1000 + res.toast.duration then return 'timer not restarted' end
            return nil
        end },
        notMerged('a different description', with({ description = 'Other' })),
        notMerged('another owner', with(), 'res_b'),
        notMerged('a toast with an id', with({ id = 'fixed' })),
        notMerged('a toast with actions', with({ actions = { { id = 'a', label = 'Go' } } })),
        notMerged('merge = false', with({ merge = false })),
        { label = 'count label', fn = function()
            if L.formatCount(2) ~= '×2' then return L.formatCount(2) end
            if L.formatCount(100) ~= '×99+' then return L.formatCount(100) end
            return nil
        end },
    })
end

-- action_forged: a press counts only for a toast sent to that player, with one of its ids, once, in time.
local function actionForged(L)
    local tr = L.createActionTracker({ max = 8, graceMs = 2000 })
    local rec = { actions = { { id = 'pin' }, { id = 'skip' } }, duration = 8000, owner = 'res_a' }
    local function track(toastId)
        tr:track(1, { toastId = toastId, actions = rec.actions, duration = rec.duration, owner = rec.owner }, 0)
    end
    track('s1')
    track('s2')
    local function refused(label, src, toastId, action, now)
        return { label = label, fn = function()
            return tr:press(src, toastId, action, now) and 'accepted' or nil
        end }
    end
    return runChecks({
        refused('unknown toastId', 1, 's9', 'pin', 100),
        refused('action not in the toast', 1, 's1', 'nope', 100),
        refused('another player', 2, 's1', 'pin', 100),
        { label = 'good press', fn = function()
            local ok, got = tr:press(1, 's1', 'pin', 1000)
            if not ok then return 'refused' end
            if got.owner ~= 'res_a' or got.action ~= 'pin' then return 'wrong record' end
            return nil
        end },
        refused('second press', 1, 's1', 'pin', 1100),
        refused('press after duration + 2000 ms', 1, 's2', 'pin', 10001),
        { label = 'payload with an extra key', fn = function()
            return L.validateActionPress({ toastId = 's1', action = 'pin', x = 1 }) and 'accepted' or nil
        end },
        { label = 'over-long toastId', fn = function()
            return L.validateActionPress({ toastId = ('a'):rep(25), action = 'pin' }) and 'accepted' or nil
        end },
    })
end

-- countdown_clock: limits, one at a time, marks, the end event once, cancel by owner only, mm:ss.
local function countdownClock(L)
    local sends, fires = {}, {}
    local cd = L.createCountdown({
        send = function(p) sends[#sends + 1] = p end,
        fire = function(p) fires[#fires + 1] = p end,
    })
    local id
    return runChecks({
        { label = '9 seconds refused', fn = function()
            return cd:start({ title = 'T', seconds = 9 }, 0, 'res_a') and 'started' or nil
        end },
        { label = '3601 seconds refused', fn = function()
            return cd:start({ title = 'T', seconds = 3601 }, 0, 'res_a') and 'started' or nil
        end },
        { label = 'marks above seconds dropped', fn = function()
            local ok, _, clean = L.validateCountdownOpts({ title = 'T', seconds = 30, marks = { 60, 20, 10 } })
            if not ok or #clean.marks ~= 2 or clean.marks[1] ~= 20 or clean.marks[2] ~= 10 then return 'marks kept' end
            return nil
        end },
        { label = 'start', fn = function()
            id = cd:start({ title = 'T', seconds = 30, marks = { 60, 20, 10 } }, 0, 'res_a')
            if not id then return 'refused' end
            return (#sends ~= 1 or sends[1].remainingMs ~= 30000) and 'first banner wrong' or nil
        end },
        { label = 'second countdown busy', fn = function()
            local other, err = cd:start({ title = 'T', seconds = 30 }, 0, 'res_a')
            return (other or err ~= 'busy') and 'got ' .. tostring(other or err) or nil
        end },
        { label = 'banner again at the 20 s mark', fn = function()
            cd:tick(5000)
            cd:tick(10000)
            return (#sends ~= 2 or sends[2].remainingMs ~= 20000) and #sends .. ' banners' or nil
        end },
        { label = 'end fires once', fn = function()
            cd:tick(30000)
            cd:tick(31000)
            if #fires ~= 1 then return #fires .. ' end events' end
            return (fires[1].countdownId ~= id or fires[1].cancelled ~= false) and 'wrong end event' or nil
        end },
        { label = 'cancel by owner only', fn = function()
            local id2 = cd:start({ title = 'T', seconds = 30 }, 40000, 'res_a')
            if not id2 then return 'not started' end
            if cd:cancel(id2, 'res_b') then return 'another resource cancelled it' end
            if not cd:cancel(id2, 'res_a') then return 'owner could not cancel' end
            return (#fires ~= 2 or fires[2].cancelled ~= true) and 'no cancelled end event' or nil
        end },
        { label = 'mm:ss', fn = function()
            if L.formatClock(65000) ~= '01:05' then return L.formatClock(65000) end
            return L.formatClock(0) ~= '00:00' and L.formatClock(0) or nil
        end },
    })
end

local SERVER_CHECKS = {
    toast_opts = toastOpts,
    merge_key = mergeKey,
    action_forged = actionForged,
    countdown_clock = countdownClock,
}

function M.run(short, L)
    local fn = SERVER_CHECKS[short]
    if not fn then
        return nil
    end
    return fn(L)
end

-- Client plans and judges ----------------------------------------------------------------------------------------

-- sound_plays: each type once as if the player's setting were on, then each type once as if it were off.
-- The player's stored setting is never changed.
function M.soundPlan()
    local plan = {}
    for _, playerOn in ipairs({ true, false }) do
        for _, ty in ipairs(M.TYPES) do
            plan[#plan + 1] = { type = ty, playerOn = playerOn, delayMs = M.SOUND_STEP_MS }
        end
    end
    return plan
end

-- countdown_banner: the banners a server countdown of `seconds` would send (start, then each mark), on a local clock.
function M.countdownPlan(L, seconds, marks)
    local shows = { { atMs = 0, remainingMs = seconds * 1000 } }
    for _, m in ipairs(L.normalizeMarks(marks, seconds)) do
        shows[#shows + 1] = { atMs = (seconds - m) * 1000, remainingMs = m * 1000 }
    end
    return { shows = shows, endMs = seconds * 1000 }
end

-- action_press: received = the aeterna_notify:action payload the test got; onScreen = the toast is still up.
function M.judgeActionPress(received, onScreen, firstId)
    if type(received) ~= 'table' then
        return false, 'the press did not reach the test'
    end
    if received.action ~= firstId then
        return false, 'the test got action ' .. tostring(received.action)
    end
    if onScreen then
        return false, 'the toast stayed on screen'
    end
    return true, 'action 1 reached the test and the toast closed'
end

-- history_pull, logic half: newest first, `limit` clamps to 1-50, a merge updates its entry, at most `max` kept.
function M.historyCheck(L, max)
    local h = L.createHistory(max)
    local keep = math.min(3, h.max)
    local function entry(id, at, count)
        return { id = id, owner = 'aeterna_notify', kind = 'toast', type = 'info', title = id, count = count or 1, at = at }
    end
    h:upsert(entry('a', 10))
    h:upsert(entry('b', 20))
    h:upsert(entry('c', 30))
    local list = h:list(50)
    if #list ~= keep then return false, 'kept ' .. #list .. ', expected ' .. keep end
    if list[1].id ~= 'c' then return false, 'newest is not first' end
    h:upsert(entry('b', 40, 2))
    list = h:list(50)
    if #list ~= keep then return false, 'a merge added an entry' end
    if list[1].id ~= 'b' or list[1].count ~= 2 then return false, 'a merge did not update its entry' end
    if #h:list(0) ~= 1 then return false, 'limit 0 did not clamp to 1' end
    return true, 'history logic held'
end

local KINDS = { toast = true, announce = true, countdown = true }

-- history_pull, export half: what the client export returned for `limit`.
function M.historyShape(list, limit)
    if type(list) ~= 'table' then
        return false, 'the export returned ' .. type(list)
    end
    if #list > limit then
        return false, #list .. ' entries for limit ' .. limit
    end
    for i = 1, #list do
        local e = list[i]
        if type(e) ~= 'table' or type(e.id) ~= 'string' or not KINDS[e.kind] or type(e.count) ~= 'number'
            or type(e.at) ~= 'number' then
            return false, 'entry ' .. i .. ' is malformed'
        end
        if i > 1 and e.at > list[i - 1].at then
            return false, 'entry ' .. i .. ' is newer than the one before'
        end
    end
    return true, #list .. ' entries, newest first'
end

return NotifySelftests
