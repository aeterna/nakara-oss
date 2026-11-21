-- store.lua -- aeterna_camera: the photo index in server-side resource KVP and its caps.
--   aeterna_camera:photo:v1:<id>   { who, ts, mode, bytes }
--   aeterna_camera:photos:v1:<who> array of ids, newest first
--   aeterna_camera:total:v1        integer bytes of all photos
-- `kv` = { get(key), set(key, string), del(key), keys(prefix) } (GetResourceKvpString, SetResourceKvp,
-- DeleteResourceKvp, StartFindKvp/FindKvp on the server). No natives here.

CameraLogic = CameraLogic or {}

local M = {}

M.PHOTO = 'aeterna_camera:photo:v1:'
M.LIST = 'aeterna_camera:photos:v1:'
M.TOTAL = 'aeterna_camera:total:v1'

function M.new(opts)
    local kv, json = opts.kv, opts.json
    local s = {
        perCharacter = opts.perCharacter,
        maxTotalBytes = opts.maxTotalBytes,
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
    local function setTotal(n)
        n = math.max(0, math.floor(n))
        if n == 0 then
            kv.del(M.TOTAL)
        else
            kv.set(M.TOTAL, json.encode(n))
        end
    end

    local function setList(who, ids)
        if #ids == 0 then
            kv.del(M.LIST .. who)
        else
            kv.set(M.LIST .. who, json.encode(ids))
        end
    end

    -- true, or false and the locale key of the refusal.
    function s:check(who, addBytes)
        if self:count(who) >= self.perCharacter then return false, 'camera.full' end
        local total = self:total()
        if total >= self.maxTotalBytes or total + (addBytes or 0) > self.maxTotalBytes then
            return false, 'camera.disk_full'
        end
        return true
    end

    function s:add(id, rec)
        local ok, reason = self:check(rec.who, rec.bytes)
        if not ok then return false, reason end
        kv.set(M.PHOTO .. id, json.encode({ who = rec.who, ts = rec.ts, mode = rec.mode, bytes = rec.bytes }))
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
        return rec
    end

    -- At start: total must equal the sum over photo:v1:*. Returns changed, before, after.
    function s:repair()
        local sum = 0
        for _, key in ipairs(kv.keys(M.PHOTO)) do
            local rec = decode(kv.get(key))
            if validRecord(rec) and rec.bytes > 0 then sum = sum + math.floor(rec.bytes) end
        end
        local raw = decode(kv.get(M.TOTAL))
        local before = type(raw) == 'number' and raw or self:total()
        if raw == sum or (raw == nil and kv.get(M.TOTAL) == nil and sum == 0) then return false, before, sum end
        setTotal(sum)
        return true, before, sum
    end

    return s
end

CameraLogic.store = M
return M
