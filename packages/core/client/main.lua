-- aeterna_core client: NUI focus lock and themeHref export.

AeternaCoreLogic = AeternaCoreLogic or {}
AeternaCore = AeternaCore or {}

local focusLogic = AeternaCoreLogic.focus
local focusManager = focusLogic.new({
    onLost = function(owner, token, reason)
        TriggerEvent('aeterna_core:focusLost', owner, token, reason)
    end,
    onPaused = function(owner, token)
        TriggerEvent('aeterna_core:focusPaused', owner, token)
    end,
    onResumed = function(owner, token)
        TriggerEvent('aeterna_core:focusResumed', owner, token)
    end,
})

local warnedTheme = nil

local function isValidThemeHref(href)
    if type(href) ~= 'string' or #href <= 10 then
        return false
    end
    if href:sub(1, 6) ~= 'nui://' or href:sub(-4) ~= '.css' then
        return false
    end
    local slash = href:find('/', 7, true)
    if not slash or slash == 7 or slash >= #href - 3 then
        return false
    end
    return true
end

exports('requestFocus', function(opts)
    local owner = GetInvokingResource() or GetCurrentResourceName()
    local token = focusManager:request(owner, opts)
    return token
end)

exports('releaseFocus', function(token)
    return focusManager:release(token)
end)

exports('focusOwner', function()
    return focusManager:owner()
end)

exports('focusPausedOwner', function()
    return focusManager:pausedOwner()
end)

exports('themeHref', function()
    local raw = GetConvar('aeterna_theme', '')
    if raw == nil or raw == '' then
        return nil
    end
    if isValidThemeHref(raw) then
        return raw
    end
    if warnedTheme ~= raw then
        warnedTheme = raw
        AeternaCore.log.warn('invalid aeterna_theme; expected nui://<resource>/<path>.css', { value = raw })
    end
    return nil
end)

AddEventHandler('onResourceStop', function(stoppedResource)
    focusManager:onResourceStop(stoppedResource, GetCurrentResourceName())
end)
