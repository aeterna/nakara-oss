-- Pure logic for the aeterna_loading self-tests (docs/specs/aeterna_loading.md "Self-tests (0.2)"): the rows
-- this package registers with aeterna_core and the pass rule of each check. Natives-free so stock Lua can test it.

LoadingSelftest = {}
local S = LoadingSelftest

-- The spec table, in order. `t(key)` translates the eye test's expect line.
function S.rows(owner, t)
    local function row(id, meta)
        return { name = owner .. '.' .. id, meta = meta }
    end
    return {
        row('config_valid', { kind = 'headless', players = 1, destructive = false }),
        row('local_paths_only', { kind = 'headless', players = 1, destructive = false }),
        row('shut_down', { kind = 'ped', players = 1, destructive = false }),
        row('page_looked_right', { kind = 'eye', players = 1, destructive = false,
            expect = t('loading.selftest.expect.page') }),
    }
end

-- A test belongs to this resource when its name starts with '<owner>.'.
function S.owns(owner, name)
    return type(name) == 'string' and name:sub(1, #owner + 1) == owner .. '.'
end

-- `errors` = the list LoadingLogic.validateConfig returns.
function S.configValid(errors)
    if #errors == 0 then return true, 'html/config.json is valid' end
    local fields = {}
    for i = 1, #errors do fields[i] = tostring(errors[i].field) end
    return false, 'bad fields: ' .. table.concat(fields, ', ')
end

-- Every path the page loads (background, audio.src) is empty or a file inside html/. `raw` = decoded config.
function S.localPaths(logic, raw)
    if type(raw) ~= 'table' then return false, 'html/config.json could not be read' end
    local audio = type(raw.audio) == 'table' and raw.audio or {}
    local bad = {}
    for _, p in ipairs({ { 'background', raw.background, logic.IMAGE_EXT }, { 'audio.src', audio.src, logic.AUDIO_EXT } }) do
        local v = p[2]
        if v ~= nil and v ~= '' and not logic.isLocalPath(v, p[3]) then bad[#bad + 1] = p[1] end
    end
    if #bad == 0 then return true, 'background and audio.src are local' end
    return false, 'not a local path: ' .. table.concat(bad, ', ')
end

-- `active` = GetIsLoadingScreenActive() on the presser's client.
function S.shutDown(active)
    if active == false then return true, 'loading screen is shut down' end
    return false, 'loading screen is still active'
end

return LoadingSelftest
