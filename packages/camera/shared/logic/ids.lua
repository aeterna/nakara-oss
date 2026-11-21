-- ids.lua -- aeterna_camera: photo ids and tickets (32 lowercase hex) and the paths built from them.
-- Ids are hard to guess, not a secret: each stream keeps its own xorshift state (seeded once at start) and mixes
-- math.random, a running counter, the game timer and os.clock into every draw. A path is only ever built from an
-- id that passed isId, so it cannot hold '/', '..' or upper case. No natives.

CameraLogic = CameraLogic or {}

local M = {}

local GOLDEN = 0x9E3779B97F4A7C15     -- wraps to a 64-bit integer
local LCG_MUL = 6364136223846793005
local LCG_ADD = 1442695040888963407

-- opts = { seed (integer), rand(lo, hi), now() (ms), clock() (s, float) }. Returns next() -> id.
function M.stream(opts)
    local state = math.tointeger(opts.seed) or 0
    state = state ~ GOLDEN
    if state == 0 then state = GOLDEN end
    local counter = 0

    local function step()
        state = state ~ (state << 13)
        state = state ~ (state >> 7)
        state = state ~ (state << 17)
        return state
    end

    return function()
        counter = counter + 1
        local timer = math.tointeger(math.floor(tonumber(opts.now()) or 0)) or 0
        local micros = math.tointeger(math.floor((tonumber(opts.clock()) or 0) * 1000000)) or 0
        local mix = (counter * GOLDEN) ~ timer ~ (micros << 20)
        local parts = {}
        for i = 1, 8 do
            mix = mix * LCG_MUL + LCG_ADD
            local v = step() ~ mix ~ (opts.rand(0, 0xFFFF) << 24)
            parts[i] = string.format('%04x', (v >> 32) & 0xFFFF)
        end
        return table.concat(parts)
    end
end

function M.isId(s)
    return type(s) == 'string' and #s == 32 and s:find('^[0-9a-f]+$') ~= nil
end

function M.path(id)
    return 'photos/' .. id .. '.jpg'
end

function M.urlPath(id)
    return '/aeterna_camera/p/' .. id .. '.jpg'
end

CameraLogic.ids = M
return M
