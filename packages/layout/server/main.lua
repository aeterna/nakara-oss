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

-- Panel buttons (server-local event from aeterna_uikit). Reset all asks to confirm in the panel first.
local PANEL_MODES = { edit = 'editor', share = 'share', resetConfirm = 'reset' }

AddEventHandler('aeterna_uikit:action', function(src, data)
    if type(data) ~= 'table' or data.owner ~= selfName() then
        return
    end
    local target = tonumber(src)
    if not target or target <= 0 then
        return
    end
    local action = data.action
    if action == 'resetAll' then
        openPanel(target, true)
    elseif action == 'back' then
        openPanel(target, false)
    elseif PANEL_MODES[action] then
        closePanel(target)
        TriggerClientEvent('aeterna_layout:cl:open', target, { mode = PANEL_MODES[action] })
    end
end)

AddEventHandler('onResourceStart', function(resName)
    if resName == 'aeterna_uikit' or resName == selfName() then
        registerMenuEntry()
    end
end)

registerMenuEntry()
