-- nakara_example -- client side.
-- Keep decision logic in plain-Lua files (no natives, no CfxLua-only syntax) so specs can load it with
-- stock Lua; keep native calls here.

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    -- client start-up work goes here
end)
