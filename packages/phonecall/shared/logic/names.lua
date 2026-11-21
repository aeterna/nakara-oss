-- names.lua -- Pure logic for the names map a client sends ({ [digits] = name }, built from phonekit's contacts):
-- the server-side check, the client-side builder and labels that fall back to the number.

PhonecallNames = {}
local M = PhonecallNames

M.MAX_KEYS = 100
M.MAX_KEY_LEN = 20
M.MAX_NAME_LEN = 40

local function vlen(s)
    return utf8.len(s) or #s
end

-- Returns true, clean or false, err. The whole map is refused when any entry breaks a rule.
function M.validate(tbl)
    if type(tbl) ~= 'table' then return false, 'names: type' end
    local clean, n = {}, 0
    for k, v in pairs(tbl) do
        n = n + 1
        if n > M.MAX_KEYS then return false, 'names: more than 100 keys' end
        if type(k) ~= 'string' or #k < 1 or #k > M.MAX_KEY_LEN or not k:match('^%d+$') then
            return false, 'names: key'
        end
        if type(v) ~= 'string' or vlen(v) > M.MAX_NAME_LEN then return false, 'names: value' end
        clean[k] = v
    end
    return true, clean
end

-- The name the player saved for `number`, or the number as given.
function M.label(names, number)
    local digits = type(number) == 'string' and (number:gsub('%D', '')) or ''
    local name = type(names) == 'table' and names[digits] or nil
    if type(name) == 'string' and name ~= '' then return name end
    return number
end

local function cut(s, n)
    if vlen(s) <= n then return s end
    local stop = utf8.offset(s, n + 1)
    return stop and s:sub(1, stop - 1) or s:sub(1, n)
end

-- Client: phonekit `getContacts()` -> names map (first 100 entries with a name and digits).
function M.fromContacts(contacts)
    local out, n = {}, 0
    for _, c in ipairs(type(contacts) == 'table' and contacts or {}) do
        if n >= M.MAX_KEYS then break end
        local name = type(c) == 'table' and type(c.name) == 'string' and c.name or ''
        local digits = type(c) == 'table' and type(c.number) == 'string' and (c.number:gsub('%D', '')) or ''
        if name ~= '' and digits ~= '' and #digits <= M.MAX_KEY_LEN and out[digits] == nil then
            out[digits] = cut(name, M.MAX_NAME_LEN)
            n = n + 1
        end
    end
    return out
end

-- Client: coalesces names updates so the server's 1 / 5000 ms limit never drops one. `request(now)` returns
-- 0 (send now), a delay in ms (one trailing send is now scheduled; call `fire(now)` when it runs), or nil (a
-- trailing send is already scheduled and will carry the newest contacts).
function M.createThrottle(gapMs)
    local th = { gap = gapMs, last = nil, pending = false }
    function th:request(now)
        if self.pending then return nil end
        if self.last == nil or now - self.last >= self.gap then
            self.last = now
            return 0
        end
        self.pending = true
        return self.last + self.gap - now
    end
    function th:fire(now)
        self.pending = false
        self.last = now
    end
    return th
end

return PhonecallNames
