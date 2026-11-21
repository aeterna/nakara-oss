-- client/selftest.lua -- runs aeterna_invkit.stash_open on the presser's client. It sends the same request as
-- the bound key (aeterna_invkit:sv:open) at the presser's position and watches for the stash opening or the
-- refusal; decisions live in shared/logic/selftest.lua.

local ST = InvkitSelftest
local L = InvkitLogic

local running = {} -- [full name] = runId
local lastRefusal = nil

local function report(runId, name, state, detail, extra)
    exports.aeterna_core:reportSelftest(runId, name, state, detail, extra)
end

AddEventHandler('aeterna_invkit:cl:refused', function(data)
    if type(data) == 'table' and data.item == 'stash' and type(data.reason) == 'string' then
        lastRefusal = data.reason
    end
end)

-- ox_inventory marks its open inventory in the player's state bag.
local function inventoryOpen()
    local ok, open = pcall(function() return LocalPlayer.state.invOpen end)
    return ok and open == true
end

local function closeInventory()
    pcall(function() exports.ox_inventory:closeInventory() end)
end

-- Sends one open request and waits up to 1500 ms: 'opened', 'refused' (+ reason) or 'none'.
local function tryOpen()
    lastRefusal = nil
    TriggerServerEvent('aeterna_invkit:sv:open')
    for _ = 1, 15 do
        Wait(100)
        if lastRefusal then return 'refused', lastRefusal end
        if inventoryOpen() then
            closeInventory()
            return 'opened'
        end
    end
    return 'none'
end

local function stashOpen(runId, name)
    local cfg = Config.stash
    local watch = ST.newStashWatch(cfg.anywhere == true)
    local waited = 0
    while waited < ST.STASH_WATCH_MS and running[name] == runId do
        local canOpen = (L.canOpenAt(GetEntityCoords(PlayerPedId()), cfg))
        if watch.needs(canOpen) then
            local outcome, reason = tryOpen()
            if watch.record(canOpen, outcome, reason) then break end
            Wait(1000)
            waited = waited + 2500
        else
            Wait(500)
            waited = waited + 500
        end
    end
    if running[name] ~= runId then return end
    report(runId, name, watch.verdict())
end

AddEventHandler('aeterna_core:selftest', function(runId, name)
    if ST.shortName(name) ~= 'stash_open' then return end
    local oxStarted = GetResourceState('ox_inventory') == 'started'
    local reason = ST.skipReason('stash_open', Config, { oxStarted = oxStarted })
    if reason then
        report(runId, name, 'skip', reason)
        return
    end
    running[name] = runId
    CreateThread(function()
        stashOpen(runId, name)
    end)
end)

AddEventHandler('aeterna_core:selftestEnd', function(runId, name)
    if running[name] == runId then running[name] = nil end
end)
