-- calls.lua -- Pure logic for aeterna_phonecall calls: the state machine (ringing -> active -> ended, the caller
-- sees `dialing` while the callee rings), busy and unavailable checks, timeouts, and the channel slot allocator.

PhonecallCalls = {}
local C = PhonecallCalls

C.REASONS = {
    hangup = true, declined = true, missed = true, busy = true, unavailable = true, dropped = true, limit = true,
    voice_off = true,
}
C.STATES = { 'dialing', 'ringing', 'active', 'ended' }

-- opts = { now = fn() -> seconds, ringSeconds, maxSeconds }
function C.create(opts)
    local o = type(opts) == 'table' and opts or {}
    local now = type(o.now) == 'function' and o.now or function() return 0 end
    local mgr = { calls = {}, byPlayer = {}, holds = {}, seq = 0,
        ringSeconds = o.ringSeconds or 30, maxSeconds = o.maxSeconds or 3600 }

    function mgr:busy(src)
        return self.byPlayer[src] ~= nil or self.holds[src] == true
    end

    -- A test hold: the player counts as in a call without one (call_busy self-test).
    function mgr:hold(src) self.holds[src] = true end
    function mgr:release(src) self.holds[src] = nil end

    -- info = { aCan, bCan, backend }. Returns the call (state `ringing`) or nil, reason.
    function mgr:dial(a, b, info)
        local i = type(info) == 'table' and info or {}
        if not i.backend then return nil, 'unavailable' end
        if b == nil or a == b then return nil, 'unavailable' end
        if self:busy(a) or self:busy(b) then return nil, 'busy' end
        if not i.aCan or not i.bCan then return nil, 'unavailable' end
        self.seq = self.seq + 1
        local call = { id = 'c' .. tostring(self.seq), from = a, to = b, state = 'ringing', startedAt = now() }
        self.calls[call.id] = call
        self.byPlayer[a] = call.id
        self.byPlayer[b] = call.id
        return call
    end

    function mgr:get(id) return self.calls[id] end

    function mgr:of(src)
        local id = self.byPlayer[src]
        return id and self.calls[id] or nil
    end

    -- What `src` sees: the caller `dialing` while the callee is `ringing`.
    function mgr:viewState(call, src)
        if call.state == 'ringing' and src == call.from then return 'dialing' end
        return call.state
    end

    -- The ringing call `src` may answer (as its callee), state unchanged; nil otherwise.
    function mgr:canAnswer(src)
        local call = self:of(src)
        if not call or call.state ~= 'ringing' or call.to ~= src then return nil end
        return call
    end

    -- The callee answers a ringing call. Returns the call or nil.
    function mgr:answer(src)
        local call = self:canAnswer(src)
        if not call then return nil end
        call.state = 'active'
        call.activeAt = now()
        return call
    end

    -- Returns the call and the end reason for `src` hanging up (or declining), or nil.
    function mgr:hangup(src)
        local call = self:of(src)
        if not call then return nil end
        if call.state == 'ringing' and src == call.to then return call, 'declined' end
        return call, 'hangup'
    end

    -- Ends the call. Returns the call, or nil for an unknown reason or a call already ended.
    function mgr:finish(call, reason)
        if type(call) ~= 'table' or call.state == 'ended' or not C.REASONS[reason] then return nil end
        call.wasActive = call.state == 'active'
        call.state = 'ended'
        call.reason = reason
        call.seconds = call.activeAt and math.max(0, math.floor(now() - call.activeAt)) or 0
        self.calls[call.id] = nil
        if self.byPlayer[call.from] == call.id then self.byPlayer[call.from] = nil end
        if self.byPlayer[call.to] == call.id then self.byPlayer[call.to] = nil end
        return call
    end

    -- Calls due to end: ringing past ringSeconds (`missed`), active past maxSeconds (`limit`).
    function mgr:expire()
        local due, t = {}, now()
        for _, call in pairs(self.calls) do
            if call.state == 'ringing' and t - call.startedAt >= self.ringSeconds then
                due[#due + 1] = { call = call, reason = 'missed' }
            elseif call.state == 'active' and t - call.activeAt >= self.maxSeconds then
                due[#due + 1] = { call = call, reason = 'limit' }
            end
        end
        table.sort(due, function(x, y) return x.call.id < y.call.id end)
        return due
    end

    function mgr:all()
        local out = {}
        for _, call in pairs(self.calls) do out[#out + 1] = call end
        table.sort(out, function(x, y) return x.id < y.id end)
        return out
    end

    return mgr
end

-- Lowest-free slot allocator 1..max (pma-voice call channels are channelBase + slot).
function C.createSlots(max)
    local s = { used = {}, max = max }
    function s:alloc()
        for n = 1, self.max do
            if not self.used[n] then
                self.used[n] = true
                return n
            end
        end
        return nil
    end
    function s:free(n)
        if n then self.used[n] = nil end
    end
    return s
end

return PhonecallCalls
