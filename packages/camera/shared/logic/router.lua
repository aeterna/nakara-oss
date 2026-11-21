-- router.lua -- aeterna_camera HTTP answers for SetHttpHandler. Only GET p/<id>.jpg with an id in the index is
-- served; everything else is 404, and more than `limit` requests in `windowMs` from one address is 429.
-- Every answer carries at least one header: writeHead(code, {}) stops FXServer b177. No natives:
-- opts = { now() ms, has(id), load(id) -> bytes|nil, limit = 60, windowMs = 10000 }.

CameraLogic = CameraLogic or {}

local Ids = CameraLogic.ids

local M = {}

local SWEEP_EVERY = 500

local function plain(status)
    return { status = status, headers = { ['Content-Type'] = 'text/plain' }, body = '' }
end

-- '1.2.3.4:5000' -> '1.2.3.4'; a bracketed IPv6 keeps its brackets; an unbracketed IPv6 stays whole.
local function addressKey(address)
    if type(address) ~= 'string' or address == '' then return '?' end
    local bracketed = address:match('^(%[[^%]]*%])')
    if bracketed then return bracketed end
    local _, colons = address:gsub(':', '')
    if colons == 1 then return (address:match('^([^:]*):')) end
    return address
end

-- Path relative to the resource ('/p/<id>.jpg'), with any query string split off first.
local function routeId(path)
    if type(path) ~= 'string' then return nil end
    path = path:match('^([^?]*)') or ''
    path = path:gsub('^/+', '')
    return path:match('^p/([^/]+)%.jpg$')
end

function M.new(opts)
    local r = {
        now = opts.now,
        has = opts.has,
        load = opts.load,
        limit = opts.limit or 60,
        windowMs = opts.windowMs or 10000,
        windows = {},
        seen = 0,
    }

    local function sweep(now)
        for key, list in pairs(r.windows) do
            if list[#list] == nil or now - list[#list] >= r.windowMs then r.windows[key] = nil end
        end
    end

    -- Sliding window per address. Returns false when this request is over the limit.
    local function admit(key, now)
        local list = r.windows[key] or {}
        local kept = {}
        for _, at in ipairs(list) do
            if now - at < r.windowMs then kept[#kept + 1] = at end
        end
        if #kept >= r.limit then
            r.windows[key] = kept
            return false
        end
        kept[#kept + 1] = now
        r.windows[key] = kept
        return true
    end

    function r:handle(req)
        req = type(req) == 'table' and req or {}
        local now = self.now()
        self.seen = self.seen + 1
        if self.seen % SWEEP_EVERY == 0 then sweep(now) end
        if not admit(addressKey(req.address), now) then return plain(429) end
        if req.method ~= 'GET' then return plain(404) end
        local id = routeId(req.path)
        if not Ids.isId(id) or not self.has(id) then return plain(404) end
        local bytes = self.load(id)
        if type(bytes) ~= 'string' or bytes == '' then return plain(404) end
        return {
            status = 200,
            headers = {
                ['Content-Type'] = 'image/jpeg',
                ['Cache-Control'] = 'private, max-age=86400',
                ['X-Content-Type-Options'] = 'nosniff',
            },
            body = bytes,
        }
    end

    return r
end

CameraLogic.router = M
return M
