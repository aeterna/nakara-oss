-- shared/logic/selftest.lua -- natives-free rules of the aeterna_invkit 0.2 self-tests
-- (docs/specs/aeterna_invkit.md § Self-tests (0.2)). Each judge returns state, detail, extra for
-- exports.aeterna_core:reportSelftest; server/selftest.lua and client/selftest.lua stay thin.
--
-- item_use, phone_two_items, phone_drop_active and phone_no_item are not registered: as the spec writes them
-- they need work the side they run on cannot do (see the package README, "Self-tests").

InvkitSelftest = InvkitSelftest or {}

local PREFIX = 'aeterna_invkit.'

-- stash_open waits this long for the presser to stand at, then away from, a stash point.
InvkitSelftest.STASH_WATCH_MS = 50000
-- phone_device_save waits this long for its save to land (invkit holds saves up to one 5000 ms window).
InvkitSelftest.SAVE_WAIT_MS = 7000

local ROWS = {
    { name = 'stash_id', kind = 'headless' },
    { name = 'use_state_machine', kind = 'headless' },
    { name = 'phone_item_map', kind = 'headless' },
    { name = 'stash_open', kind = 'ped', expect = true, timeout = 60000, needsOx = true },
    { name = 'phone_device_save', kind = 'mock', destructive = true, timeout = 15000, needsOx = true },
}

local KNOWN = {}
for _, row in ipairs(ROWS) do KNOWN[row.name] = true end

--- The registered rows in spec order: { { name, meta }, … }. `t(key)` translates the expect strings.
function InvkitSelftest.definitions(t)
    t = t or function(key) return key end
    local out = {}
    for i, row in ipairs(ROWS) do
        local meta = { kind = row.kind, players = 1, destructive = row.destructive == true }
        if row.expect then meta.expect = t('invkit.selftest.' .. row.name .. '.expect') end
        if row.timeout then meta.timeout = row.timeout end
        if row.needsOx then meta.skipWhen = { resources = { 'ox_inventory' } } end
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

--- The only reasons a row may report SKIP (the spec's "Skip when" column). env.oxStarted = ox_inventory started.
function InvkitSelftest.skipReason(name, cfg, env)
    cfg = type(cfg) == 'table' and cfg or {}
    env = type(env) == 'table' and env or {}
    local phoneOff = not (type(cfg.phone) == 'table' and cfg.phone.enabled == true)
    if name == 'phone_item_map' then
        if phoneOff then return 'Config.phone.enabled = false' end
    elseif name == 'stash_open' then
        if env.oxStarted == false then return 'needs ox_inventory' end
        local points = type(cfg.stash) == 'table' and cfg.stash.points or nil
        if type(points) ~= 'table' or #points == 0 then return 'no stash point configured' end
    elseif name == 'phone_device_save' then
        if env.oxStarted == false then return 'needs ox_inventory' end
        if phoneOff then return 'Config.phone.enabled = false' end
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

--- r = { given, item, id, metadata (of the test item after the save), gone (the test item is gone again) }.
function InvkitSelftest.deviceSaveVerdict(r)
    r = r or {}
    if not r.given then
        return 'fail', ('could not give the test phone item %s'):format(tostring(r.item)), { restored = true }
    end
    local extra = { restored = r.gone == true, wrote = true }
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

return InvkitSelftest
