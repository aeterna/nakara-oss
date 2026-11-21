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
