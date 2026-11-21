-- selftest.lua -- Pure decision logic for aeterna_phonecall self-tests (spec "Self-tests (0.2)"): the rows it
-- registers, what counts as a pass, and the detail text. The wrappers in server/ and client/ only gather facts.

PhonecallSelftest = {}
local T = PhonecallSelftest

local P = 'aeterna_phonecall.'

-- Exactly the rows of the spec table, in its order. `expect` is a locale key; `needsVoice` adds the pma-voice skip.
T.ROWS = {
    { name = P .. 'number_format', meta = { kind = 'headless', players = 1, destructive = false } },
    { name = P .. 'number_unique', meta = { kind = 'mock', players = 1, destructive = false } },
    { name = P .. 'sms_store_cap', meta = { kind = 'mock', players = 1, destructive = false } },
    { name = P .. 'sms_rate_limit', meta = { kind = 'headless', players = 1, destructive = false } },
    { name = P .. 'voice_detect', meta = { kind = 'headless', players = 1, destructive = false } },
    { name = P .. 'voice_channel', meta = { kind = 'headless', players = 1, destructive = false } },
    { name = P .. 'my_number', meta = { kind = 'eye', players = 1, destructive = false },
        expect = 'phonecall.selftest.my_number' },
    { name = P .. 'sms_ab', meta = { kind = 'eye', players = 2, destructive = true },
        expect = 'phonecall.selftest.sms_ab' },
    { name = P .. 'call_ab', meta = { kind = 'eye', players = 2, destructive = false },
        expect = 'phonecall.selftest.call_ab', needsVoice = true },
    { name = P .. 'call_busy', meta = { kind = 'ped', players = 2, destructive = false }, needsVoice = true },
}

-- addSelftest metas by name. t = AeternaCore.t; backendKind = 'channels' | 'pma'. On `pma` the call tests skip
-- while pma-voice is not started; on `channels` the voice backend is always there.
function T.metas(t, backendKind)
    local out = {}
    for _, row in ipairs(T.ROWS) do
        local meta = {}
        for k, v in pairs(row.meta) do meta[k] = v end
        if row.expect then meta.expect = t(row.expect) end
        if row.needsVoice and backendKind == 'pma' then meta.skipWhen = { resources = { 'pma-voice' } } end
        out[row.name] = meta
    end
    return out
end

-- number_format: the format is valid and 20 drawn numbers match it.
function T.numberFormat(N, fmt, rng)
    local ok, why = N.validateFormat(fmt)
    if not ok then return 'fail', why end
    for i = 1, 20 do
        local n = N.generate(fmt, rng)
        if not N.matches(fmt, n) then return 'fail', 'number ' .. i .. ' does not match ' .. fmt end
    end
    return 'pass', 'format ' .. fmt .. ': 20 numbers match'
end

-- number_unique: r = { a, b, ownerA, ownerB, takenRefused, restored } from the fake keys test:a and test:b.
function T.numberUnique(r)
    if type(r) ~= 'table' or type(r.a) ~= 'string' or type(r.b) ~= 'string' then
        return 'fail', 'no number assigned'
    end
    if (r.a:gsub('%D', '')) == (r.b:gsub('%D', '')) then
        return 'fail', 'both keys got the same number'
    end
    if r.ownerA ~= 'test:a' or r.ownerB ~= 'test:b' then return 'fail', 'owner index is wrong' end
    if not r.takenRefused then return 'fail', 'a taken number was accepted' end
    if not r.restored then return 'fail', 'state not restored' end
    return 'mock', 'two keys got two numbers; a taken number was refused'
end

-- sms_store_cap: r = { keep, lenA, lenB, oldestGone, restored }.
function T.smsCap(r)
    if r.lenA ~= r.keep or r.lenB ~= r.keep then
        return 'fail', ('lists hold %s and %s, expected %s'):format(tostring(r.lenA), tostring(r.lenB), r.keep)
    end
    if not r.oldestGone then return 'fail', 'the oldest message was kept' end
    if not r.restored then return 'fail', 'state not restored' end
    return 'mock', ('both lists capped at %d, oldest dropped'):format(r.keep)
end

-- sms_rate_limit: every rule allows exactly `max` calls in its window and refuses the next.
function T.smsRate(L, rl, base)
    local rules = {}
    for _, r in ipairs(L.SMS) do rules[#rules + 1] = r end
    rules[#rules + 1] = L.SMS_PAIR
    rules[#rules + 1] = L.SERVICE
    local parts = {}
    for _, r in ipairs(rules) do
        local src = tostring(base) .. ':' .. r.key
        for i = 1, r.max do
            if not rl(src, r.key, r.max, r.window) then
                return 'fail', ('%s refused call %d of %d'):format(r.key, i, r.max)
            end
        end
        if rl(src, r.key, r.max, r.window) then
            return 'fail', ('%s allowed more than %d'):format(r.key, r.max)
        end
        parts[#parts + 1] = ('%d/%d ms'):format(r.max, r.window)
    end
    return 'pass', table.concat(parts, ', ')
end

function T.voiceDetect(name)
    return 'pass', 'backend: ' .. tostring(name)
end

function T.voiceChannel(kind, ok, detail)
    if kind ~= 'channels' then return 'skip', 'backend is not channels' end
    if ok then return 'pass', detail end
    return 'fail', detail
end

-- Client side of call_ab and call_busy: what one `cl:state` means for this role. nil = keep waiting.
function T.callOutcome(test, role, st)
    if type(st) ~= 'table' then return nil end
    if st.state == 'ended' and st.reason == 'voice_off' then return 'skip', 'no voice backend' end
    if test == 'call_busy' then
        if role ~= 'A' then return nil end
        if st.state == 'ended' and st.reason == 'busy' then return 'pass', 'call ended busy' end
        if st.state == 'ended' then return 'fail', 'call ended: ' .. tostring(st.reason) end
        return 'fail', 'call was placed, expected busy'
    end
    if st.state == 'ended' then return 'fail', 'call ended: ' .. tostring(st.reason) end
    if (role == 'A' and st.state == 'dialing') or (role == 'B' and st.state == 'ringing') then
        return 'ready', st.state
    end
    return nil
end

-- Two-player tests the server sets up: A and B come from core's selftestStarted ctx and stay until selftestEnd.
T.TWO_PLAYER = { [P .. 'sms_ab'] = true, [P .. 'call_ab'] = true, [P .. 'call_busy'] = true }

function T.createTracker()
    local tr = { items = {} }
    local function key(runId, name) return tostring(runId) .. '|' .. tostring(name) end
    -- Returns { a, b } the first time a two-player test of ours starts with two different players, else nil.
    function tr:start(runId, name, ctx)
        if not T.TWO_PLAYER[name] or type(ctx) ~= 'table' then return nil end
        if ctx.a == nil or ctx.b == nil or ctx.a == ctx.b then return nil end
        local k = key(runId, name)
        if self.items[k] then return nil end
        self.items[k] = { a = ctx.a, b = ctx.b }
        return { a = ctx.a, b = ctx.b }
    end
    function tr:active(runId, name)
        return self.items[key(runId, name)] ~= nil
    end
    function tr:finish(runId, name)
        self.items[key(runId, name)] = nil
    end
    return tr
end

return PhonecallSelftest
