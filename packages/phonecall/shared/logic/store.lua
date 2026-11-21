-- store.lua -- Pure logic for aeterna_phonecall stored lists: message delivery into both lists, the keep cap,
-- threads, read state and the call log. Lists run oldest first. Natives-free; storage comes in through `io`.

PhonecallStore = {}
local S = PhonecallStore

S.MAX_THREADS = 50
S.MAX_THREAD_MESSAGES = 50

local BASE36 = '0123456789abcdefghijklmnopqrstuvwxyz'

-- A short id (base 36), at most 12 characters.
function S.makeId(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return '0' end
    local out = ''
    while n > 0 and #out < 12 do
        local r = n % 36
        out = BASE36:sub(r + 1, r + 1) .. out
        n = n // 36
    end
    return out
end

-- text = AeternaCore.text. Control characters (newlines included) go; an empty result is refused.
function S.cleanBody(text, body, maxLen)
    if type(body) ~= 'string' then return nil, 'phonecall.sms.empty' end
    local clean = text.clean(body, maxLen)
    if clean == '' then return nil, 'phonecall.sms.empty' end
    return clean
end

-- Appends `rec` and drops the oldest past `keep`.
function S.push(list, rec, keep)
    local out = type(list) == 'table' and list or {}
    out[#out + 1] = rec
    while #out > keep do table.remove(out, 1) end
    return out
end

-- io = { load(who) -> list, save(who, list) }.
-- msg = { fromWho?, toWho, fromPeer, toPeer, body, ts, keep, idOut?, idIn, svc? }. A nil `fromWho` is a service
-- message: only the recipient gets a copy. A nil `toWho` (unknown number) stores nothing.
function S.deliver(io, msg)
    if msg.toWho == nil then return false, 'phonecall.sms.unknown' end
    local out
    if msg.fromWho ~= nil then
        out = { id = msg.idOut, peer = msg.toPeer, dir = 'out', body = msg.body, ts = msg.ts, read = true }
        io.save(msg.fromWho, S.push(io.load(msg.fromWho), out, msg.keep))
    end
    local inc = { id = msg.idIn, peer = msg.fromPeer, dir = 'in', body = msg.body, ts = msg.ts, read = false }
    if msg.svc then inc.svc = true end
    io.save(msg.toWho, S.push(io.load(msg.toWho), inc, msg.keep))
    return true, out, inc
end

local function threadKey(peer, svc)
    return (svc and 's:' or 'n:') .. tostring(peer)
end

-- Threads grouped by peer (a service label and a number are different threads), newest first, at most `max`.
-- Each: { peer, svc, last, ts, unread }.
function S.threads(list, max)
    local limit = max or S.MAX_THREADS
    local byKey, order = {}, {}
    for i, m in ipairs(list or {}) do
        local key = threadKey(m.peer, m.svc)
        local t = byKey[key]
        if not t then
            t = { peer = m.peer, svc = m.svc == true, unread = 0 }
            byKey[key] = t
            order[#order + 1] = t
        end
        t.last = m
        t.ts = m.ts
        t.seq = i
        if m.dir == 'in' and not m.read then t.unread = t.unread + 1 end
    end
    table.sort(order, function(a, b) return a.seq > b.seq end)
    local out = {}
    for i = 1, math.min(limit, #order) do
        order[i].seq = nil
        out[i] = order[i]
    end
    return out
end

-- The last `max` messages of one thread, oldest first.
function S.thread(list, peer, svc, max)
    local limit = max or S.MAX_THREAD_MESSAGES
    local key = threadKey(peer, svc)
    local all = {}
    for _, m in ipairs(list or {}) do
        if threadKey(m.peer, m.svc) == key then all[#all + 1] = m end
    end
    local out = {}
    for i = math.max(1, #all - limit + 1), #all do out[#out + 1] = all[i] end
    return out
end

-- Marks the thread's messages read. Returns how many changed.
function S.markRead(list, peer, svc)
    local key, n = threadKey(peer, svc), 0
    for _, m in ipairs(list or {}) do
        if threadKey(m.peer, m.svc) == key and not m.read then
            m.read = true
            n = n + 1
        end
    end
    return n
end

function S.unread(list)
    local n = 0
    for _, m in ipairs(list or {}) do
        if m.dir == 'in' and not m.read then n = n + 1 end
    end
    return n
end

-- trySave(list) -> boolean. Drops the oldest until a save succeeds; one warn when anything was dropped.
function S.shrinkToFit(list, trySave, warn)
    local cur = list
    local dropped = 0
    while not trySave(cur) and #cur > 0 do
        table.remove(cur, 1)
        dropped = dropped + 1
    end
    if dropped > 0 and type(warn) == 'function' then
        warn('phonecall stored list too large, dropped the oldest entries', { dropped = dropped })
    end
    return cur
end

return PhonecallStore
