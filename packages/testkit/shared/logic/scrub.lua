-- Pure report scrubbing for aeterna_testkit: player names, identifiers, IP addresses and paths. No natives.

TestkitLogic = TestkitLogic or {}

local M = {}

-- Identifier types FXServer documents for GetPlayerIdentifiers, as `<prefix>:<value>`.
-- license2 comes before license so the longer prefix is tried first.
M.PREFIXES = { 'license2', 'license', 'steam', 'fivem', 'xbl', 'live', 'ip' }

local function escapePattern(s)
    return (s:gsub('[%^%$%(%)%%%.%[%]%*%+%-%?]', '%%%0'))
end

local function isIPv4(s)
    local a, b, c, d = s:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
    if not a then return false end
    for _, part in ipairs({ a, b, c, d }) do
        if #part > 3 or tonumber(part) > 255 then return false end
    end
    return true
end

-- `fe80::1`, `::1`, eight groups, and a dotted IPv4 tail (`::ffff:10.0.0.1`).
local function isIPv6(tok)
    local body = tok
    local tail = tok:match(':([%d%.]+)$')
    if tail and tail:find('.', 1, true) then
        if not isIPv4(tail) then return false end
        body = tok:sub(1, #tok - #tail) .. '0'
    elseif tok:find('.', 1, true) then
        return false
    end
    local _, colons = body:gsub(':', '')
    local double = body:find('::', 1, true) ~= nil
    if colons < 2 or colons > 7 or (not double and colons ~= 7) then return false end
    if body:find(':::', 1, true) then return false end
    for group in (body .. ':'):gmatch('([^:]*):') do
        if #group > 4 or group:find('[^%x]') then return false end
    end
    return true
end

local function names(s, list)
    local sorted = {}
    for label, name in pairs(list or {}) do
        if type(name) == 'string' and name ~= '' then sorted[#sorted + 1] = { label = label, name = name } end
    end
    table.sort(sorted, function(x, y) return #x.name > #y.name end)
    for _, n in ipairs(sorted) do
        s = s:gsub(escapePattern(n.name), (tostring(n.label):gsub('%%', '%%%%')))
    end
    return s
end

local function identifiers(s)
    for _, prefix in ipairs(M.PREFIXES) do
        s = s:gsub('%f[%w_]' .. prefix .. ':[^%s]+', '[id]')
    end
    return s
end

local function addresses(s)
    s = s:gsub('[%x:%.]+', function(tok)
        if tok:find('::', 1, true) or select(2, tok:gsub(':', '')) >= 2 then
            if isIPv6(tok) then return '[ip]' end
        end
        return nil
    end)
    s = s:gsub('(%d+%.%d+%.%d+%.%d+):(%d+)', function(ip, port)
        if isIPv4(ip) and #port <= 5 then return '[ip]' end
        return nil
    end)
    s = s:gsub('%d+%.%d+%.%d+%.%d+', function(ip)
        if isIPv4(ip) then return '[ip]' end
        return nil
    end)
    return s
end

local function paths(s)
    s = s:gsub('%f[%a]%a:[\\/][^%s]*', '[path]')
    s = s:gsub('\\\\[^%s]+', '[path]')
    s = (' ' .. s):gsub('(%s)/[^%s/]+/[^%s/][^%s]*', '%1[path]'):sub(2)
    return s
end

local function fallbackClean(s, maxLen)
    s = s:gsub('[%c]', ''):match('^%s*(.-)%s*$')
    if (utf8.len(s) or #s) <= maxLen then return s end
    return s:sub(1, (utf8.offset(s, maxLen + 1) or (#s + 1)) - 1)
end

-- Scrubs one detail/expected string. who = { A = '<name>', B = '<name>' }; clean = AeternaCore.text.clean.
-- Order: names, identifiers, IP addresses, paths, then clean to 300.
function M.scrub(s, who, clean)
    if type(s) ~= 'string' then return nil end
    s = names(s, who)
    s = identifiers(s)
    s = addresses(s)
    s = paths(s)
    return (clean or fallbackClean)(s, 300)
end

TestkitLogic.scrub = M
return M
