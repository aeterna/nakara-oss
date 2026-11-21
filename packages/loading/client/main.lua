-- aeterna_loading client: tells its own loadscreen page when the Character stage starts, and closes the page
-- on playerSpawned or after shutdown.fallbackSeconds, unless something else (a framework) already closed it.

local RESOURCE = GetCurrentResourceName()

local function readConfig()
    local raw = LoadResourceFile(RESOURCE, 'html/config.json')
    if type(raw) ~= 'string' then return nil end
    local ok, decoded = pcall(json.decode, raw)
    if ok then return decoded end
    return nil
end

local cfg = LoadingLogic.validateConfig(readConfig())
local spawned = false

AddEventHandler('playerSpawned', function()
    spawned = true
end)

local function send(msg)
    SendLoadingScreenMessage(json.encode(msg))
end

local function closePage()
    if not GetIsLoadingScreenActive() then return end
    send({ type = 'aeterna_loading:closing' })
    Wait(1000) -- the page fades its audio out over 1 s
    if GetIsLoadingScreenActive() then
        ShutdownLoadingScreen()
        ShutdownLoadingScreenNui()
    end
end

CreateThread(function()
    while not NetworkIsSessionStarted() do
        Wait(250)
    end
    send({ type = 'aeterna_loading:stage', stage = 'character' })

    local startedAt = GetGameTimer()
    while not spawned and not LoadingLogic.fallbackDue(startedAt, GetGameTimer(), cfg.shutdown.fallbackSeconds) do
        Wait(250)
    end
    closePage()
end)
