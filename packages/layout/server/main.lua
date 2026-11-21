-- aeterna_layout server: registers the shared menu entry in aeterna_uikit, opens the menu panel (0.2) and tells the
-- client what to open. Layouts never reach the server.

local function translate(key)
    if AeternaCore and type(AeternaCore.t) == 'function' then
        return AeternaCore.t(key)
    end
    if Locales and Locales.en and Locales.en[key] then
        return Locales.en[key]
    end
    return key
end

local function registerMenuEntry()
    if Config and Config.menu == false then
        return
    end
    pcall(function()
        exports.aeterna_uikit:addMenuEntry({
            id = 'layout',
            label = translate('layout.menu.entry'),
            icon = 'sliders',
            order = 100,
            group = 'general',
        })
    end)
end

local function selfName()
    return type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_layout'
end

local function openPanel(target, confirmReset)
    local blocks
    if confirmReset then
        blocks = {
            { id = 'confirm', type = 'text', label = translate('layout.editor.resetAllConfirm') },
            { id = 'act', type = 'buttons', items = {
                { id = 'resetConfirm', label = translate('layout.menu.resetAll'), variant = 'danger' },
                { id = 'back', label = translate('layout.editor.cancel'), variant = 'secondary' },
            } },
        }
    else
        blocks = {
            { id = 'act', type = 'buttons', items = {
                { id = 'edit', label = translate('layout.menu.edit'), variant = 'primary' },
                { id = 'resetAll', label = translate('layout.menu.resetAll'), variant = 'danger' },
                { id = 'share', label = translate('layout.menu.share'), variant = 'secondary' },
            } },
        }
    end
    pcall(function()
        exports.aeterna_uikit:open(target, { title = translate('layout.menu.entry'), size = 'sm', blocks = blocks })
    end)
end

local function closePanel(target)
    pcall(function()
        exports.aeterna_uikit:close(target)
    end)
end

AddEventHandler('aeterna_uikit:menu', function(src, data)
    if type(data) ~= 'table' or data.owner ~= selfName() then
        return
    end
    local target = tonumber(src)
    if not target or target <= 0 then
        return
    end
    if Config and Config.menuPanel == false then
        TriggerClientEvent('aeterna_layout:cl:open', target)
        return
    end
    openPanel(target, false)
end)

-- Panel buttons (server-local event from aeterna_uikit). Reset all asks to confirm in the panel first: pressing it
-- arms the client with a one-time token, and resetConfirm sends that token only while the confirm row is open
-- (at most 30 s).
local PANEL_MODES = { edit = 'editor', share = 'share' }
local RESET_CONFIRM_TTL_MS = 30000
local pendingReset = {}

local function newResetToken()
    return ('%08x%08x'):format(math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
end

AddEventHandler('aeterna_uikit:action', function(src, data)
    if type(data) ~= 'table' or data.owner ~= selfName() then
        return
    end
    local target = tonumber(src)
    if not target or target <= 0 then
        return
    end
    local action = data.action
    local pending = pendingReset[target]
    pendingReset[target] = nil
    if action == 'resetAll' then
        local token = newResetToken()
        pendingReset[target] = { token = token, expires = GetGameTimer() + RESET_CONFIRM_TTL_MS }
        openPanel(target, true)
        TriggerClientEvent('aeterna_layout:cl:open', target, { mode = 'arm', token = token })
    elseif action == 'resetConfirm' then
        if pending and GetGameTimer() <= pending.expires then
            closePanel(target)
            TriggerClientEvent('aeterna_layout:cl:open', target, { mode = 'reset', token = pending.token })
        end
    elseif action == 'back' then
        openPanel(target, false)
    elseif PANEL_MODES[action] then
        closePanel(target)
        TriggerClientEvent('aeterna_layout:cl:open', target, { mode = PANEL_MODES[action] })
    end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then
        pendingReset[src] = nil
    end
end)

AddEventHandler('onResourceStart', function(resName)
    if resName == 'aeterna_uikit' or resName == selfName() then
        registerMenuEntry()
    end
end)

registerMenuEntry()
