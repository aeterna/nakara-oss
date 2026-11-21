-- Pure logic for aeterna_invkit phone item mode (0.2): item map validation, phoneId serials, the device
-- list sent to aeterna_phonekit's open gate, deviceSave metadata merge, hook-report targets and the
-- per-player save window. Natives-free so busted can load it.

InvkitPhoneLogic = {}
local P = InvkitPhoneLogic

P.MODELS = {
    keypad = true, burner = true, qwerty = true, slab = true,
    fold = true, pro = true, book = true, pad = true,
}
P.MAX_ENTRIES = 32
P.MAX_DEVICES = 8
P.MAX_NAME_LEN = 64
P.MAX_ID_LEN = 64
P.SAVE_WINDOW_MS = 5000

local FOLDS = { open = true, closed = true }

local function isFiniteNumber(v)
    return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge
end

local function isItemName(name)
    return type(name) == 'string' and #name >= 1 and #name <= P.MAX_NAME_LEN and name:match('^[%w_%-]+$') ~= nil
end

local function copyTable(t)
    local out = {}
    if type(t) == 'table' then
        for k, v in pairs(t) do out[k] = v end
    end
    return out
end

--- Validates Config.phone.items (ox item name -> model id). Entries are taken in sorted name order so the
--- 32-entry cap is deterministic. Returns the clean map and a list of { name, reason } for skipped entries.
function P.validateItemMap(items)
    local map, skipped = {}, {}
    if type(items) ~= 'table' then
        return map, skipped
    end
    local names = {}
    for name in pairs(items) do names[#names + 1] = name end
    table.sort(names, function(a, b) return tostring(a) < tostring(b) end)

    local count = 0
    for _, name in ipairs(names) do
        local model = items[name]
        if not isItemName(name) then
            skipped[#skipped + 1] = { name = tostring(name), reason = 'name' }
        elseif type(model) ~= 'string' or not P.MODELS[model] then
            skipped[#skipped + 1] = { name = name, reason = 'model' }
        elseif count >= P.MAX_ENTRIES then
            skipped[#skipped + 1] = { name = name, reason = 'limit' }
        else
            map[name] = model
            count = count + 1
        end
    end
    return map, skipped
end

--- Sorted list of the mapped item names (for ox_inventory Search and hook item filters).
function P.itemNames(map)
    local names = {}
    for name in pairs(map or {}) do names[#names + 1] = name end
    table.sort(names)
    return names
end

--- ox_inventory itemFilter: { [name] = true }.
function P.itemFilter(map)
    local filter = {}
    for name in pairs(map or {}) do filter[name] = true end
    return filter
end

function P.isPhoneId(v)
    return type(v) == 'string' and #v >= 1 and #v <= P.MAX_ID_LEN and v:match('^[%w_%-]+$') ~= nil
end

--- A new 8-character lowercase hex serial not in `taken`. `rng` returns an integer 0..0xffffffff.
function P.newPhoneId(taken, rng)
    rng = rng or function() return math.random(0, 0xffffffff) end
    for _ = 1, 64 do
        local id = ('%08x'):format(math.floor(tonumber(rng()) or 0) % 0x100000000)
        if not taken[id] then
            return id
        end
    end
    return nil
end

--- Flattens an ox_inventory Search(src, 'slots', names) result into one list sorted by slot number.
--- With one name ox returns the slot list itself; with several, a map of name -> slot list.
function P.collectSlots(result, names)
    local out = {}
    if type(result) ~= 'table' then
        return out
    end
    local lists
    if #names == 1 then
        lists = { result }
    else
        lists = {}
        for _, list in pairs(result) do lists[#lists + 1] = list end
    end
    for _, list in ipairs(lists) do
        if type(list) == 'table' then
            for _, slot in ipairs(list) do
                if type(slot) == 'table' and tonumber(slot.slot) and type(slot.name) == 'string' then
                    out[#out + 1] = slot
                end
            end
        end
    end
    table.sort(out, function(a, b) return tonumber(a.slot) < tonumber(b.slot) end)
    return out
end

--- One device entry for phonekit's answer, with only the metadata fields phonekit accepts.
function P.deviceEntry(id, model, metadata)
    local entry = { id = id, model = model }
    local md = type(metadata) == 'table' and metadata or {}
    if isFiniteNumber(md.battery) and md.battery >= 0 and md.battery <= 100 then
        entry.battery = md.battery
    end
    if FOLDS[md.fold] then
        entry.fold = md.fold
    end
    if isFiniteNumber(md.color) and md.color >= 0 and md.color == math.floor(md.color) then
        entry.color = math.floor(md.color)
    end
    return entry
end

--- Builds phonekit's device list from the player's slots (lowest slot first).
--- Every mapped phone without a valid, unique phoneId gets a new one; those are returned in `writes`
--- as { slot, metadata } (full metadata, other fields kept) for the caller to store before answering.
--- Returns devices (at most 8, lowest slots), writes.
function P.buildDevices(slots, map, rng)
    local sorted = {}
    for _, slot in ipairs(slots or {}) do
        if type(slot) == 'table' and map[slot.name] and tonumber(slot.slot) then
            sorted[#sorted + 1] = slot
        end
    end
    table.sort(sorted, function(a, b) return tonumber(a.slot) < tonumber(b.slot) end)

    local taken = {}
    for _, slot in ipairs(sorted) do
        local id = type(slot.metadata) == 'table' and slot.metadata.phoneId or nil
        if P.isPhoneId(id) then taken[id] = (taken[id] or 0) + 1 end
    end

    local devices, writes, used = {}, {}, {}
    for _, slot in ipairs(sorted) do
        local id = type(slot.metadata) == 'table' and slot.metadata.phoneId or nil
        if not P.isPhoneId(id) or used[id] then
            id = P.newPhoneId(taken, rng)
            if id then
                taken[id] = 1
                local metadata = copyTable(slot.metadata)
                metadata.phoneId = id
                writes[#writes + 1] = { slot = tonumber(slot.slot), metadata = metadata, id = id }
            end
        end
        if id then
            used[id] = true
            if #devices < P.MAX_DEVICES then
                devices[#devices + 1] = P.deviceEntry(id, map[slot.name], slot.metadata)
            end
        end
    end
    return devices, writes
end

--- The slot of a mapped phone item whose metadata.phoneId equals `id`, or nil.
function P.findById(slots, map, id)
    for _, slot in ipairs(slots or {}) do
        if type(slot) == 'table' and map[slot.name] and type(slot.metadata) == 'table'
            and slot.metadata.phoneId == id then
            return slot
        end
    end
    return nil
end

--- Cleans a deviceSave payload: { id, battery?, fold? } with battery rounded and clamped to 0-100 and
--- fold kept only when 'open' or 'closed'. Returns nil when the id is invalid or nothing is left to write.
function P.cleanSave(data)
    if type(data) ~= 'table' or not P.isPhoneId(data.id) then
        return nil
    end
    local out = { id = data.id }
    if isFiniteNumber(data.battery) then
        local b = math.floor(data.battery + 0.5)
        if b < 0 then b = 0 elseif b > 100 then b = 100 end
        out.battery = b
    end
    if FOLDS[data.fold] then
        out.fold = data.fold
    end
    if out.battery == nil and out.fold == nil then
        return nil
    end
    return out
end

--- New metadata table: `metadata` with the save's battery and fold written, every other field kept.
function P.applySave(metadata, save)
    local out = copyTable(metadata)
    if save.battery ~= nil then out.battery = save.battery end
    if save.fold ~= nil then out.fold = save.fold end
    return out
end

local function playerId(inventory, invType)
    if invType ~= nil and invType ~= 'player' then
        return nil
    end
    local id = tonumber(inventory)
    if id and id > 0 and id == math.floor(id) then
        return id
    end
    return nil
end

--- Players to notify for an ox_inventory hook report. `event` is 'swapItems' or 'createItem'.
--- Returns a list of player server ids (no duplicates); empty when no mapped item is involved.
function P.hookTargets(event, payload, map)
    local out = {}
    if type(payload) ~= 'table' then
        return out
    end
    local mapped = false
    if event == 'swapItems' then
        local from, to = payload.fromSlot, payload.toSlot
        mapped = (type(from) == 'table' and map[from.name] ~= nil) or (type(to) == 'table' and map[to.name] ~= nil)
    elseif event == 'createItem' then
        local item = payload.item
        local name = type(item) == 'table' and item.name or item
        mapped = type(name) == 'string' and map[name] ~= nil
    end
    if not mapped then
        return out
    end

    local seen = {}
    local function add(id)
        if id and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    if event == 'swapItems' then
        add(playerId(payload.fromInventory, payload.fromType))
        add(playerId(payload.toInventory, payload.toType))
    else
        add(playerId(payload.inventoryId, nil))
    end
    return out
end

--- Per-player save window: at most one write batch per player per SAVE_WINDOW_MS. Saves that arrive
--- sooner are held, the latest per phone id wins, and the caller flushes them when the window opens.
function P.createSaveQueue(opts)
    local now = opts.now
    local window = opts.windowMs or P.SAVE_WINDOW_MS
    local q = { lastWrite = {}, held = {}, scheduled = {} }

    --- Returns 'write' (write now; the window is marked), or 'held', delayMs, firstHeld.
    --- `firstHeld` is true when the caller must schedule a flush after delayMs.
    function q:offer(src, save)
        local t = now()
        local last = self.lastWrite[src]
        if last == nil or t - last >= window then
            self.lastWrite[src] = t
            return 'write'
        end
        self.held[src] = self.held[src] or {}
        self.held[src][save.id] = save
        local first = not self.scheduled[src]
        self.scheduled[src] = true
        return 'held', window - (t - last), first
    end

    --- Takes the held saves of one player (map id -> save) and marks the window, or nil when none.
    function q:take(src)
        self.scheduled[src] = nil
        local held = self.held[src]
        self.held[src] = nil
        if not held or next(held) == nil then
            return nil
        end
        self.lastWrite[src] = now()
        return held
    end

    function q:drop(src)
        self.lastWrite[src] = nil
        self.held[src] = nil
        self.scheduled[src] = nil
    end

    return q
end

return P
