-- store.lua -- aeterna_camera: the photo index in server-side resource KVP and its caps.
--   aeterna_camera:photo:v1:<id>   { who, ts, mode, bytes }
--   aeterna_camera:photos:v1:<who> array of ids, newest first
--   aeterna_camera:total:v1        integer bytes of all photos
--   aeterna_camera:acct:v1:<acct>  integer bytes of all photos of one account (all its characters)
--   aeterna_camera:free:v1         array of ids whose file is empty (a deleted photo); the next photo reuses one
-- `kv` = { get(key), set(key, string), del(key), keys(prefix) } (GetResourceKvpString, SetResourceKvp,
-- DeleteResourceKvp, StartFindKvp/FindKvp on the server). No natives here.

CameraLogic = CameraLogic or {}

local M = {}

M.PHOTO = 'aeterna_camera:photo:v1:'
M.LIST = 'aeterna_camera:photos:v1:'
M.TOTAL = 'aeterna_camera:total:v1'
M.ACCT = 'aeterna_camera:acct:v1:'
M.FREE = 'aeterna_camera:free:v1'
M.FREE_MAX = 5000

function M.new(opts)
    local kv, json = opts.kv, opts.json
    local s = {
        perCharacter = opts.perCharacter,
        maxTotalBytes = opts.maxTotalBytes,
        perAccountBytes = opts.perAccountBytes,
    }

    local function decode(raw)
        if type(raw) ~= 'string' or raw == '' then return nil end
        local ok, v = pcall(json.decode, raw)
        if ok then return v end
        return nil
    end

    local function validRecord(rec)
        return type(rec) == 'table' and type(rec.who) == 'string' and type(rec.bytes) == 'number'
    end

    function s:get(id)
        local rec = decode(kv.get(M.PHOTO .. id))
        if not validRecord(rec) then return nil end
        return rec
    end

    function s:has(id)
        return self:get(id) ~= nil
    end

    function s:list(who)
        local ids = decode(kv.get(M.LIST .. who))
        if type(ids) ~= 'table' then return {} end
        local out = {}
        for _, id in ipairs(ids) do
            if type(id) == 'string' then out[#out + 1] = id end
        end
        return out
    end

    function s:count(who)
        return #self:list(who)
    end

    function s:total()
        local v = decode(kv.get(M.TOTAL))
        if type(v) ~= 'number' or v < 0 then return 0 end
        return math.floor(v)
    end

    -- 0 is stored as no key, so an empty index leaves nothing behind.
    local function setCount(key, n)
        n = math.max(0, math.floor(n))
        if n == 0 then
            kv.del(key)
        else
            kv.set(key, json.encode(n))
        end
    end

    local function setTotal(n) setCount(M.TOTAL, n) end

    function s:accountTotal(acct)
        if type(acct) ~= 'string' or acct == '' then return 0 end
        local v = decode(kv.get(M.ACCT .. acct))
        if type(v) ~= 'number' or v < 0 then return 0 end
        return math.floor(v)
    end

    local function freeIds()
        local ids = decode(kv.get(M.FREE))
        if type(ids) ~= 'table' then return {} end
        local out = {}
        for _, id in ipairs(ids) do
            if type(id) == 'string' then out[#out + 1] = id end
        end
        return out
    end

    local function setFree(ids)
        if #ids == 0 then kv.del(M.FREE) else kv.set(M.FREE, json.encode(ids)) end
    end

    -- An id whose file is empty, taken off the free list, or nil. A taken id that is still indexed is skipped.
    function s:takeFree()
        local ids = freeIds()
        while #ids > 0 do
            local id = table.remove(ids)
            if not self:has(id) then
                setFree(ids)
                return id
            end
        end
        setFree(ids)
        return nil
    end

    -- Puts an id whose file is now empty back on the free list (at most FREE_MAX; past that the file stays unused).
    function s:giveFree(id)
        local ids = freeIds()
        if #ids >= M.FREE_MAX then return false end
        for _, x in ipairs(ids) do
            if x == id then return true end
        end
        ids[#ids + 1] = id
        setFree(ids)
        return true
    end

    local function setList(who, ids)
        if #ids == 0 then
            kv.del(M.LIST .. who)
        else
            kv.set(M.LIST .. who, json.encode(ids))
        end
    end

    -- true, or false and the locale key of the refusal.
    function s:check(who, addBytes, acct)
        if self:count(who) >= self.perCharacter then return false, 'camera.full' end
        if self.perAccountBytes and type(acct) == 'string' and acct ~= ''
            and self:accountTotal(acct) + (addBytes or 0) > self.perAccountBytes then
            return false, 'camera.full'
        end
        local total = self:total()
        if total >= self.maxTotalBytes or total + (addBytes or 0) > self.maxTotalBytes then
            return false, 'camera.disk_full'
        end
        return true
    end

    function s:add(id, rec)
        local ok, reason = self:check(rec.who, rec.bytes, rec.acct)
        if not ok then return false, reason end
        local acct = type(rec.acct) == 'string' and rec.acct ~= '' and rec.acct or nil
        kv.set(M.PHOTO .. id, json.encode({ who = rec.who, ts = rec.ts, mode = rec.mode, bytes = rec.bytes, acct = acct }))
        if acct then setCount(M.ACCT .. acct, self:accountTotal(acct) + rec.bytes) end
        local ids = self:list(rec.who)
        table.insert(ids, 1, id)
        setList(rec.who, ids)
        setTotal(self:total() + rec.bytes)
        return true
    end

    -- Removes the record, the id from its owner's list and its bytes from the total. Returns the record or nil.
    function s:remove(id)
        local rec = self:get(id)
        if not rec then return nil end
        kv.del(M.PHOTO .. id)
        local ids, kept = self:list(rec.who), {}
        for _, x in ipairs(ids) do
            if x ~= id then kept[#kept + 1] = x end
        end
        setList(rec.who, kept)
        setTotal(self:total() - rec.bytes)
        if type(rec.acct) == 'string' and rec.acct ~= '' then
            setCount(M.ACCT .. rec.acct, self:accountTotal(rec.acct) - rec.bytes)
        end
        return rec
    end

    -- At start: total and every account total must equal the sums over photo:v1:*. Returns changed, before, after
    -- (before and after are the server total).
    function s:repair()
        local sum, perAcct = 0, {}
        for _, key in ipairs(kv.keys(M.PHOTO)) do
            local rec = decode(kv.get(key))
            if validRecord(rec) and rec.bytes > 0 then
                local b = math.floor(rec.bytes)
                sum = sum + b
                if type(rec.acct) == 'string' and rec.acct ~= '' then perAcct[rec.acct] = (perAcct[rec.acct] or 0) + b end
            end
        end
        local acctChanged = false
        for _, key in ipairs(kv.keys(M.ACCT)) do
            local acct = key:sub(#M.ACCT + 1)
            if perAcct[acct] == nil then kv.del(key) acctChanged = true end
        end
        for acct, b in pairs(perAcct) do
            if decode(kv.get(M.ACCT .. acct)) ~= b then setCount(M.ACCT .. acct, b) acctChanged = true end
        end
        local raw = decode(kv.get(M.TOTAL))
        local before = type(raw) == 'number' and raw or self:total()
        if raw == sum or (raw == nil and kv.get(M.TOTAL) == nil and sum == 0) then return acctChanged, before, sum end
        setTotal(sum)
        return true, before, sum
    end

    return s
end

CameraLogic.store = M
return M
