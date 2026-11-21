-- settings.lua -- aeterna_camera: checks config.lua. A missing or out-of-range key falls back to its default
-- with one warn naming the key. No natives.

CameraLogic = CameraLogic or {}

local M = {}

local RULES = {
    { key = 'perCharacter', default = 60, min = 1, max = 500, integer = true },
    { key = 'maxBytes', default = 900000, min = 100000, max = 3000000, integer = true },
    { key = 'maxTotalMB', default = 1024, min = 1, max = 1048576, integer = true },
    { key = 'quality', default = 0.8, min = 0.5, max = 0.95 },
    { key = 'cooldownMs', default = 3000, min = 0, max = 600000, integer = true },
}

function M.check(raw, warn)
    raw = type(raw) == 'table' and raw or {}
    local cfg = {}
    for _, rule in ipairs(RULES) do
        local v = raw[rule.key]
        local ok = type(v) == 'number' and v >= rule.min and v <= rule.max
            and (not rule.integer or v == math.floor(v))
        if ok then
            cfg[rule.key] = v
        else
            if v ~= nil then warn('invalid config value; using the default', { key = rule.key }) end
            cfg[rule.key] = rule.default
        end
    end
    return cfg
end

CameraLogic.settings = M
return M
