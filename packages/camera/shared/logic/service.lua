-- service.lua -- aeterna_camera server rules: viewfinder state, the shoot gate, tickets, upload checks, saving,
-- ownership and removal. Every native comes in through `deps`, so busted drives it with fakes:
--   store, tickets, newId(), now() ms, clock() s, available(), writePhoto(id, bytes) -> boolean,
--   emit(name, ...), warn(msg, fields)
-- cfg = { cooldownMs, maxBytes, perCharacter }

CameraLogic = CameraLogic or {}

local Codec = CameraLogic.codec
local Ids = CameraLogic.ids

local M = {}

local DISK_WARN_MS = 3600000
local MODES = { back = true, selfie = true }
local REASON_MAX = 64
local GALLERY_MAX = 500
local MAX_DRAWS = 8

function M.view(id, rec)
    return {
        id = id, who = rec.who, ts = rec.ts, mode = rec.mode, bytes = rec.bytes,
        path = Ids.path(id), urlPath = Ids.urlPath(id),
    }
end

-- Upload payload: exactly { ticket, data }, ticket 32 lowercase hex, data a string. Returns ok, why.
local function payloadShape(p)
    if type(p) ~= 'table' then return false, 'payload' end
    for k in pairs(p) do
        if k ~= 'ticket' and k ~= 'data' then return false, 'payload' end
    end
    if not Ids.isId(p.ticket) then return false, 'ticket' end
    if type(p.data) ~= 'string' then return false, 'data' end
    return true
end

function M.new(deps, cfg)
    local svc = { deps = deps, cfg = cfg, open = {}, lastShot = {}, lastDiskWarn = nil }

    local function refuseWarn(reason)
        if reason ~= 'camera.disk_full' then return end
        local now = deps.now()
        if svc.lastDiskWarn == nil or now - svc.lastDiskWarn >= DISK_WARN_MS then
            svc.lastDiskWarn = now
            deps.warn('photo disk cap reached', { total = deps.store:total(), cap = deps.store.maxTotalBytes })
        end
    end

    function svc:openViewfinder(src, who)
        self.open[src] = true
        return { count = deps.store:count(who), cap = cfg.perCharacter }
    end

    function svc:close(src)
        self.open[src] = nil
    end

    function svc:isOpen(src)
        return self.open[src] == true
    end

    -- true, ticket  or  false, locale key. No ticket is issued on a refusal.
    function svc:shoot(src, who, mode)
        if not self.open[src] or not MODES[mode] then return false, 'camera.failed' end
        if not deps.available() then return false, 'camera.unavailable' end
        local now = deps.now()
        local last = self.lastShot[src]
        if last and now - last < cfg.cooldownMs then return false, 'camera.slow' end
        local ok, reason = deps.store:check(who, 0)
        if not ok then
            refuseWarn(reason)
            return false, reason
        end
        self.lastShot[src] = now
        return true, deps.tickets:issue(src, who, mode)
    end

    -- Writes the file, then the index, then fires saved. Returns the photo view, or nil and a locale key.
    function svc:save(src, who, mode, bytes)
        local ok, reason = deps.store:check(who, #bytes)
        if not ok then
            refuseWarn(reason)
            return nil, reason
        end
        local id
        for _ = 1, MAX_DRAWS do
            local candidate = deps.newId()
            if not deps.store:has(candidate) then
                id = candidate
                break
            end
        end
        if not id then
            deps.warn('photo id draw failed')
            return nil, 'camera.failed'
        end
        if not deps.writePhoto(id, bytes) then
            deps.warn('photo file write failed', { id = id })
            return nil, 'camera.failed'
        end
        local rec = { who = who, ts = deps.clock(), mode = mode, bytes = #bytes }
        local added, why = deps.store:add(id, rec)
        if not added then
            deps.writePhoto(id, '')
            return nil, why
        end
        local photo = M.view(id, rec)
        deps.emit('aeterna_camera:saved', src, photo)
        return photo
    end

    -- 'saved', photo  |  'refused', locale key, detail  |  'dropped', why (no answer to the client).
    function svc:upload(src, who, payload)
        local shaped, why = payloadShape(payload)
        if not shaped then return 'dropped', why end
        local taken, entry = deps.tickets:take(payload.ticket, src, who)
        if not taken then return 'dropped', entry end
        local ok, bytesOrWhy = Codec.checkUpload(payload.data, cfg.maxBytes)
        if not ok then
            deps.warn('photo upload refused', { src = src, reason = bytesOrWhy })
            return 'refused', 'camera.failed', bytesOrWhy
        end
        local photo, key = self:save(src, who, entry.mode, bytesOrWhy)
        if not photo then return 'refused', key, key end
        return 'saved', photo
    end

    function svc:remove(id, reason)
        if not Ids.isId(id) then return false end
        local rec = deps.store:remove(id)
        if not rec then return false end
        deps.writePhoto(id, '')
        if type(reason) ~= 'string' or reason == '' then reason = 'admin' end
        local stop = utf8.offset(reason, REASON_MAX + 1)
        if stop then reason = reason:sub(1, stop - 1) end
        deps.emit('aeterna_camera:removed', id, reason)
        return true
    end

    -- Only the owner's current character may delete.
    function svc:delete(src, who, id)
        if not Ids.isId(id) then return false end
        local rec = deps.store:get(id)
        if not rec or rec.who ~= who then return false end
        return self:remove(id, 'owner')
    end

    function svc:getPhoto(id)
        if not Ids.isId(id) then return nil end
        local rec = deps.store:get(id)
        return rec and M.view(id, rec) or nil
    end

    function svc:listPhotos(who)
        local out = {}
        if type(who) ~= 'string' then return out end
        for _, id in ipairs(deps.store:list(who)) do
            local rec = deps.store:get(id)
            if rec then out[#out + 1] = M.view(id, rec) end
        end
        return out
    end

    function svc:gallery(who)
        local items = {}
        for _, p in ipairs(self:listPhotos(who)) do
            if #items >= GALLERY_MAX then break end
            items[#items + 1] = { id = p.id, ts = p.ts, mode = p.mode, bytes = p.bytes }
        end
        return items
    end

    function svc:drop(src)
        self.open[src] = nil
        self.lastShot[src] = nil
        deps.tickets:drop(src)
    end

    return svc
end

CameraLogic.service = M
return M
