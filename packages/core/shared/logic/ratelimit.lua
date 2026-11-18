-- Pure sliding-window rate limiter for aeterna_core. No natives.

AeternaCoreLogic = AeternaCoreLogic or {}

local M = {}

function M.new(nowFn)
    local buckets = {}
    local inst = {}

    local function checkImpl(src, key, max, windowMs, explicitNow)
        if src == nil or key == nil then
            return false
        end
        if type(max) ~= 'number' or max < 1 or type(windowMs) ~= 'number' or windowMs <= 0 then
            return false
        end

        local now = explicitNow
        if type(now) ~= 'number' then
            now = nowFn and nowFn() or 0
        end

        local srcKey = tostring(src)
        local actionKey = tostring(key)
        local bySrc = buckets[srcKey]
        if not bySrc then
            bySrc = {}
            buckets[srcKey] = bySrc
        end

        local window = bySrc[actionKey]
        if not window then
            window = {}
            bySrc[actionKey] = window
        end

        local cutoff = now - windowMs
        local kept = 0
        local total = #window
        for i = 1, total do
            local ts = window[i]
            if ts > cutoff then
                kept = kept + 1
                window[kept] = ts
            end
        end
        for i = total, kept + 1, -1 do
            window[i] = nil
        end

        if kept >= max then
            return false
        end

        window[kept + 1] = now
        return true
    end

    function inst.check(a, b, c, d, e, f)
        if a == inst then
            return checkImpl(b, c, d, e, f)
        end
        return checkImpl(a, b, c, d, e)
    end

    inst.rateLimit = inst.check

    function inst.drop(a, b)
        local src = (a == inst) and b or a
        if src ~= nil then
            buckets[tostring(src)] = nil
        end
    end

    function inst.reset()
        buckets = {}
    end

    return inst
end

local defaultLimiter = M.new()

function M.check(src, key, max, windowMs, now)
    return defaultLimiter.check(src, key, max, windowMs, now)
end

M.rateLimit = M.check

function M.drop(src)
    return defaultLimiter.drop(src)
end

function M.reset()
    return defaultLimiter.reset()
end

AeternaCoreLogic.ratelimit = M
return M
