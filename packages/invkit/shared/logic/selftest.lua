-- shared/logic/selftest.lua -- natives-free rules of the aeterna_invkit 0.2 self-tests
-- (docs/specs/aeterna_invkit.md § Self-tests (0.2)). Each judge returns state, detail, extra for
-- exports.aeterna_core:reportSelftest; server/selftest.lua and client/selftest.lua stay thin.
-- Client tests that need server state (item_use) are prepared by the server on aeterna_core:selftestStarted and
-- torn down on the server-local aeterna_core:selftestEnd; the result still comes only from the client.

InvkitSelftest = InvkitSelftest or {}

local PREFIX = 'aeterna_invkit.'

-- stash_open moves the presser to each stop and waits this long there for the open request's answer.
InvkitSelftest.STASH_WATCH_MS = 8000
-- phone_device_save waits this long for its save to land (invkit holds saves up to one 5000 ms window).
InvkitSelftest.SAVE_WAIT_MS = 7000
-- item_use: the client waits this long for the tagged test item, then this long for the use to finish.
InvkitSelftest.ITEM_WAIT_MS = 6000
InvkitSelftest.USE_WAIT_MS = 8000
-- item_use: the server starts the use this long after giving the item, once the client listens.
InvkitSelftest.USE_START_DELAY_MS = 1500
-- The phone ped rows wait this long for the presser's inventory to match. The server gives and takes the items
-- itself (owner 2026-11-23: no manual steps); phone_drop_active takes one back after PHONE_DROP_DELAY_MS.
InvkitSelftest.PHONE_WATCH_MS = 15000
InvkitSelftest.PHONE_DROP_DELAY_MS = 4000
InvkitSelftest.PHONE_BATTERY = 100

-- item_use gives one of these ox_inventory default items, the first that no resource has registered.
InvkitSelftest.USE_ITEMS = { 'water', 'burger', 'sandwich' }
InvkitSelftest.USE_DEF = { label = 'Self-test', duration = 1500, consume = 1, cancelable = false }

local OX = { 'ox_inventory' }
local OX_PHONEKIT = { 'ox_inventory', 'aeterna_phonekit' }

local ROWS = {
    { name = 'stash_id', kind = 'headless' },
    { name = 'use_state_machine', kind = 'headless' },
    { name = 'phone_item_map', kind = 'headless' },
    { name = 'stash_open', kind = 'ped', expect = true, timeout = 30000, needs = OX },
    { name = 'item_use', kind = 'mock', side = 'client', destructive = true, timeout = 20000, needs = OX },
    { name = 'phone_two_items', kind = 'ped', destructive = true, expect = true, timeout = 25000, needs = OX_PHONEKIT },
    { name = 'phone_drop_active', kind = 'ped', destructive = true, expect = true, timeout = 25000, needs = OX_PHONEKIT },
    { name = 'phone_no_item', kind = 'ped', destructive = true, expect = true, timeout = 25000, needs = OX_PHONEKIT },
    { name = 'phone_device_save', kind = 'mock', destructive = true, timeout = 15000, needs = OX },
}

local KNOWN = {}
for _, row in ipairs(ROWS) do KNOWN[row.name] = true end

-- An item name Config.phone.items maps to `model`: one ending in '_<model>' first (the generic 'phone' maps to
-- slab too), then any, sorted; else the shipped name.
local function itemFor(items, model)
    local named, other = {}, {}
    for name, m in pairs(type(items) == 'table' and items or {}) do
        if m == model and type(name) == 'string' then
            local list = name:sub(-(#model + 1)) == '_' .. model and named or other
            list[#list + 1] = name
        end
    end
    table.sort(named)
    table.sort(other)
    return named[1] or other[1] or ('phone_' .. model)
end

--- The registered rows in spec order: { { name, meta }, … }. `t(key, vars)` translates the expect strings;
--- `cfg` (Config) names the fold and slab items in the phone_two_items instruction.
function InvkitSelftest.definitions(t, cfg)
    t = t or function(key) return key end
    local items = type(cfg) == 'table' and type(cfg.phone) == 'table' and cfg.phone.items or nil
    local vars = { fold = itemFor(items, 'fold'), slab = itemFor(items, 'slab') }
    local out = {}
    for i, row in ipairs(ROWS) do
        local meta = { kind = row.kind, players = 1, destructive = row.destructive == true }
        if row.side then meta.side = row.side end
        if row.expect then meta.expect = t('invkit.selftest.' .. row.name .. '.expect', vars) end
        if row.timeout then meta.timeout = row.timeout end
        if row.needs then meta.skipWhen = { resources = { table.unpack(row.needs) } } end
        out[i] = { name = row.name, meta = meta }
    end
    return out
end

--- 'aeterna_invkit.<name>' -> '<name>' for this package's own rows, else nil.
function InvkitSelftest.shortName(fullName)
    if type(fullName) ~= 'string' or fullName:sub(1, #PREFIX) ~= PREFIX then return nil end
    local short = fullName:sub(#PREFIX + 1)
    return KNOWN[short] and short or nil
end

local PHONE_PED = { phone_two_items = true, phone_drop_active = true, phone_no_item = true }

--- The only reasons a row may report SKIP: the spec's "Skip when" column, plus 'needs a presser' for the
--- server mock on a run nobody pressed. env = { oxStarted, phonekitStarted, presser } (false = known missing).
function InvkitSelftest.skipReason(name, cfg, env)
    cfg = type(cfg) == 'table' and cfg or {}
    env = type(env) == 'table' and env or {}
    local enabled = nil
    if type(cfg.phone) == 'table' then enabled = cfg.phone.enabled end
    local phoneOff = enabled ~= true and ('Config.phone.enabled = ' .. tostring(enabled)) or nil
    if name == 'phone_item_map' then
        return phoneOff
    elseif name == 'stash_open' then
        if env.oxStarted == false then return 'needs ox_inventory' end
        local points = type(cfg.stash) == 'table' and cfg.stash.points or nil
        if type(points) ~= 'table' or #points == 0 then return 'no stash point configured' end
    elseif name == 'item_use' then
        if env.oxStarted == false then return 'needs ox_inventory' end
    elseif PHONE_PED[name] then
        if env.oxStarted == false then return 'needs ox_inventory' end
        if env.phonekitStarted == false then return 'needs aeterna_phonekit' end
        return phoneOff
    elseif name == 'phone_device_save' then
        if env.oxStarted == false then return 'needs ox_inventory' end
        if phoneOff then return phoneOff end
        if env.presser == false then return 'needs a presser' end
    end
    return nil
end

local function firstMismatch(checks)
    for _, c in ipairs(checks) do
        if c[2] ~= c[3] then
            return ('%s: got %s, expected %s'):format(c[1], tostring(c[2]), tostring(c[3]))
        end
    end
    return nil
end

--- stash_id: both scopes, with and without qbx, and the refusals.
function InvkitSelftest.stashIdCheck(L)
    local hex = '0123456789abcdef'
    local lic = 'license:' .. hex -- the id keeps the part after 'license:'
    local bad = firstMismatch({
        { 'character with qbx', (L.stashId('character', { qbxStarted = true, citizenid = 'ABC123', license = lic })),
            'aeterna_stash:c:ABC123' },
        { 'character without qbx', (L.stashId('character', { qbxStarted = false, license = lic })),
            'aeterna_stash:c:' .. hex },
        { 'account with qbx', (L.stashId('account', { qbxStarted = true, citizenid = 'ABC123', license = lic })),
            'aeterna_stash:a:' .. hex },
        { 'account without qbx', (L.stashId('account', { qbxStarted = false, license = lic })),
            'aeterna_stash:a:' .. hex },
        { 'no identifier', (L.stashId('character', { qbxStarted = false })), nil },
        { 'unknown scope', (L.stashId('house', { qbxStarted = false, license = lic })), nil },
    })
    if bad then return 'fail', bad end
    return 'pass', 'stash ids are right for both scopes, with and without qbx'
end

--- use_state_machine: a private use manager on a fake clock (no item is touched).
function InvkitSelftest.useStateMachine(L)
    local clock, used, consumed = 0, 0, 0
    local mgr = L.createUseManager({
        now = function() return clock end,
        onStartClient = function() end,
        onRefused = function() end,
        onUsed = function() used = used + 1 end,
        consumeItem = function() consumed = consumed + 1; return true end,
    })
    local src, item = 1, 'selftest_item'
    local regOk = mgr:registerUsable('aeterna_invkit', item, { label = 'Self-test', duration = 1000 })
    local started, useId = mgr:startUse(src, item, 1)
    clock = 500
    local early = mgr:done(src, useId)
    local second = mgr:startUse(src, item, 2)
    clock = 1000
    local onTime = mgr:done(src, useId)
    local again = mgr:done(src, useId)
    local _, cancelId = mgr:startUse(src, item, 1)
    local cancelled = mgr:cancel(src, cancelId)
    local clearedOnCancel = mgr:getPending(src) == nil
    mgr:registerUsable('selftest_owner', 'selftest_other', { label = 'Other', duration = 1000 })
    mgr:startUse(src, 'selftest_other', 3)
    local removed = mgr:removeByOwner('selftest_owner')
    local bad = firstMismatch({
        { 'registerUsable', regOk, true },
        { 'start', started, true },
        { 'done too early accepted', early, false },
        { 'second start while pending', second, false },
        { 'done after duration', onTime, true },
        { 'used fired', used, 1 },
        { 'item consumed', consumed, 1 },
        { 'done twice', again, false },
        { 'cancel', cancelled, true },
        { 'pending after cancel', clearedOnCancel, true },
        { 'owner stop removed', removed, 1 },
        { 'pending after owner stop', mgr:getPending(src) == nil, true },
        { 'other owner kept', mgr:getUsable(item) ~= nil, true },
    })
    if bad then return 'fail', bad end
    return 'pass', 'start, early done, busy, done, cancel and owner stop behave as specified'
end

--- phone_item_map: the server's Config.phone.items, validated as invkit validates it at start.
function InvkitSelftest.phoneItemMap(P, items)
    local map, skipped = P.validateItemMap(items)
    if #skipped > 0 then
        local names = {}
        for i, entry in ipairs(skipped) do names[i] = ('%s (%s)'):format(entry.name, entry.reason) end
        return 'fail', 'skipped entries: ' .. table.concat(names, ', ')
    end
    local count = #P.itemNames(map)
    if count == 0 then
        return 'fail', 'Config.phone.items maps no phone item'
    end
    return 'pass', ('%d phone items mapped to phonekit models'):format(count)
end

--- stash_open: record(canOpen, outcome, reason) with canOpen = the distance rule at the presser's position
--- and outcome = 'opened' | 'refused' | 'none' after the open request. Needs one opening at a point and,
--- unless Config.stash.anywhere, one refusal away from every point.
function InvkitSelftest.newStashWatch(anywhere)
    local seen = {}
    local records = {}
    local failed = nil
    local w = {}

    local function done()
        return seen[true] == true and (anywhere or seen[false] == true)
    end

    function w.needs(canOpen)
        if failed then return false end
        if canOpen == false and anywhere then return false end
        return not seen[canOpen == true]
    end

    function w.record(canOpen, outcome, reason)
        canOpen = canOpen == true
        records[#records + 1] = { canOpen = canOpen, outcome = outcome, reason = reason }
        local step = #records
        if canOpen then
            if outcome == 'refused' then
                failed = { ('step %d: refused at a stash point (%s)'):format(step, tostring(reason)),
                    { step = step, expected = 'stash opens' } }
            elseif outcome ~= 'opened' then
                failed = { ('step %d: the stash did not open at a stash point'):format(step),
                    { step = step, expected = 'stash opens' } }
            end
        else
            if outcome == 'opened' then
                failed = { ('step %d: the stash opened away from every point'):format(step),
                    { step = step, expected = 'invkit.stash.far' } }
            elseif outcome ~= 'refused' or reason ~= 'invkit.stash.far' then
                failed = { ('step %d: no invkit.stash.far refusal away from a stash point'):format(step),
                    { step = step, expected = 'invkit.stash.far' } }
            end
        end
        seen[canOpen] = true
        return failed ~= nil or done()
    end

    function w.verdict()
        if failed then return 'fail', failed[1], failed[2] end
        if done() then
            return 'pass', anywhere and 'the stash opened (Config.stash.anywhere)'
                or 'the stash opened at a point and was refused away from it'
        end
        if not seen[true] then return 'fail', 'not checked at a stash point' end
        return 'fail', 'not checked away from a stash point'
    end

    return w
end

--- phone_device_save: the item it gives (the first mapped name, sorted), or nil when none is mapped.
function InvkitSelftest.testPhoneItem(map)
    local names = {}
    for name in pairs(map or {}) do names[#names + 1] = name end
    table.sort(names)
    return names[1]
end

InvkitSelftest.SAVE = { battery = 42, fold = 'closed' }

-- The item `map` (validated name -> model) maps to `model`, preferring one named '_<model>'; nil when none.
local function mappedItem(map, model)
    local named, other = {}, {}
    for name, m in pairs(map or {}) do
        if m == model then
            local list = name:sub(-(#model + 1)) == '_' .. model and named or other
            list[#list + 1] = name
        end
    end
    table.sort(named)
    table.sort(other)
    return named[1] or other[1]
end

--- The phone ped rows, driven by the server: { give = { { item, metadata }, … }, drop = index of the give to take
--- back after PHONE_DROP_DELAY_MS or nil, takeAway = put the presser's own phone items aside until the row ends }.
--- `newId()` returns a fresh phoneId. nil, reason when an item the row needs is not mapped.
function InvkitSelftest.phonePlan(short, map, runId, newId)
    local function give(model)
        local item = mappedItem(map, model)
        if not item then return nil, 'no phone item maps to ' .. model end
        return { item = item, metadata = { phoneId = newId(), battery = InvkitSelftest.PHONE_BATTERY,
            aeterna_selftest = runId } }
    end
    if short == 'phone_no_item' then
        return { give = {}, takeAway = true }
    end
    local models = short == 'phone_two_items' and { 'fold', 'slab' } or { 'slab', 'slab' }
    local plan = { give = {}, takeAway = false, drop = short == 'phone_drop_active' and 2 or nil }
    for i, model in ipairs(models) do
        local g, err = give(model)
        if not g then return nil, err end
        plan.give[i] = g
    end
    return plan
end

--- stash_open: where the client moves the presser — the first point, then a spot away from it — or nil when no
--- point is configured. The presser goes back where they stood afterwards. `typeFn` is type() for specs.
function InvkitSelftest.stashStops(points, typeFn)
    local pt = type(points) == 'table' and points[1] or nil
    -- a game vector3's type() is 'vector3': read it the way invkit reads its points
    local c = type(pt) == 'table' and InvkitLogic.readVec3(pt.coords, typeFn) or nil
    if not c then return nil end
    local radius = tonumber(pt.radius) or 2.0
    return {
        { x = c.x, y = c.y, z = c.z },
        { x = c.x + radius + 25.0, y = c.y, z = c.z },
    }
end

--- phone_device_save: metadata of the phone it gives. The battery is set so aeterna_phonekit does not write its
--- start battery for a new phone, a write that can land after the test's own save.
function InvkitSelftest.testPhoneMetadata(id)
    return { phoneId = id, battery = 100 }
end

--- r = { guard, given, item, id, metadata (of the test item after the save), gone (the test item count is back
--- to what it was before) }. guard = false: the write guard refused, nothing was given.
function InvkitSelftest.deviceSaveVerdict(r)
    r = r or {}
    if r.guard == false then
        return 'fail', 'the write guard refused the test write', { restored = true }
    end
    if not r.given then
        return 'fail', ('could not give the test phone item %s'):format(tostring(r.item)), { restored = true }
    end
    local extra = { restored = r.gone == true }
    local md = type(r.metadata) == 'table' and r.metadata or {}
    local bad = firstMismatch({
        { 'battery', md.battery, InvkitSelftest.SAVE.battery },
        { 'fold', md.fold, InvkitSelftest.SAVE.fold },
        { 'phoneId', md.phoneId, r.id },
    })
    if bad then
        return 'fail', 'item metadata ' .. bad, extra
    end
    if not extra.restored then
        return 'fail', 'the test phone item was not removed', extra
    end
    return 'mock', 'deviceSave wrote battery 42 and fold closed into the item; the item is removed', extra
end

--- item_use: the first test item `isTaken(name)` says no resource has registered, or nil.
function InvkitSelftest.pickUseItem(isTaken)
    for _, name in ipairs(InvkitSelftest.USE_ITEMS) do
        if not isTaken(name) then return name end
    end
    return nil
end

--- item_use, judged on the presser's client: r = { before = tagged items before the use, uses = progress bars
--- started for it, after = tagged items when the use ended }.
function InvkitSelftest.itemUseVerdict(r)
    r = r or {}
    local after = tonumber(r.after) or 0
    local extra = { restored = after == 0 }
    if (tonumber(r.before) or 0) ~= 1 then
        extra.step, extra.expected = 1, 'one test item'
        return 'fail', 'the test item never arrived', extra
    end
    if r.uses ~= 1 then
        extra.step, extra.expected = 2, 'one progress bar'
        return 'fail', ('%d progress bars ran for the test item'):format(tonumber(r.uses) or 0), extra
    end
    if after ~= 0 then
        extra.step, extra.expected = 3, 'test item removed'
        return 'fail', 'the test item was not removed after the use', extra
    end
    return 'mock', 'the item was given, its progress bar ran once and the item was removed', extra
end

--- The phone items the presser's own ox_inventory shows (the client view), lowest slot first:
--- { key, model, battery? }. key = the item's phoneId, or name@slot for a phone that has none yet, so the
--- same phone keeps the same key between two reads. Nothing is written.
function InvkitSelftest.devicesFrom(P, slots, map)
    if type(slots) ~= 'table' then return nil end
    local sorted = {}
    for _, slot in ipairs(slots) do
        if type(slot) == 'table' and map[slot.name] and tonumber(slot.slot) then sorted[#sorted + 1] = slot end
    end
    table.sort(sorted, function(a, b) return tonumber(a.slot) < tonumber(b.slot) end)
    local out = {}
    for i, slot in ipairs(sorted) do
        local md = type(slot.metadata) == 'table' and slot.metadata or {}
        local key = P.isPhoneId(md.phoneId) and md.phoneId or (slot.name .. '@' .. tostring(slot.slot))
        out[i] = { key = key, model = map[slot.name], battery = type(md.battery) == 'number' and md.battery or nil }
    end
    return out
end

local function byModel(devices, model)
    for _, d in ipairs(devices or {}) do
        if d.model == model then return d end
    end
    return nil
end

--- The three phone ped rows: observe(devices) with the current device list (nil = inventory not readable)
--- returns true once the presser's inventory shows what the row checks; verdict() gives the result.
function InvkitSelftest.newPhoneWatch(name)
    local w = {}
    local seenTwo = nil -- ids carried when two or more phones were seen
    local last = nil
    local result = nil

    function w.observe(devices)
        if type(devices) ~= 'table' then return false end
        last = devices
        if name == 'phone_two_items' then
            local fold, slab = byModel(devices, 'fold'), byModel(devices, 'slab')
            if fold and slab then
                result = ('inventory shows a fold (battery %s) and a slab (battery %s) phone item'):format(
                    tostring(fold.battery), tostring(slab.battery))
            end
        elseif name == 'phone_drop_active' then
            if #devices >= 2 then
                local now = {}
                for _, d in ipairs(devices) do now[d.key] = true end
                local dropped = false
                for key in pairs(seenTwo or {}) do
                    if not now[key] then dropped = true end
                end
                if dropped and next(now) ~= nil then
                    result = 'inventory shows one phone item gone and another still carried'
                else
                    seenTwo = now
                end
            elseif seenTwo and #devices >= 1 then
                local kept = 0
                for _, d in ipairs(devices) do if seenTwo[d.key] then kept = kept + 1 end end
                if kept == #devices then
                    result = 'inventory shows one phone item gone and another still carried'
                end
            end
        elseif name == 'phone_no_item' then
            if #devices == 0 then
                result = 'inventory shows no phone item'
            end
        end
        return result ~= nil
    end

    function w.verdict()
        if result then return 'pass', result end
        if last == nil then return 'fail', 'could not read the presser inventory' end
        if name == 'phone_two_items' then
            local missing = {}
            if not byModel(last, 'fold') then missing[#missing + 1] = 'fold' end
            if not byModel(last, 'slab') then missing[#missing + 1] = 'slab' end
            return 'fail', 'inventory shows no ' .. table.concat(missing, ' and ') .. ' phone item'
        elseif name == 'phone_drop_active' then
            if not seenTwo then return 'fail', 'inventory never showed two phones' end
            return 'fail', 'inventory never showed one phone gone while another stayed'
        end
        return 'fail', ('inventory shows %d phone items still carried'):format(#last)
    end

    return w
end

return InvkitSelftest
