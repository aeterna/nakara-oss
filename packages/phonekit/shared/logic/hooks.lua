-- hooks.lua -- Pure logic for aeterna_phonekit 0.2 hooks for add-ons: the contacts hook, contact intents,
-- the ring screen and canCall. Natives-free so stock Lua can test it. The contacts hook uses
-- PhoneLogic.createContactsStore (shared/logic/phone.lua, loaded first in the manifest).

HooksLogic = {}
local H = HooksLogic

local function copyContacts(list)
    local out = {}
    for i, c in ipairs(list) do
        out[i] = { id = c.id, name = c.name, number = c.number }
    end
    return out
end

--------------------------------------------------------------------------------
-- Contacts (client)
--------------------------------------------------------------------------------

-- opts = { load = fn() -> list, save = fn(list), onChange = fn(), encode = fn(tbl) -> string }
function H.createContactsHook(opts)
    local o = type(opts) == 'table' and opts or {}
    local hook = {}

    local function store()
        local initial = type(o.load) == 'function' and o.load() or {}
        return PhoneLogic.createContactsStore(type(initial) == 'table' and initial or {})
    end

    local function changed(list)
        if type(o.save) == 'function' then o.save(list) end
        if type(o.onChange) == 'function' then o.onChange() end
    end

    function hook:getContacts()
        return copyContacts(store():list())
    end

    -- Same limits as the app. Returns true or false, reasonKey.
    function hook:addContact(contact)
        if type(contact) ~= 'table' then return false, 'contact: type' end
        local st = store()
        local ok, err = st:save({ name = contact.name, number = contact.number }, o.encode)
        if not ok then return false, err end
        changed(st:list())
        return true
    end

    -- The Contacts app saved a whole list (add, edit or delete). Returns true or false, reasonKey.
    function hook:replaceAll(items)
        if type(items) ~= 'table' then return false, 'contacts: type' end
        local st = PhoneLogic.createContactsStore()
        for i = 1, #items do
            local ok, err = st:save(items[i], o.encode)
            if not ok then return false, err end
        end
        changed(st:list())
        return true, st:list()
    end

    return hook
end

--------------------------------------------------------------------------------
-- Contact intents (server)
--------------------------------------------------------------------------------

H.INTENT_KINDS = { tel = true, sms = true }

function H.createIntents(warn)
    local reg = { order = {} }

    function reg:register(owner, id, handles)
        if type(handles) ~= 'table' then return end
        for _, kind in ipairs(handles) do
            if H.INTENT_KINDS[kind] then
                local current = self:handler(kind)
                if current and not (current.owner == owner and current.id == id) and type(warn) == 'function' then
                    warn('phonekit intent already handled', { kind = kind, owner = owner, id = id,
                        handler = current.owner .. ':' .. current.id })
                end
                local exists = false
                for _, e in ipairs(self.order) do
                    if e.kind == kind and e.owner == owner and e.id == id then exists = true end
                end
                if not exists then
                    self.order[#self.order + 1] = { kind = kind, owner = owner, id = id }
                end
            end
        end
    end

    function reg:remove(owner, id)
        for i = #self.order, 1, -1 do
            local e = self.order[i]
            if e.owner == owner and (id == nil or e.id == id) then table.remove(self.order, i) end
        end
    end

    function reg:removeOwner(owner)
        self:remove(owner, nil)
    end

    -- The first registered app that handles `kind`.
    function reg:handler(kind)
        for _, e in ipairs(self.order) do
            if e.kind == kind then return { owner = e.owner, id = e.id } end
        end
        return nil
    end

    function reg:isHandler(kind, owner, id)
        local h = self:handler(kind)
        return h ~= nil and h.owner == owner and h.id == id
    end

    function reg:route(kind, number)
        local h = self:handler(kind)
        if not h then return nil end
        return { owner = h.owner, id = h.id, intent = { kind = kind, number = number } }
    end

    function reg:available()
        local out = {}
        for kind in pairs(H.INTENT_KINDS) do
            out[kind] = self:handler(kind)
        end
        return out
    end

    return reg
end

--------------------------------------------------------------------------------
-- Ring screen (server)
--------------------------------------------------------------------------------

H.RING_SEC = 60

-- opts = { now = fn() -> seconds }
function H.createRingManager(opts)
    local o = type(opts) == 'table' and opts or {}
    local now = type(o.now) == 'function' and o.now or function() return 0 end
    local mgr = { rings = {}, seq = 0 }

    -- info = { owner, id, appExists, hasDevice, voice, battery, title, body }
    function mgr:ring(src, info)
        if type(info) ~= 'table' then return nil, 'noapp' end
        if not info.appExists then return nil, 'noapp' end
        if not info.hasDevice then return nil, 'nodevice' end
        if info.battery ~= nil and (tonumber(info.battery) or 0) <= 0 then return nil, 'dead' end
        if not info.voice then return nil, 'novoice' end
        if self.rings[src] then return nil, 'busy' end
        self.seq = self.seq + 1
        local ringId = 'ring_' .. tostring(self.seq)
        self.rings[src] = { ringId = ringId, owner = info.owner, id = info.id, title = info.title, body = info.body,
            at = now() }
        return ringId
    end

    function mgr:current(src)
        return self.rings[src]
    end

    function mgr:stop(src, ringId)
        local r = self.rings[src]
        if r and (ringId == nil or r.ringId == ringId) then
            self.rings[src] = nil
            return true
        end
        return false
    end

    -- Answer or Decline: the `aeterna_phonekit:action` payload, or nil for a stale ring.
    function mgr:answer(src, ringId, answer)
        local r = self.rings[src]
        if not r or r.ringId ~= ringId then return nil end
        self.rings[src] = nil
        return { owner = r.owner, id = r.id, screenId = r.ringId, action = answer and '__answer' or '__decline',
            values = {} }
    end

    -- Rings older than 60 s end by themselves. Returns { { src, ringId } }.
    function mgr:expire()
        local out, t = {}, now()
        for src, r in pairs(self.rings) do
            if t - r.at >= H.RING_SEC then
                out[#out + 1] = { src = src, ringId = r.ringId }
                self.rings[src] = nil
            end
        end
        table.sort(out, function(a, b) return tostring(a.src) < tostring(b.src) end)
        return out
    end

    function mgr:removeOwner(owner)
        for src, r in pairs(self.rings) do
            if r.owner == owner then self.rings[src] = nil end
        end
    end

    return mgr
end

-- false for a pad, a player with no phone, or a dead battery; else true. info = { hasDevice, model, battery }
function H.canCall(info)
    if type(info) ~= 'table' or not info.hasDevice then return false end
    if info.model == 'pad' then return false end
    if info.battery ~= nil and (tonumber(info.battery) or 0) <= 0 then return false end
    return true
end

return HooksLogic
