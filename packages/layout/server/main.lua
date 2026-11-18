-- aeterna_layout server: registers the shared menu entry in aeterna_uikit and opens the client editor.

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

AddEventHandler('aeterna_uikit:menu', function(src, data)
    local selfName = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_layout'
    if type(data) ~= 'table' or data.owner ~= selfName then
        return
    end
    local target = tonumber(src)
    if not target or target <= 0 then
        return
    end
    TriggerClientEvent('aeterna_layout:cl:open', target)
end)

AddEventHandler('onResourceStart', function(resName)
    local selfName = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_layout'
    if resName == 'aeterna_uikit' or resName == selfName then
        registerMenuEntry()
    end
end)

registerMenuEntry()
