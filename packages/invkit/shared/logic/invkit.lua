-- Pure logic for aeterna_invkit: stash id resolution, 3D point distance check,
-- usable item definition validation and item-use state machine. Natives-free for stock Lua 5.1+.

InvkitLogic = {}
local L = InvkitLogic

local BASE36_CHARS = '0123456789abcdefghijklmnopqrstuvwxyz'

L.ASK_TIMEOUT_MS = 1000
L.DURATION_MIN_MS = 300
L.DURATION_MAX_MS = 60000
L.DONE_GRACE_MS = 250
L.USE_EXPIRE_MS = 5000

local function utf8SeqLen(b1)
    if not b1 then return 0 end
    if b1 < 128 then return 1 end
    if b1 >= 194 and b1 <= 223 then return 2 end
    if b1 >= 224 and b1 <= 239 then return 3 end
    if b1 >= 240 and b1 <= 244 then return 4 end
    return 1
end

local function isControlSeq(b1, b2, b3)
    if b1 < 32 or b1 == 127 then return true, 1 end
    if b1 == 226 and b2 == 128 and b3 then
        if (b3 >= 139 and b3 <= 143) or (b3 >= 170 and b3 <= 174) then
            return true, 3
        end
    end
    return false, 0
end

local function isThaiCombining(b1, b2, b3)
    if b1 ~= 224 then return false end
    if b2 == 184 then
        return b3 == 177 or (b3 >= 180 and b3 <= 186)
    elseif b2 == 185 then
        return b3 >= 135 and b3 <= 142
    end
    return false
end

function L.stripControlAndTrim(s)
    if type(s) ~= 'string' then return '' end
    local out = {}
    local i = 1
    local len = #s
    while i <= len do
        local b1 = s:byte(i)
        local b2 = s:byte(i + 1)
        local b3 = s:byte(i + 2)
        local isCtrl, ctrlLen = isControlSeq(b1, b2, b3)
        if isCtrl then
            i = i + ctrlLen
        else
            local seqLen = utf8SeqLen(b1)
            if i + seqLen - 1 > len then break end
            out[#out + 1] = s:sub(i, i + seqLen - 1)
            i = i + seqLen
        end
    end
    local joined = table.concat(out)
    return joined:match('^%s*(.-)%s*$') or ''
end

function L.textCut(s, maxVisible)
    if AeternaCore and AeternaCore.text and type(AeternaCore.text.cut) == 'function' then
        return AeternaCore.text.cut(s, maxVisible)
    end
    if type(s) ~= 'string' then return '' end
    if maxVisible ~= nil and maxVisible <= 0 then return '' end
    local visible = 0
    local i = 1
    local len = #s
    local lastEnd = 0
    while i <= len do
        local b1 = s:byte(i)
        local seqLen = utf8SeqLen(b1)
        if i + seqLen - 1 > len then break end
        local combining = false
        if seqLen == 3 then
            combining = isThaiCombining(b1, s:byte(i + 1), s:byte(i + 2))
        end
        if combining then
            if visible > 0 then
                lastEnd = i + seqLen - 1
            end
            i = i + seqLen
        else
            if maxVisible ~= nil and visible >= maxVisible then
                break
            end
            visible = visible + 1
            lastEnd = i + seqLen - 1
            i = i + seqLen
        end
    end
    if lastEnd == 0 then return '' end
    return s:sub(1, lastEnd)
end

function L.textClean(s, maxLen)
    if AeternaCore and AeternaCore.text and type(AeternaCore.text.clean) == 'function' then
        return AeternaCore.text.clean(s, maxLen)
    end
    local stripped = L.stripControlAndTrim(s)
    if maxLen ~= nil then
        return L.textCut(stripped, maxLen)
    end
    return stripped
end

function L.isValidId(id, maxLen)
    local limit = maxLen or 32
    if type(id) ~= 'string' then return false end
    if #id < 1 or #id > limit then return false end
    return id:match('^[%w_%-]+$') ~= nil
end

function L.formatUseId(counter)
    local n = math.floor(tonumber(counter) or 1)
    if n < 1 then n = 1 end
    local digits = {}
    while n > 0 do
        local rem = n % 36
        digits[#digits + 1] = BASE36_CHARS:sub(rem + 1, rem + 1)
        n = math.floor(n / 36)
    end
    local rev = {}
    for i = #digits, 1, -1 do
        rev[#rev + 1] = digits[i]
    end
    local id = 'u' .. table.concat(rev)
    if #id > 24 then
        id = id:sub(1, 24)
    end
    return id
end

--------------------------------------------------------------------------------
-- Payload schemas (aeterna_core validate format)
--------------------------------------------------------------------------------

L.DONE_SCHEMA = {
    type = 'table',
    fields = {
        useId = { type = 'string', minLen = 1, maxLen = 24, pattern = '^[%w_%-]+$' },
    },
    extra = false,
}

L.CANCEL_SCHEMA = L.DONE_SCHEMA

L.REFUSED_SCHEMA = {
    type = 'table',
    fields = {
        item = { type = 'string', minLen = 1, maxLen = 64 },
        reason = { type = 'string', minLen = 1, maxLen = 64 },
    },
    extra = false,
}

function L.validateUseIdPayload(payload)
    if AeternaCore and type(AeternaCore.validate) == 'function' then
        if type(payload) == 'table' and type(payload.useId) == 'string' and #payload.useId > 24 then
            return false, 'useId: maxLen 24', nil
        end
        return AeternaCore.validate(payload, L.DONE_SCHEMA)
    end
    if type(payload) ~= 'table' then
        return false, 'value: type', nil
    end
    for k in pairs(payload) do
        if k ~= 'useId' then
            return false, tostring(k) .. ': not allowed', nil
        end
    end
    if type(payload.useId) ~= 'string' then
        return false, 'useId: type', nil
    end
    local cleaned = L.textClean(payload.useId)
    if #cleaned < 1 or #cleaned > 24 or not cleaned:match('^[%w_%-]+$') then
        return false, 'useId: pattern', nil
    end
    return true, nil, { useId = cleaned }
end

function L.validateRefusedPayload(payload)
    if AeternaCore and type(AeternaCore.validate) == 'function' then
        if type(payload) == 'table' then
            if type(payload.item) == 'string' and #payload.item > 64 then
                return false, 'item: maxLen 64', nil
            end
            if type(payload.reason) == 'string' and #payload.reason > 64 then
                return false, 'reason: maxLen 64', nil
            end
        end
        return AeternaCore.validate(payload, L.REFUSED_SCHEMA)
    end
    if type(payload) ~= 'table' then
        return false, 'value: type', nil
    end
    for k in pairs(payload) do
        if k ~= 'item' and k ~= 'reason' then
            return false, tostring(k) .. ': not allowed', nil
        end
    end
    if type(payload.item) ~= 'string' or #payload.item > 64 then
        return false, 'item: type', nil
    end
    if type(payload.reason) ~= 'string' or #payload.reason > 64 then
        return false, 'reason: type', nil
    end
    local cleanItem = L.textClean(payload.item, 64)
    local cleanReason = L.textClean(payload.reason, 64)
    if cleanItem == '' then return false, 'item: minLen 1', nil end
    if cleanReason == '' then return false, 'reason: minLen 1', nil end
    return true, nil, { item = cleanItem, reason = cleanReason }
end

--------------------------------------------------------------------------------
-- 1. Personal stash ID resolution
--------------------------------------------------------------------------------

function L.extractLicense(val)
    if type(val) == 'string' then
        local trimmed = L.stripControlAndTrim(val)
        if trimmed == '' then return nil end
        local afterPrefix = trimmed:match('^[lL][iI][cC][eE][nN][sS][eE]2?:(.+)$')
        if afterPrefix then
            local clean = L.stripControlAndTrim(afterPrefix)
            if clean ~= '' and clean:match('^[%w_%-]+$') then
                return clean
            end
            return nil
        end
        if trimmed:find(':', 1, true) then
            return nil
        end
        if trimmed:match('^[%w_%-]+$') then
            return trimmed
        end
        return nil
    elseif type(val) == 'table' then
        for i = 1, #val do
            local entry = val[i]
            if type(entry) == 'string' then
                local lic = entry:match('^[lL][iI][cC][eE][nN][sS][eE]2?:(.+)$')
                if lic then
                    local clean = L.stripControlAndTrim(lic)
                    if clean ~= '' and clean:match('^[%w_%-]+$') then
                        return clean
                    end
                end
            end
        end
    end
    return nil
end

local function cleanIdentifierPart(val)
    if type(val) ~= 'string' then return nil end
    local trimmed = L.stripControlAndTrim(val)
    if trimmed == '' or #trimmed > 64 then return nil end
    if not trimmed:match('^[%w_%-]+$') then return nil end
    return trimmed
end

function L.stashId(scope, optsOrCitizenId, licenseArg, qbxStartedArg)
    local sc = scope
    if sc == nil then
        sc = 'character'
    end
    if sc ~= 'character' and sc ~= 'account' then
        return nil, 'scope: enum'
    end

    local citizenid = nil
    local license = nil
    local qbxStarted = false

    if type(optsOrCitizenId) == 'table' then
        citizenid = cleanIdentifierPart(optsOrCitizenId.citizenid)
        license = L.extractLicense(optsOrCitizenId.license or optsOrCitizenId.identifiers)
        if optsOrCitizenId.qbxStarted ~= nil then
            qbxStarted = optsOrCitizenId.qbxStarted == true
        elseif optsOrCitizenId.qbx ~= nil then
            qbxStarted = optsOrCitizenId.qbx == true
        else
            qbxStarted = citizenid ~= nil
        end
    else
        citizenid = cleanIdentifierPart(optsOrCitizenId)
        license = L.extractLicense(licenseArg)
        if qbxStartedArg ~= nil then
            qbxStarted = qbxStartedArg == true
        else
            qbxStarted = citizenid ~= nil
        end
    end

    if sc == 'character' then
        if qbxStarted and citizenid then
            return 'aeterna_stash:c:' .. citizenid, nil
        end
        if license then
            return 'aeterna_stash:c:' .. license, nil
        end
        return nil, 'identifier: missing'
    end

    if license then
        return 'aeterna_stash:a:' .. license, nil
    end
    return nil, 'license: missing'
end

L.buildStashId = L.stashId

--------------------------------------------------------------------------------
-- 2. Distance check for stash points
--------------------------------------------------------------------------------

local function isVec3Type(v, typeFn)
    local t = (typeFn or type)(v)
    return t == 'table' or t == 'vector3' or t == 'userdata'
end

function L.readVec3(v, typeFn)
    if v == nil or not isVec3Type(v, typeFn) then
        return nil
    end
    local x = v.x
    local y = v.y
    local z = v.z
    if type(v) == 'table' then
        if x == nil then x = v[1] end
        if y == nil then y = v[2] end
        if z == nil then z = v[3] end
    end
    if type(x) ~= 'number' or x ~= x
        or type(y) ~= 'number' or y ~= y
        or type(z) ~= 'number' or z ~= z then
        return nil
    end
    return { x = x, y = y, z = z }
end

local function extractPointCoords(pt, typeFn)
    if type(pt) ~= 'table' then
        return nil
    end
    local coords = L.readVec3(pt.coords, typeFn)
    if coords then
        return coords
    end
    return L.readVec3(pt, typeFn)
end

function L.canOpenAt(playerCoords, pointsOrConfig, anywhereArg, typeFn)
    local points = pointsOrConfig
    local anywhere = anywhereArg == true

    if type(pointsOrConfig) == 'table' and (pointsOrConfig.points ~= nil or pointsOrConfig.anywhere ~= nil) then
        points = pointsOrConfig.points
        if anywhereArg == nil then
            anywhere = pointsOrConfig.anywhere == true
        end
    end

    if anywhere then
        return true, nil
    end

    if type(points) ~= 'table' or #points == 0 then
        return false, 'invkit.stash.far'
    end

    local player = L.readVec3(playerCoords, typeFn)
    if not player then
        return false, 'invkit.stash.far'
    end

    for i = 1, #points do
        local pt = points[i]
        if type(pt) == 'table' then
            local c = extractPointCoords(pt, typeFn)
            local radius = tonumber(pt.radius) or 2.0
            if c and radius > 0 then
                local dx = player.x - c.x
                local dy = player.y - c.y
                local dz = player.z - c.z
                local distSq = dx * dx + dy * dy + dz * dz
                if distSq <= (radius * radius) then
                    return true, nil, i, math.sqrt(distSq)
                end
            end
        end
    end

    return false, 'invkit.stash.far'
end

L.checkDistance = L.canOpenAt

function L.nearestPoint(playerCoords, points, typeFn)
    local player = L.readVec3(playerCoords, typeFn)
    if not player or type(points) ~= 'table' or #points == 0 then
        return false, nil, nil
    end
    local bestIdx = nil
    local bestDistSq = nil
    for i = 1, #points do
        local pt = points[i]
        if type(pt) == 'table' then
            local c = extractPointCoords(pt, typeFn)
            local radius = tonumber(pt.radius) or 2.0
            if c and radius > 0 then
                local dx = player.x - c.x
                local dy = player.y - c.y
                local dz = player.z - c.z
                local distSq = dx * dx + dy * dy + dz * dz
                if distSq <= (radius * radius) and (bestDistSq == nil or distSq < bestDistSq) then
                    bestIdx = i
                    bestDistSq = distSq
                end
            end
        end
    end
    if bestIdx ~= nil then
        return true, points[bestIdx], math.sqrt(bestDistSq)
    end
    return false, nil, nil
end

--------------------------------------------------------------------------------
-- 3 & 4. Usable item definition validation
--------------------------------------------------------------------------------

function L.containsFunction(val, seen)
    local t = type(val)
    if t == 'function' or t == 'thread' or t == 'userdata' then
        return true
    end
    if t ~= 'table' then
        return false
    end
    seen = seen or {}
    if seen[val] then
        return false
    end
    seen[val] = true
    for k, v in pairs(val) do
        if L.containsFunction(k, seen) or L.containsFunction(v, seen) then
            return true
        end
    end
    return false
end

function L.normalizeVec3(v, path, typeFn)
    if v == nil then
        return true, nil, { x = 0.0, y = 0.0, z = 0.0 }
    end
    if not isVec3Type(v, typeFn) then
        return false, path .. ': type', nil
    end
    local coords = L.readVec3(v, typeFn)
    if not coords then
        return false, path .. ': coords', nil
    end
    return true, nil, coords
end

function L.validateUsableDef(item, def)
    if not L.isValidId(item, 64) then
        return false, 'item: invalid', nil
    end
    if type(def) ~= 'table' then
        return false, 'def: type', nil
    end
    if L.containsFunction(def) then
        return false, 'def: function not allowed', nil
    end

    local cleanLabel = item
    if def.label ~= nil then
        if type(def.label) ~= 'string' then
            return false, 'label: type', nil
        end
        local stripped = L.stripControlAndTrim(def.label)
        if stripped == '' then
            return false, 'label: minLen 1', nil
        end
        cleanLabel = L.textClean(def.label, 60)
    end

    local duration = def.duration
    if duration == nil then
        duration = 2000
    end
    if type(duration) ~= 'number' or duration ~= duration or math.floor(duration) ~= duration then
        return false, 'duration: integer', nil
    end
    if duration < L.DURATION_MIN_MS or duration > L.DURATION_MAX_MS then
        return false, 'duration: range 300..60000', nil
    end

    local consume = def.consume
    if consume == nil then
        consume = 1
    end
    if type(consume) ~= 'number' or consume ~= consume or math.floor(consume) ~= consume or consume < 1 then
        return false, 'consume: positive integer required', nil
    end

    local cancelable = def.cancelable
    if cancelable == nil then
        cancelable = true
    end
    if type(cancelable) ~= 'boolean' then
        return false, 'cancelable: type', nil
    end

    local ask = def.ask
    if ask == nil then
        ask = false
    end
    if type(ask) ~= 'boolean' then
        return false, 'ask: type', nil
    end

    local cleanAnim = nil
    if def.anim ~= nil then
        if type(def.anim) ~= 'table' then
            return false, 'anim: type', nil
        end
        if type(def.anim.dict) ~= 'string' then
            return false, 'anim.dict: type', nil
        end
        local dict = L.textClean(def.anim.dict, 64)
        if dict == '' then
            return false, 'anim.dict: minLen 1', nil
        end
        if type(def.anim.clip) ~= 'string' then
            return false, 'anim.clip: type', nil
        end
        local clip = L.textClean(def.anim.clip, 64)
        if clip == '' then
            return false, 'anim.clip: minLen 1', nil
        end
        local flag = def.anim.flag
        if flag == nil then
            flag = 49
        end
        if type(flag) ~= 'number' or flag ~= flag or math.floor(flag) ~= flag then
            return false, 'anim.flag: integer', nil
        end
        cleanAnim = {
            dict = dict,
            clip = clip,
            flag = flag,
        }
    end

    local cleanProp = nil
    if def.prop ~= nil then
        if type(def.prop) ~= 'table' then
            return false, 'prop: type', nil
        end
        local model = def.prop.model
        if type(model) == 'string' then
            model = L.textClean(model, 64)
            if model == '' then
                return false, 'prop.model: minLen 1', nil
            end
        elseif type(model) ~= 'number' or model ~= model or math.floor(model) ~= model then
            return false, 'prop.model: type', nil
        end
        local bone = def.prop.bone
        if bone == nil then
            bone = 60309
        end
        if type(bone) ~= 'number' or bone ~= bone or math.floor(bone) ~= bone then
            return false, 'prop.bone: integer', nil
        end
        local okPos, errPos, pos = L.normalizeVec3(def.prop.pos, 'prop.pos')
        if not okPos then return false, errPos, nil end
        local okRot, errRot, rot = L.normalizeVec3(def.prop.rot, 'prop.rot')
        if not okRot then return false, errRot, nil end
        cleanProp = {
            model = model,
            bone = bone,
            pos = pos,
            rot = rot,
        }
    end

    return true, nil, {
        label = cleanLabel,
        duration = duration,
        anim = cleanAnim,
        prop = cleanProp,
        consume = consume,
        cancelable = cancelable,
        ask = ask,
    }
end

--------------------------------------------------------------------------------
-- 3, 4 & 5. Item-use state machine
--------------------------------------------------------------------------------

function L.createUseManager(opts)
    opts = opts or {}
    local internalClock = 0
    local nowFn = opts.now or function()
        if type(GetGameTimer) == 'function' then
            return GetGameTimer()
        end
        return internalClock
    end
    local onAsk = opts.onAsk
    local onStartClient = opts.onStartClient
    local onRefused = opts.onRefused
    local onUsed = opts.onUsed
    local consumeItem = opts.consumeItem

    local usables = {}         -- item -> { owner, item, def }
    local pendingBySrc = {}    -- src -> pending
    local pendingByUseId = {}  -- useId -> pending
    local seq = 0

    local mgr = {}

    local function clearPending(p)
        if not p then return end
        if pendingBySrc[p.src] == p then
            pendingBySrc[p.src] = nil
        end
        if pendingByUseId[p.useId] == p then
            pendingByUseId[p.useId] = nil
        end
    end

    local function buildClientUsePayload(p)
        return {
            useId = p.useId,
            label = p.def.label,
            duration = p.def.duration,
            anim = p.def.anim,
            prop = p.def.prop,
            cancelable = p.def.cancelable,
        }
    end

    function mgr:advance(ms)
        internalClock = internalClock + (tonumber(ms) or 0)
        self:checkTimeouts()
        return internalClock
    end

    function mgr:registerUsable(ownerOrItem, itemOrDef, maybeDef)
        local owner, item, def
        if type(itemOrDef) == 'table' and maybeDef == nil then
            owner = 'default'
            item = ownerOrItem
            def = itemOrDef
        else
            owner = ownerOrItem
            item = itemOrDef
            def = maybeDef
        end
        if type(owner) ~= 'string' or owner == '' then
            return false, 'owner: invalid'
        end
        local ok, err, cleanDef = L.validateUsableDef(item, def)
        if not ok then
            return false, err
        end
        usables[item] = {
            owner = owner,
            item = item,
            def = cleanDef,
        }
        return true, nil, usables[item]
    end

    function mgr:unregisterUsable(item, owner)
        local entry = usables[item]
        if not entry then
            return false
        end
        if owner ~= nil and entry.owner ~= owner then
            return false
        end
        usables[item] = nil
        for _, p in pairs(pendingByUseId) do
            if p.item == item and (owner == nil or p.owner == owner) then
                clearPending(p)
            end
        end
        return true
    end

    function mgr:getUsable(item)
        return usables[item]
    end

    function mgr:itemFilter()
        local filter = {}
        local count = 0
        for item in pairs(usables) do
            filter[item] = true
            count = count + 1
        end
        return filter, count
    end

    function mgr:startUse(src, item, slot)
        local playerSrc = tonumber(src)
        if not playerSrc or playerSrc <= 0 then
            return false, 'src: invalid'
        end
        local entry = usables[item]
        if not entry then
            return false, 'item: not registered'
        end

        if pendingBySrc[playerSrc] then
            if type(onRefused) == 'function' then
                onRefused(playerSrc, { item = item, reason = 'invkit.use.busy' })
            end
            return false, 'invkit.use.busy'
        end

        seq = seq + 1
        local useId = L.formatUseId(seq)
        local now = nowFn()

        local initialState = 'running'
        local initialStartedAt = now
        if entry.def.ask then
            initialState = 'asking'
            initialStartedAt = nil
        end

        local p = {
            useId = useId,
            src = playerSrc,
            owner = entry.owner,
            item = item,
            slot = slot,
            def = entry.def,
            state = initialState,
            askedAt = now,
            startedAt = initialStartedAt,
        }

        pendingBySrc[playerSrc] = p
        pendingByUseId[useId] = p

        if entry.def.ask then
            if type(onAsk) == 'function' then
                onAsk(playerSrc, {
                    owner = entry.owner,
                    item = item,
                    slot = slot,
                    useId = useId,
                })
            end
            return true, useId, 'asking'
        end

        local clPayload = buildClientUsePayload(p)
        if type(onStartClient) == 'function' then
            onStartClient(playerSrc, clPayload)
        end
        return true, useId, 'running', clPayload
    end

    mgr.start = mgr.startUse

    function mgr:expireAsk(useId)
        local p = pendingByUseId[useId]
        if not p or p.state ~= 'asking' then
            return false
        end
        clearPending(p)
        local refusedPayload = {
            item = p.item,
            reason = 'invkit.use.cancelled',
        }
        if type(onRefused) == 'function' then
            onRefused(p.src, refusedPayload)
        end
        return true, p, refusedPayload
    end

    function mgr:expireRunning(useId)
        local p = pendingByUseId[useId]
        if not p or p.state ~= 'running' or p.startedAt == nil then
            return false
        end
        clearPending(p)
        return true, p
    end

    function mgr:checkTimeouts()
        local now = nowFn()
        local toExpire = {}
        local toExpireRunning = {}
        for useId, p in pairs(pendingByUseId) do
            if p.state == 'asking' and (now - p.askedAt) >= L.ASK_TIMEOUT_MS then
                toExpire[#toExpire + 1] = useId
            elseif p.state == 'running' and p.startedAt ~= nil
                and (now - p.startedAt) >= (p.def.duration + L.USE_EXPIRE_MS) then
                toExpireRunning[#toExpireRunning + 1] = useId
            end
        end
        table.sort(toExpire)
        table.sort(toExpireRunning)
        for i = 1, #toExpire do
            self:expireAsk(toExpire[i])
        end
        for i = 1, #toExpireRunning do
            self:expireRunning(toExpireRunning[i])
        end
        return #toExpire + #toExpireRunning
    end

    function mgr:allowUse(useId, callerOwner)
        if not L.isValidId(useId, 24) then
            return false, 'useId: invalid'
        end
        local p = pendingByUseId[useId]
        if not p or p.state ~= 'asking' then
            return false, 'useId: stale'
        end
        if callerOwner ~= nil and p.owner ~= callerOwner then
            return false, 'owner: mismatch'
        end
        local now = nowFn()
        if (now - p.askedAt) >= L.ASK_TIMEOUT_MS then
            self:expireAsk(useId)
            return false, 'useId: expired'
        end
        p.state = 'running'
        p.startedAt = now
        local clPayload = buildClientUsePayload(p)
        if type(onStartClient) == 'function' then
            onStartClient(p.src, clPayload)
        end
        return true, p, clPayload
    end

    function mgr:denyUse(useId, reasonKey, callerOwner)
        if not L.isValidId(useId, 24) then
            return false, 'useId: invalid'
        end
        local p = pendingByUseId[useId]
        if not p or p.state ~= 'asking' then
            return false, 'useId: stale'
        end
        if callerOwner ~= nil and p.owner ~= callerOwner then
            return false, 'owner: mismatch'
        end
        clearPending(p)
        local reason = 'invkit.use.cancelled'
        if type(reasonKey) == 'string' then
            local cleaned = L.textClean(reasonKey, 64)
            if cleaned ~= '' then
                reason = cleaned
            end
        end
        local refusedPayload = {
            item = p.item,
            reason = reason,
        }
        if type(onRefused) == 'function' then
            onRefused(p.src, refusedPayload)
        end
        return true, p, refusedPayload
    end

    function mgr:done(src, useId)
        local playerSrc = tonumber(src)
        if not playerSrc or playerSrc <= 0 then
            return false, 'src: invalid'
        end
        if not L.isValidId(useId, 24) then
            return false, 'useId: invalid'
        end
        local p = pendingBySrc[playerSrc]
        if not p or p.useId ~= useId or p.state ~= 'running' or p.startedAt == nil then
            return false, 'use: not pending'
        end
        if not usables[p.item] or usables[p.item].owner ~= p.owner then
            clearPending(p)
            return false, 'use: owner stopped'
        end

        local now = nowFn()
        local minElapsed = p.def.duration - L.DONE_GRACE_MS
        if (now - p.startedAt) < minElapsed then
            return false, 'use: too early'
        end

        clearPending(p)

        if type(consumeItem) == 'function' then
            local okConsume = consumeItem(playerSrc, p.item, p.def.consume, p.slot)
            if not okConsume then
                return false, 'use: item missing'
            end
        end

        local usedPayload = {
            owner = p.owner,
            item = p.item,
            slot = p.slot,
            count = p.def.consume,
        }
        if type(onUsed) == 'function' then
            onUsed(playerSrc, usedPayload)
        end
        return true, usedPayload
    end

    function mgr:cancel(src, useId)
        local playerSrc = tonumber(src)
        if not playerSrc or playerSrc <= 0 then
            return false, 'src: invalid'
        end
        local p = pendingBySrc[playerSrc]
        if not p then
            return false, 'use: not pending'
        end
        if useId ~= nil and p.useId ~= useId then
            return false, 'useId: mismatch'
        end
        clearPending(p)
        return true
    end

    function mgr:removeByOwner(owner)
        if type(owner) ~= 'string' or owner == '' then return 0 end
        local removed = 0
        for item, entry in pairs(usables) do
            if entry.owner == owner then
                usables[item] = nil
                removed = removed + 1
            end
        end
        for _, p in pairs(pendingByUseId) do
            if p.owner == owner then
                clearPending(p)
            end
        end
        return removed
    end

    function mgr:removePlayer(src)
        local playerSrc = tonumber(src)
        if not playerSrc then return end
        local p = pendingBySrc[playerSrc]
        if p then
            clearPending(p)
        end
    end

    function mgr:getPending(src)
        return pendingBySrc[tonumber(src)]
    end

    function mgr:getPendingByUseId(useId)
        return pendingByUseId[useId]
    end

    return mgr
end

return L
