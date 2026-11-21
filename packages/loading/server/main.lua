-- aeterna_loading server: validates html/config.json once at start so the owner sees mistakes in the console.
-- The page applies the same rules (html/logic.js) and falls back field by field; nothing here is sent anywhere.

local RESOURCE = GetCurrentResourceName()

local function text(lang, key, vars)
    local s = (Locales[lang] and Locales[lang][key]) or Locales.en[key] or key
    return (s:gsub('{(%w+)}', function(name) return tostring(vars[name]) end))
end

local function readConfig()
    local raw = LoadResourceFile(RESOURCE, 'html/config.json')
    if type(raw) ~= 'string' then return nil end
    local ok, decoded = pcall(json.decode, raw)
    if ok then return decoded end
    return nil
end

local cfg, errors = LoadingLogic.validateConfig(readConfig())
for i = 1, #errors do
    print(('[%s] WARN %s'):format(RESOURCE, text(cfg.lang, 'loading.config.bad', { field = errors[i].field })))
end

-- Self-tests (spec § Self-tests (0.2)). aeterna_core is an optional edge reached only through its local events,
-- each carrying `owner` first; with core not started the events go nowhere.
local function registerSelftests()
    local lang = cfg.lang
    for _, r in ipairs(LoadingSelftest.rows(RESOURCE, function(key) return text(lang, key, {}) end)) do
        TriggerEvent('aeterna_core:selftest:add', RESOURCE, r.name, r.meta)
    end
end

if GetResourceState('aeterna_core') == 'started' then registerSelftests() end
AddEventHandler('aeterna_core:hello', function()
    if GetInvokingResource() == 'aeterna_core' then registerSelftests() end
end)

AddEventHandler('aeterna_core:selftest', function(runId, name)
    if GetInvokingResource() ~= 'aeterna_core' or not LoadingSelftest.owns(RESOURCE, name) then return end
    local ok, detail
    if name == RESOURCE .. '.config_valid' then
        local _, errs = LoadingLogic.validateConfig(readConfig())
        ok, detail = LoadingSelftest.configValid(errs)
    elseif name == RESOURCE .. '.local_paths_only' then
        ok, detail = LoadingSelftest.localPaths(LoadingLogic, readConfig())
    else
        return
    end
    TriggerEvent('aeterna_core:selftest:report', RESOURCE, runId, name, ok, detail)
end)
