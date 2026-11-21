-- ids.lua -- aeterna_camera: photo ids and tickets (32 lowercase hex, 128 bits) and the paths built from them.
-- A path is only ever built from an id that passed isId, so it cannot hold '/', '..' or upper case. No natives.

CameraLogic = CameraLogic or {}

local M = {}

local MAX_DRAWS = 8

-- rand(lo, hi) is math.random on the server; eight 16-bit draws make 128 bits.
function M.new(rand)
    local parts = {}
    for i = 1, 8 do parts[i] = string.format('%04x', rand(0, 0xFFFF)) end
    return table.concat(parts)
end

-- Draws until exists(id) is false; nil after MAX_DRAWS collisions in a row.
function M.draw(rand, exists)
    for _ = 1, MAX_DRAWS do
        local id = M.new(rand)
        if not exists(id) then return id end
    end
    return nil
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
