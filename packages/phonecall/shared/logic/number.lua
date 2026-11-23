-- number.lua -- Pure logic for aeterna_phonecall phone numbers: the format, drawing a free number, digits-only
-- comparison and the admin format check. Natives-free so stock Lua can test it.

PhonecallNumber = {}
local N = PhonecallNumber

N.DEFAULT_FORMAT = '555-####'
N.MAX_TRIES = 50
N.MAX_LEN = 20
N.MIN_HASHES = 4

-- Digits only: '555-0142' and '5550142' are the same number.
function N.digits(s)
    if type(s) ~= 'string' then return '' end
    return (s:gsub('%D', ''))
end

function N.same(a, b)
    local da, db = N.digits(a), N.digits(b)
    return da ~= '' and da == db
end

-- `#` = a random digit, any other character literal; at least 4 `#`, at most 20 characters.
function N.validateFormat(fmt)
    if type(fmt) ~= 'string' or fmt == '' then return false, 'format: type' end
    if #fmt > N.MAX_LEN then return false, 'format: longer than 20 characters' end
    local _, hashes = fmt:gsub('#', '')
    if hashes < N.MIN_HASHES then return false, 'format: fewer than 4 #' end
    return true
end

-- rng(lo, hi) -> integer
function N.generate(fmt, rng)
    return (fmt:gsub('#', function() return tostring(rng(0, 9)) end))
end

function N.isReserved(reserved, number)
    if type(reserved) ~= 'table' then return false end
    for _, r in ipairs(reserved) do
        if N.same(r, number) then return true end
    end
    return false
end

-- opts = { rng, reserved, isTaken = fn(digits) -> boolean, tries = 50 }. Returns a number or nil.
function N.draw(fmt, opts)
    local o = type(opts) == 'table' and opts or {}
    local tries = tonumber(o.tries) or N.MAX_TRIES
    for _ = 1, tries do
        local n = N.generate(fmt, o.rng)
        if not N.isReserved(o.reserved, n) and not (type(o.isTaken) == 'function' and o.isTaken(N.digits(n))) then
            return n
        end
    end
    return nil
end

-- Exactly the format: same length, a digit for every `#`, every other character as written.
function N.matches(fmt, number)
    if type(fmt) ~= 'string' or type(number) ~= 'string' or #fmt ~= #number then return false end
    for i = 1, #fmt do
        local f, c = fmt:sub(i, i), number:sub(i, i)
        if f == '#' then
            if not c:match('%d') then return false end
        elseif f ~= c then
            return false
        end
    end
    return true
end

-- The number written in the format, from either the formatted text or its digits; nil when it does not fit.
function N.normalize(fmt, input)
    if N.matches(fmt, input) then return input end
    local d = N.digits(input)
    local want = N.digits((fmt:gsub('#', '0')))
    if d == '' or #d ~= #want then return nil end
    local out, k = {}, 0
    for i = 1, #fmt do
        local f = fmt:sub(i, i)
        if f == '#' or f:match('%d') then
            k = k + 1
            local c = d:sub(k, k)
            if f ~= '#' and c ~= f then return nil end
            out[#out + 1] = c
        else
            out[#out + 1] = f
        end
    end
    return table.concat(out)
end

return PhonecallNumber
