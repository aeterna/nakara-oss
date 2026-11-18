-- server/main.lua -- aeterna_hudkit server: answers uikit menu entry.

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
    pcall(function()
        exports.aeterna_uikit:addMenuEntry({
            id = 'hudkit',
            label = translate('hudkit.menu.entry'),
            icon = 'sliders',
            order = 110,
            group = 'general',
        })
    end)
end

AddEventHandler('aeterna_uikit:menu', function(src, data)
    local selfName = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_hudkit'
    if type(data) ~= 'table' or data.owner ~= selfName then
        return
    end
    local target = tonumber(src)
    if not target or target <= 0 then
        return
    end
    TriggerClientEvent('aeterna_hudkit:cl:settings', target)
end)

AddEventHandler('onResourceStart', function(resName)
    local selfName = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_hudkit'
    if resName == 'aeterna_uikit' or resName == selfName then
        registerMenuEntry()
    end
end)

registerMenuEntry()
