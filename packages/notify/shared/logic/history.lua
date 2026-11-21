-- Pure logic for aeterna_notify 0.2: the in-memory notification history read by the `history` export, and the
-- player's sound setting (client KVP aeterna_notify:settings:v1). Natives-free so busted can load it.

NotifyLogic = NotifyLogic or {}
local L = NotifyLogic

L.HISTORY_MAX = 50

local ENTRY_FIELDS = { 'id', 'owner', 'kind', 'type', 'title', 'description', 'icon', 'count', 'at' }

local function copyEntry(e)
    local out = {}
    for i = 1, #ENTRY_FIELDS do
        local k = ENTRY_FIELDS[i]
        out[k] = e[k]
    end
    return out
end

local function clampInt(v, lo, hi, default)
    local n = tonumber(v)
    if not n or n ~= n then return default end
    n = math.floor(n)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

-- Newest first. `upsert` replaces the entry of the same kind and id (a merged or replaced toast, a countdown shown
-- again at a mark) and moves it to the front; it returns a copy of the stored entry, or nil when history is off.
function L.createHistory(max)
    local h = {
        max = clampInt(max, 0, L.HISTORY_MAX, L.HISTORY_MAX),
        entries = {},
    }

    function h:upsert(entry)
        if self.max == 0 or type(entry) ~= 'table' then
            return nil
        end
        for i = 1, #self.entries do
            local e = self.entries[i]
            if e.kind == entry.kind and e.id == entry.id then
                table.remove(self.entries, i)
                break
            end
        end
        local stored = copyEntry(entry)
        table.insert(self.entries, 1, stored)
        while #self.entries > self.max do
            table.remove(self.entries)
        end
        return copyEntry(stored)
    end

    function h:list(limit)
        local n = clampInt(limit, 1, L.HISTORY_MAX, L.HISTORY_MAX)
        local out = {}
        for i = 1, math.min(n, #self.entries) do
            out[i] = copyEntry(self.entries[i])
        end
        return out
    end

    function h:clear()
        self.entries = {}
    end

    function h:count()
        return #self.entries
    end

    return h
end

function L.historyFromToast(item, at)
    return {
        id = item.historyId or item.toastId,
        owner = item.owner,
        kind = 'toast',
        type = item.type,
        title = item.title,
        description = item.description,
        icon = item.icon,
        count = item.count or 1,
        at = at,
    }
end

function L.historyFromBanner(kind, banner, owner, at)
    return {
        id = kind == 'countdown' and banner.countdownId or banner.id,
        owner = owner,
        kind = kind,
        type = 'info',
        title = banner.title,
        description = banner.body,
        icon = nil,
        count = 1,
        at = at,
    }
end

-- deps = { get() -> table|nil, set(table), playerDefault = boolean }
function L.createSettings(deps)
    local d = type(deps) == 'table' and deps or {}
    local s = {}

    function s:sound()
        local saved = type(d.get) == 'function' and d.get() or nil
        if type(saved) == 'table' and type(saved.sound) == 'boolean' then
            return saved.sound
        end
        return d.playerDefault == true
    end

    function s:setSound(on)
        local v = on == true
        if type(d.set) == 'function' then
            d.set({ sound = v })
        end
        return v
    end

    function s:toggle()
        return self:setSound(not self:sound())
    end

    return s
end

return NotifyLogic
