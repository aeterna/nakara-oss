-- Pure timezone and civil-time arithmetic for aeterna_core. No natives.

AeternaCoreLogic = AeternaCoreLogic or {}

local M = {}

function M.parseOffset(tzStr)
    if type(tzStr) ~= 'string' then
        return nil
    end
    local sign, h, m = tzStr:match('^([%+%-])(%d%d):(%d%d)$')
    if not sign then
        return nil
    end
    local hh = tonumber(h)
    local mm = tonumber(m)
    if not hh or not mm or hh < 0 or hh > 23 or mm < 0 or mm > 59 then
        return nil
    end
    local total = hh * 3600 + mm * 60
    if sign == '-' then
        return -total
    end
    return total
end

function M.parts(ts, tzStr)
    local unix = math.floor(tonumber(ts) or 0)
    local offset = M.parseOffset(tzStr or '+00:00') or 0
    local localTs = unix + offset

    local days = math.floor(localTs / 86400)
    local rem = localTs - days * 86400
    local hour = math.floor(rem / 3600)
    rem = rem - hour * 3600
    local min = math.floor(rem / 60)
    local sec = math.floor(rem - min * 60)

    -- 1970-01-01 (days = 0) was Thursday (wday = 5); 1 = Sunday ... 7 = Saturday
    local wday = ((days + 4) % 7) + 1

    local z = days + 719468
    local era = math.floor((z >= 0 and z or (z - 146096)) / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp + (mp < 10 and 3 or -9)
    if m <= 2 then
        y = y + 1
    end

    return {
        year = y,
        month = m,
        day = d,
        hour = hour,
        min = min,
        sec = sec,
        wday = wday,
    }
end

function M.format(ts, pattern, tzStr, translateFn)
    local p = M.parts(ts, tzStr)
    local pat = tostring(pattern or 'YYYY-MM-DD HH:mm:ss')
    local tFn = translateFn or function(k) return k end

    local tokens = {
        YYYY = string.format('%04d', p.year),
        MMMM = tostring(tFn('core.month.' .. tostring(p.month))),
        dddd = tostring(tFn('core.wday.' .. tostring(p.wday))),
        WWWW = tostring(tFn('core.wday.' .. tostring(p.wday))),
        MM   = string.format('%02d', p.month),
        DD   = string.format('%02d', p.day),
        HH   = string.format('%02d', p.hour),
        mm   = string.format('%02d', p.min),
        ss   = string.format('%02d', p.sec),
    }

    local out = {}
    local i = 1
    local len = #pat
    while i <= len do
        local sub4 = (i + 3 <= len) and pat:sub(i, i + 3) or nil
        local sub2 = (i + 1 <= len) and pat:sub(i, i + 1) or nil
        if sub4 and tokens[sub4] then
            out[#out + 1] = tokens[sub4]
            i = i + 4
        elseif sub2 and tokens[sub2] then
            out[#out + 1] = tokens[sub2]
            i = i + 2
        else
            out[#out + 1] = pat:sub(i, i)
            i = i + 1
        end
    end
    return table.concat(out)
end

AeternaCoreLogic.time = M
return M
