-- Pure Thai-aware UTF-8 text helpers for aeterna_core. No natives.

AeternaCoreLogic = AeternaCoreLogic or {}

local M = {}

local function isCont(b)
    return b ~= nil and b >= 0x80 and b <= 0xBF
end

-- Decodes one UTF-8 codepoint starting at byte index `i`.
-- Returns codepoint, nextByteIndex; for invalid/truncated sequences returns nil, i + 1.
local function decodeNext(s, i, len)
    local b1 = s:byte(i)
    if b1 <= 0x7F then
        return b1, i + 1
    elseif b1 >= 0xC2 and b1 <= 0xDF then
        if i + 1 > len then return nil, i + 1 end
        local b2 = s:byte(i + 1)
        if not isCont(b2) then return nil, i + 1 end
        return (b1 - 0xC0) * 64 + (b2 - 0x80), i + 2
    elseif b1 >= 0xE0 and b1 <= 0xEF then
        if i + 2 > len then return nil, i + 1 end
        local b2, b3 = s:byte(i + 1, i + 2)
        if not isCont(b2) or not isCont(b3) then return nil, i + 1 end
        if b1 == 0xE0 and b2 < 0xA0 then return nil, i + 1 end
        if b1 == 0xED and b2 > 0x9F then return nil, i + 1 end
        return (b1 - 0xE0) * 4096 + (b2 - 0x80) * 64 + (b3 - 0x80), i + 3
    elseif b1 >= 0xF0 and b1 <= 0xF4 then
        if i + 3 > len then return nil, i + 1 end
        local b2, b3, b4 = s:byte(i + 1, i + 3)
        if not isCont(b2) or not isCont(b3) or not isCont(b4) then return nil, i + 1 end
        if b1 == 0xF0 and b2 < 0x90 then return nil, i + 1 end
        if b1 == 0xF4 and b2 > 0x8F then return nil, i + 1 end
        return (b1 - 0xF0) * 262144 + (b2 - 0x80) * 4096 + (b3 - 0x80) * 64 + (b4 - 0x80), i + 4
    end
    return nil, i + 1
end

-- Thai combining marks (U+0E31, U+0E34-U+0E3A, U+0E47-U+0E4E) count as 0 visible characters.
function M.isCombining(cp)
    return cp == 0x0E31
        or (cp >= 0x0E34 and cp <= 0x0E3A)
        or (cp >= 0x0E47 and cp <= 0x0E4E)
end

-- Control characters: U+0000-U+001F, U+007F, U+200B-U+200F, U+202A-U+202E.
function M.isControl(cp)
    return (cp >= 0x0000 and cp <= 0x001F)
        or cp == 0x007F
        or (cp >= 0x200B and cp <= 0x200F)
        or (cp >= 0x202A and cp <= 0x202E)
end

function M.len(s)
    if type(s) ~= 'string' then
        if s == nil then return 0 end
        s = tostring(s)
    end
    local byteLen = #s
    local i = 1
    local count = 0
    while i <= byteLen do
        local cp, nextIdx = decodeNext(s, i, byteLen)
        if cp ~= nil and not M.isCombining(cp) then
            count = count + 1
        end
        i = nextIdx
    end
    return count
end

function M.cut(s, n)
    if type(s) ~= 'string' then
        if s == nil then return '' end
        s = tostring(s)
    end
    if n ~= nil and n <= 0 then
        return ''
    end
    local byteLen = #s
    local i = 1
    local count = 0
    local hasBase = false
    local out = {}
    while i <= byteLen do
        local cp, nextIdx = decodeNext(s, i, byteLen)
        if cp ~= nil then
            if M.isCombining(cp) then
                if hasBase then
                    out[#out + 1] = s:sub(i, nextIdx - 1)
                end
            else
                if n ~= nil and count >= n then
                    break
                end
                count = count + 1
                hasBase = true
                out[#out + 1] = s:sub(i, nextIdx - 1)
            end
        end
        i = nextIdx
    end
    return table.concat(out)
end

function M.clean(s, maxLen)
    if type(s) ~= 'string' then
        if s == nil then return '' end
        s = tostring(s)
    end
    local byteLen = #s
    local i = 1
    local buf = {}
    while i <= byteLen do
        local cp, nextIdx = decodeNext(s, i, byteLen)
        if cp ~= nil and not M.isControl(cp) then
            buf[#buf + 1] = s:sub(i, nextIdx - 1)
        end
        i = nextIdx
    end
    local stripped = table.concat(buf)
    local trimmed = stripped:match('^%s*(.-)%s*$') or ''
    return M.cut(trimmed, maxLen)
end

AeternaCoreLogic.text = M
return M
