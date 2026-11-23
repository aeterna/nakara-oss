-- aeterna_loading client: tells its own loadscreen page when the Character stage starts, and closes the page
-- on playerSpawned or after shutdown.fallbackSeconds, unless something else (a framework) already closed it.
-- With loadscreen_manual_shutdown nothing else is guaranteed to close the page, so every failure below
-- (missing logic, unreadable config, a session that never starts) still ends in a close.

local RESOURCE = GetCurrentResourceName()
local DEFAULT_FALLBACK_SECONDS = 30 -- the spec's default for shutdown.fallbackSeconds
local resourceStartedAt = GetGameTimer()

local function readFallbackSeconds()
    local raw = LoadResourceFile(RESOURCE, 'html/config.json')
    local decoded = nil
    if type(raw) == 'string' then
        local ok, value = pcall(json.decode, raw)
        if ok then decoded = value end
    end
    local cfg = LoadingLogic.validateConfig(decoded)
    return cfg.shutdown.fallbackSeconds
end

local okConfig, fallbackSeconds = pcall(readFallbackSeconds)
if not okConfig or type(fallbackSeconds) ~= 'number' then
    fallbackSeconds = DEFAULT_FALLBACK_SECONDS
end

local spawned = false

AddEventHandler('playerSpawned', function()
    spawned = true
end)

local function send(msg)
    SendLoadingScreenMessage(json.encode(msg))
end

-- Hard cap from resource start while the session has not started; from the session start after it did.
local function closeDue(sessionStartedAt, now)
    local ok, due = pcall(function()
        return LoadingLogic.closeDue(resourceStartedAt, sessionStartedAt, now, fallbackSeconds)
    end)
    if ok then return due end
    return now - (sessionStartedAt or resourceStartedAt) >= fallbackSeconds * 1000
end

local function closePage()
    if not GetIsLoadingScreenActive() then return end
    pcall(send, { type = 'aeterna_loading:closing' })
    Wait(1000) -- the page fades its audio out over 1 s
    if GetIsLoadingScreenActive() then
        ShutdownLoadingScreen()
        ShutdownLoadingScreenNui()
    end
end

CreateThread(function()
    local sessionStartedAt = nil
    pcall(function()
        while not spawned do
            if sessionStartedAt == nil and NetworkIsSessionStarted() then
                sessionStartedAt = GetGameTimer()
                send({ type = 'aeterna_loading:stage', stage = 'character' })
            end
            if closeDue(sessionStartedAt, GetGameTimer()) then return end
            Wait(250)
        end
    end)
    closePage()
end)

-- Self-tests run on the presser's client (spec § Self-tests (0.2)); results go back through aeterna_core's
-- client-local event with `owner`, never through a core export.
AddEventHandler('aeterna_core:selftest', function(runId, name)
    if GetInvokingResource() ~= 'aeterna_core' or not LoadingSelftest.owns(RESOURCE, name) then return end
    if name == RESOURCE .. '.shut_down' then
        local ok, detail = LoadingSelftest.shutDown(GetIsLoadingScreenActive())
        TriggerEvent('aeterna_core:selftest:report', RESOURCE, runId, name, ok, detail)
    elseif name == RESOURCE .. '.page_looked_right' then
        -- Nothing to set up: the person answers from what they saw when they joined.
        TriggerEvent('aeterna_core:selftest:report', RESOURCE, runId, name, 'ready', '')
    end
end)
