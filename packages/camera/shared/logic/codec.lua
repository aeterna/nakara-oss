-- codec.lua -- aeterna_camera: base64 (RFC 4648, padded), JPEG start/end checks and the upload data check.
-- Pure Lua 5.4 (bit operators), no natives.

CameraLogic = CameraLogic or {}

local M = {}

M.PREFIX = 'data:image/jpeg;base64,'

local ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local DEC = {}
for i = 1, 64 do DEC[ALPHABET:byte(i)] = i - 1 end
local ENC = {}
for i = 1, 64 do ENC[i - 1] = ALPHABET:sub(i, i) end

local PAD = 61 -- '='
local CHUNK = 4096

local byte, char, concat = string.byte, string.char, table.concat

-- Longest accepted data string for a decoded size: base64 grows by 4/3, plus the prefix and slack.
function M.maxDataLen(maxBytes)
    return math.ceil(maxBytes * 4 / 3) + 32
end

function M.encode(bytes)
    local out, o = {}, 0
    local n = #bytes
    for i = 1, n, 3 do
        local a, b, c = byte(bytes, i, i + 2)
        local v = (a << 16) | ((b or 0) << 8) | (c or 0)
        local s = ENC[(v >> 18) & 63] .. ENC[(v >> 12) & 63]
            .. (b and ENC[(v >> 6) & 63] or '=') .. (c and ENC[v & 63] or '=')
        o = o + 1
        out[o] = s
    end
    return concat(out)
end

-- Returns the bytes, or nil and a reason. Refuses any character outside the alphabet, padding anywhere but
-- the last one or two places, and a length that is not a multiple of 4.
function M.decode(s)
    if type(s) ~= 'string' then return nil, 'type' end
    local n = #s
    if n == 0 or n % 4 ~= 0 then return nil, 'length' end
    local pad = 0
    if byte(s, n) == PAD then
        pad = byte(s, n - 1) == PAD and 2 or 1
    end
    local out, o = {}, 0
    local buf, b = {}, 0
    local last = n - 3
    for i = 1, n, 4 do
        local c1, c2, c3, c4 = byte(s, i, i + 3)
        local d1, d2, d3, d4 = DEC[c1], DEC[c2], DEC[c3], DEC[c4]
        if i == last and pad > 0 then
            d4 = 0
            if pad == 2 then d3 = 0 end
        end
        if not (d1 and d2 and d3 and d4) then return nil, 'char' end
        local v = (d1 << 18) | (d2 << 12) | (d3 << 6) | d4
        local piece
        if i == last and pad == 2 then
            piece = char(v >> 16)
        elseif i == last and pad == 1 then
            piece = char(v >> 16, (v >> 8) & 255)
        else
            piece = char(v >> 16, (v >> 8) & 255, v & 255)
        end
        b = b + 1
        buf[b] = piece
        if b >= CHUNK then
            o = o + 1
            out[o] = concat(buf, '', 1, b)
            b = 0
        end
    end
    if b > 0 then
        o = o + 1
        out[o] = concat(buf, '', 1, b)
    end
    return concat(out)
end

-- Start bytes FF D8 FF and end bytes FF D9.
function M.isJpeg(bytes)
    if type(bytes) ~= 'string' or #bytes < 5 then return false end
    local a, b, c = byte(bytes, 1, 3)
    local y, z = byte(bytes, -2, -1)
    return a == 0xFF and b == 0xD8 and c == 0xFF and y == 0xFF and z == 0xD9
end

-- Checks an uploaded data URI in the spec's order. Returns true, bytes or false, reason
-- ('type', 'too long', 'prefix', 'base64', 'not jpeg', 'too large'). The reason never carries the data.
function M.checkUpload(data, maxBytes)
    if type(data) ~= 'string' then return false, 'type' end
    if #data > M.maxDataLen(maxBytes) then return false, 'too long' end
    if data:sub(1, #M.PREFIX) ~= M.PREFIX then return false, 'prefix' end
    local bytes = M.decode(data:sub(#M.PREFIX + 1))
    if not bytes then return false, 'base64' end
    if not M.isJpeg(bytes) then return false, 'not jpeg' end
    if #bytes > maxBytes then return false, 'too large' end
    return true, bytes
end

-- A minimal JPEG built at run time for the self-tests, one marker per piece.
function M.tinyJpeg()
    return char(0xFF, 0xD8)                    -- SOI
        .. char(0xFF, 0xE0, 0x00, 0x10)        -- APP0, segment length 16
        .. 'JFIF' .. char(0x00)                -- identifier
        .. char(0x01, 0x01, 0x00)              -- version 1.1, no density unit
        .. char(0x00, 0x01, 0x00, 0x01)        -- density 1 x 1
        .. char(0x00, 0x00)                    -- no thumbnail
        .. char(0xFF, 0xD9)                    -- EOI
end

CameraLogic.codec = M
return M
