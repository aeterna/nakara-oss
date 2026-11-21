-- Pure logic for aeterna_notify 0.2 action presses: payload check and the server's record of open action toasts.
-- Natives-free so busted can load it.

NotifyLogic = NotifyLogic or {}
local L = NotifyLogic

L.ACTION_TOAST_MAX = 8
L.ACTION_GRACE_MS = 2000

-- `aeterna_notify:sv:action` and the NUI `toastAction` callback: { toastId: string <= 24, action: string <= 32 }.
function L.validateActionPress(payload)
    if type(payload) ~= 'table' then
        return false, 'payload: type'
    end
    for k in pairs(payload) do
        if k ~= 'toastId' and k ~= 'action' then
            return false, tostring(k) .. ': not allowed'
        end
    end
    if not L.isValidId(payload.toastId, 24) then
        return false, 'toastId: pattern'
    end
    if not L.isValidId(payload.action, 32) then
        return false, 'action: pattern'
    end
    return true, nil, { toastId = payload.toastId, action = payload.action }
end

-- Server side: which action toasts each player was sent. At most `max` per player (a new one replaces the oldest,
-- whose press is then refused); a press must name a sent toastId and one of its action ids, arrive no later than
-- duration + grace ms after sending, and each toastId answers at most once.
function L.createActionTracker(opts)
    local o = type(opts) == 'table' and opts or {}
    local tracker = {
        max = math.max(1, math.floor(tonumber(o.max) or L.ACTION_TOAST_MAX)),
        graceMs = math.max(0, math.floor(tonumber(o.graceMs) or L.ACTION_GRACE_MS)),
        byPlayer = {},
    }

    local function listFor(self, src, create)
        local key = tostring(src)
        local list = self.byPlayer[key]
        if not list and create then
            list = {}
            self.byPlayer[key] = list
        end
        return list
    end

    -- rec = { toastId, actions = { 'id', ... } or { { id = 'id' }, ... }, duration, owner }
    function tracker:track(src, rec, now)
        if type(rec) ~= 'table' or type(rec.toastId) ~= 'string' or type(rec.actions) ~= 'table' then
            return false
        end
        local ids = {}
        for i = 1, #rec.actions do
            local a = rec.actions[i]
            local id = type(a) == 'table' and a.id or a
            if type(id) == 'string' then
                ids[id] = true
            end
        end
        local list = listFor(self, src, true)
        for i = #list, 1, -1 do
            if list[i].toastId == rec.toastId then
                table.remove(list, i)
            end
        end
        list[#list + 1] = {
            toastId = rec.toastId,
            actions = ids,
            owner = rec.owner,
            deadline = (tonumber(now) or 0) + (tonumber(rec.duration) or 0) + self.graceMs,
        }
        while #list > self.max do
            table.remove(list, 1)
        end
        return true
    end

    function tracker:press(src, toastId, action, now)
        local list = listFor(self, src, false)
        if not list then
            return false, 'unknown'
        end
        for i = 1, #list do
            local entry = list[i]
            if entry.toastId == toastId then
                if not entry.actions[action] then
                    return false, 'action'
                end
                table.remove(list, i)
                if (tonumber(now) or 0) > entry.deadline then
                    return false, 'expired'
                end
                return true, { owner = entry.owner, toastId = toastId, action = action }
            end
        end
        return false, 'unknown'
    end

    function tracker:count(src)
        local list = listFor(self, src, false)
        return list and #list or 0
    end

    function tracker:drop(src)
        self.byPlayer[tostring(src)] = nil
    end

    return tracker
end

return NotifyLogic
