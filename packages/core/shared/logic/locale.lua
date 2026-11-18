-- Pure locale lookup and variable interpolation for aeterna_core. No natives.

AeternaCoreLogic = AeternaCoreLogic or {}

local M = {}

local function lookup(tbl, key)
    if type(tbl) ~= 'table' or key == nil then
        return nil
    end
    local direct = tbl[key]
    if type(direct) == 'string' then
        return direct
    end
    return nil
end

function M.interpolate(str, vars)
    if type(str) ~= 'string' or type(vars) ~= 'table' then
        return tostring(str or '')
    end
    local out = str:gsub('{([%w_]+)}', function(name)
        local val = vars[name]
        if val == nil then
            return '{' .. name .. '}'
        end
        return tostring(val)
    end)
    return out
end

-- Supports both M.t(locales, lang, key, vars) and M.t(key, vars) (reading global Locales).
function M.t(a, b, c, d)
    local locales, lang, key, vars
    if type(a) == 'table' then
        locales, lang, key, vars = a, b, c, d
    else
        locales = Locales
        lang = 'en'
        key = a
        vars = b
    end

    if key == nil then
        return ''
    end
    local keyStr = tostring(key)
    local activeLang = (lang == 'th' or lang == 'en') and lang or 'en'

    local found
    if type(locales) == 'table' then
        found = lookup(locales[activeLang], keyStr)
        if found == nil and activeLang ~= 'en' then
            found = lookup(locales.en, keyStr)
        end
    end
    if found == nil then
        found = keyStr
    end

    return M.interpolate(found, vars)
end

AeternaCoreLogic.locale = M
return M
