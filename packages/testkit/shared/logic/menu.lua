-- Pure menu logic for aeterna_testkit: update throttle, player B invites, the eye card state, console arguments
-- and the uikit panel specs. No natives; the clock and every side effect are passed in.

TestkitLogic = TestkitLogic or {}

local M = {}

-- At most one update per `ms`. hit(now) = send now?; a refused hit leaves one update pending for due(now).
-- final(now) always sends (the last update after runDone).
function M.createThrottle(ms)
    local t = { last = nil, pending = false }

    function t:hit(now)
        if self.last == nil or now - self.last >= ms then
            self.last, self.pending = now, false
            return true
        end
        self.pending = true
        return false
    end

    function t:due(now)
        if self.pending and now - self.last >= ms then
            self.last, self.pending = now, false
            return true
        end
        return false
    end

    -- Milliseconds until the pending update may go (0 when nothing is pending or it may go now).
    function t:wait(now)
        if not self.pending then return 0 end
        return math.max(0, ms - (now - self.last))
    end

    function t:final(now)
        self.last, self.pending = now, false
        return true
    end

    return t
end

-- Player B invites. opts = { seconds, now = function() -> ms }.
-- One open invite or accepted pair per player, on either side.
function M.createInvites(opts)
    local seconds, now = opts.seconds, opts.now
    local inv = { open = {}, pairs = {} } -- open[a] = { a, b, expires }; pairs[a] = b

    local function involved(id)
        for a, o in pairs(inv.open) do
            if a == id or o.b == id then return true end
        end
        for a, b in pairs(inv.pairs) do
            if a == id or b == id then return true end
        end
        return false
    end

    -- Removes expired invites and returns them as { { a, b } }.
    function inv:expire()
        local gone, t = {}, now()
        for a, o in pairs(self.open) do
            if t >= o.expires then
                gone[#gone + 1] = { a = a, b = o.b }
                self.open[a] = nil
            end
        end
        return gone
    end

    -- isOnline(id) -> boolean; inRun(id) -> boolean (optional). Returns true or false, reason.
    function inv:create(a, target, isOnline, inRun)
        self:expire()
        if math.type(target) ~= 'integer' or target < 1 or target > 65535 then return false, 'invalid' end
        if target == a then return false, 'self' end
        if not isOnline(target) then return false, 'offline' end
        if inRun and (inRun(a) or inRun(target)) then return false, 'busy' end
        if involved(a) or involved(target) then return false, 'pending' end
        self.open[a] = { b = target, expires = now() + seconds * 1000 }
        return true
    end

    -- An answer from the invited player of an open invite: 'accepted' | 'declined', a. Anyone else: nil.
    function inv:answer(from, accept)
        self:expire()
        for a, o in pairs(self.open) do
            if o.b == from then
                self.open[a] = nil
                if accept == true then
                    self.pairs[a] = from
                    return 'accepted', a
                end
                return 'declined', a
            end
        end
        return nil
    end

    function inv:bOf(a)
        return self.pairs[a]
    end

    -- Player `src` leaves (key mapping or disconnect): drops every invite and pair it is part of.
    function inv:leave(src)
        local out = {}
        for a, o in pairs(self.open) do
            if a == src or o.b == src then
                out[#out + 1] = { a = a, b = o.b }
                self.open[a] = nil
            end
        end
        for a, b in pairs(self.pairs) do
            if a == src or b == src then
                out[#out + 1] = { a = a, b = b }
                self.pairs[a] = nil
            end
        end
        return out
    end

    -- Ends A's pairing (the run is over). Returns B or nil.
    function inv:release(a)
        local b = self.pairs[a]
        self.pairs[a] = nil
        return b
    end

    return inv
end

local ANSWERS = { pass = true, mismatch = true, skip = true }

-- The eye card. deps = { request(opts) -> token|nil, release(token), answer(runId, name, answer), show(msg), hide() }.
-- Every way out releases the overlay token exactly once.
function M.createEyeCard(deps)
    local card = { cur = nil, runId = nil, index = 0 }

    function card:isOpen()
        return self.cur ~= nil
    end

    function card:close()
        local c = self.cur
        if not c then return false end
        self.cur = nil
        deps.release(c.token)
        deps.hide()
        return true
    end

    -- info = { ask, expect, role } from aeterna_core:eyeAsk.
    function card:ask(runId, name, info)
        if self.cur then self:close() end
        if runId ~= self.runId then self.runId, self.index = runId, 0 end
        local token = deps.request({ overlay = true, cursor = true, keyboard = true })
        if not token then return false end
        self.index = self.index + 1
        info = type(info) == 'table' and info or {}
        self.cur = { runId = runId, name = name, token = token }
        deps.show({
            runId = runId, name = name, index = self.index, role = info.role == 'B' and 'B' or 'A',
            ask = type(info.ask) == 'string' and info.ask or name, expect = type(info.expect) == 'string' and info.expect or '',
        })
        return true
    end

    function card:answer(answer)
        local c = self.cur
        if not c or not ANSWERS[answer] then return false end
        deps.answer(c.runId, c.name, answer)
        self:close()
        return true
    end

    function card:escape()
        return self:answer('skip')
    end

    -- aeterna_core:selftestEnd for this test (no answer: core decides).
    function card:ended(runId, name)
        local c = self.cur
        if c and c.runId == runId and c.name == name then self:close() end
    end

    -- aeterna_core:focusLost for this card's own token (counted as no answer).
    function card:lost(token)
        local c = self.cur
        if c and c.token == token then self:close() end
    end

    return card
end

-- The now-testing strip: one line in the eye card's spot while a client test that is not `eye` (ped, client-side
-- mock or headless) and carries `expect` runs on this client.
-- It never takes focus or the cursor. deps = { show({ name, expect }), hide() }.
function M.createNowStrip(deps)
    local strip = { cur = nil }

    function strip:isShown()
        return self.cur ~= nil
    end

    local function close(self)
        if not self.cur then return end
        self.cur = nil
        deps.hide()
    end

    -- aeterna_core or this resource stopped: no selftestEnd will come.
    function strip:close()
        close(self)
    end

    -- ctx = the client-local aeterna_core:selftest context. Returns true when the strip is shown.
    function strip:started(runId, name, ctx)
        local c = type(ctx) == 'table' and ctx or {}
        if c.kind == 'eye' or type(c.expect) ~= 'string' or c.expect:match('^%s*$') then
            close(self)
            return false
        end
        -- a new strip replaces the old one in place (no hide in between)
        self.cur = { runId = runId, name = name }
        deps.show({ name = name, expect = c.expect })
        return true
    end

    -- aeterna_core:selftestEnd: hides the strip of that test only.
    function strip:ended(runId, name)
        local c = self.cur
        if c and c.runId == runId and c.name == name then close(self) end
    end

    return strip
end

-- Console arguments: `--json`, `--only <name or prefix>`.
function M.parseArgs(args)
    local out = { json = false }
    local i = 1
    while args and args[i] ~= nil do
        local a = tostring(args[i])
        if a == '--json' then
            out.json = true
        elseif a == '--only' and args[i + 1] ~= nil then
            local v = tostring(args[i + 1])
            if #v >= 1 and #v <= 96 then out.only = v end
            i = i + 1
        end
        i = i + 1
    end
    return out
end

-- At most `n` UTF-8 codepoints (each visible character is at least one codepoint).
local function cut(s, n)
    s = tostring(s or '')
    if (utf8.len(s) or #s) <= n then return s end
    local stop = utf8.offset(s, n + 1)
    return stop and s:sub(1, stop - 1) or s
end
M.cut = cut

local STATE_ICON = { PASS = 'check', FAIL = 'x', MISSING = 'alert-triangle', GAP = 'clock', SKIP = 'minus', MOCK = 'info' }

-- uikit item id for a suite: 's_' + suite name, within the id rule (≤ 32, [%w_-]).
function M.suiteId(suite)
    return ('s_' .. tostring(suite):gsub('[^%w_%-]', '_')):sub(1, 32)
end

function M.countsLine(c)
    c = c or {}
    return string.format('PASS %d · FAIL %d · SKIP %d · GAP %d · MOCK %d · MISSING %d', c.PASS or 0, c.FAIL or 0,
        c.SKIP or 0, c.GAP or 0, c.MOCK or 0, c.MISSING or 0)
end

-- The main menu (uikit `lg`). view = { versions, gate = 'on'|'off'|nil, bId, note, running, mine, done, total,
-- counts, suites = { { suite, meta, state } }, busy = { phase, since }|nil, hasReport }; t = translate(key, vars).
function M.menuSpec(view, t)
    local head = { view.versions ~= '' and view.versions or nil }
    if view.gate then head[#head + 1] = t('testkit.gate.' .. view.gate) end
    head[#head + 1] = view.bId and t('testkit.b.ready', { id = view.bId }) or t('testkit.b.none')
    if view.note then head[#head + 1] = view.note end

    local items = {}
    for i = 1, math.min(#(view.suites or {}), 50) do
        local s = view.suites[i]
        items[#items + 1] = { id = M.suiteId(s.suite), label = cut(s.suite, 60), meta = cut(s.meta, 30),
            icon = STATE_ICON[s.state] }
    end

    local buttons = {
        { id = 'run', label = cut(t('testkit.menu.run'), 24), variant = 'primary', disabled = view.running == true },
        { id = 'invite', label = cut(t('testkit.menu.invite'), 24), variant = 'secondary', disabled = view.running == true },
    }
    if view.running and view.mine then
        buttons[#buttons + 1] = { id = 'cancel', label = cut(t('testkit.menu.cancel'), 24), variant = 'danger' }
    end
    if view.hasReport and not view.running then
        buttons[#buttons + 1] = { id = 'report', label = cut(t('testkit.menu.report'), 24), variant = 'secondary' }
    end

    local total = tonumber(view.total) or 0
    local blocks = {
        { id = 'head', type = 'text', label = cut(table.concat(head, ' · '), 400) },
        { id = 'progress', type = 'progress',
            label = cut(view.running and string.format('%d / %d', view.done or 0, total) or t('testkit.idle'), 40),
            value = (view.running and total > 0) and math.min(1, (view.done or 0) / total) or 0 },
        { id = 'counts', type = 'text', label = M.countsLine(view.counts) },
        { id = 'suites', type = 'list', items = items },
    }
    if view.busy then
        blocks[#blocks + 1] = { id = 'busy', type = 'text',
            label = cut(t('testkit.busy', { phase = view.busy.phase, since = view.busy.since }), 400) }
    end
    blocks[#blocks + 1] = { id = 'act', type = 'buttons', items = buttons }
    return { title = cut(t('testkit.menu.title'), 60), size = 'lg', blocks = blocks }
end

-- The update patch for an open menu built from the same view (same blocks, new labels, values and items).
function M.menuPatch(spec)
    local patch = {}
    for _, b in ipairs(spec.blocks) do
        if b.type == 'text' then
            patch[b.id] = { label = b.label }
        elseif b.type == 'progress' then
            patch[b.id] = { label = b.label, value = b.value }
        else
            patch[b.id] = { items = b.items }
        end
    end
    return { blocks = patch }
end

function M.hasBlock(spec, id)
    for _, b in ipairs(spec.blocks) do
        if b.id == id then return true end
    end
    return false
end

-- One suite's tests (uikit `md`): a list with the state, then one line per row that has something to say.
function M.suiteSpec(suite, rows, shortName)
    local items, lines = {}, {}
    for i = 1, math.min(#rows, 50) do
        local r = rows[i]
        items[#items + 1] = { id = 't' .. i, label = cut(shortName(r.name), 60), meta = cut(r.state, 30),
            icon = STATE_ICON[r.state] }
        if r.state ~= 'PASS' and #lines < 36 then
            local parts = { shortName(r.name), r.state }
            if r.state == 'FAIL' and r.step ~= nil then parts[#parts + 1] = 'step ' .. tostring(r.step) end
            if r.state == 'FAIL' and r.expected ~= nil then parts[#parts + 1] = 'expected ' .. tostring(r.expected) end
            if type(r.detail) == 'string' and r.detail ~= '' then parts[#parts + 1] = r.detail end
            lines[#lines + 1] = { id = 'd' .. i, type = 'text', label = cut(table.concat(parts, ' · '), 400) }
        end
    end
    local blocks = { { id = 'tests', type = 'list', items = items } }
    for _, l in ipairs(lines) do blocks[#blocks + 1] = l end
    return { title = cut(suite, 60), size = 'md', blocks = blocks }
end

TestkitLogic.menu = M
return M
