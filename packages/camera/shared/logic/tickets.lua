-- tickets.lua -- aeterna_camera: single-use upload tickets, one per player, bound to source and character,
-- valid ttlMs (30 s). No natives: the clock and the id generator are passed in.

CameraLogic = CameraLogic or {}

local M = {}

local TTL_MS = 30000

function M.new(opts)
    local t = {
        now = opts.now,
        newId = opts.newId,
        ttlMs = opts.ttlMs or TTL_MS,
        bySrc = {},
        byTicket = {},
    }

    local function forget(entry)
        t.byTicket[entry.ticket] = nil
        if t.bySrc[entry.src] == entry then t.bySrc[entry.src] = nil end
    end

    -- A new ticket replaces the player's old one.
    function t:issue(src, who, mode)
        local old = self.bySrc[src]
        if old then forget(old) end
        local ticket
        repeat ticket = self.newId() until not self.byTicket[ticket]
        local entry = { ticket = ticket, src = src, who = who, mode = mode, expires = self.now() + self.ttlMs }
        self.byTicket[ticket] = entry
        self.bySrc[src] = entry
        return ticket
    end

    -- Takes the ticket first, so it is gone whatever the checks say. Returns true, entry or false, reason
    -- ('unknown', 'expired', 'source', 'character').
    function t:take(ticket, src, who)
        local entry = self.byTicket[ticket]
        if not entry then return false, 'unknown' end
        forget(entry)
        if self.now() > entry.expires then return false, 'expired' end
        if entry.src ~= src then return false, 'source' end
        if entry.who ~= who then return false, 'character' end
        return true, entry
    end

    function t:peek(src)
        local entry = self.bySrc[src]
        return entry and entry.ticket or nil
    end

    function t:drop(src)
        local entry = self.bySrc[src]
        if entry then forget(entry) end
    end

    return t
end

CameraLogic.tickets = M
return M
