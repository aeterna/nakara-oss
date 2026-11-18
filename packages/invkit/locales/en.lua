Locales = Locales or {}
Locales.en = Locales.en or {}

local EN = {
    ['invkit.stash.label'] = 'Personal stash',
    ['invkit.stash.hint'] = 'Open stash',
    ['invkit.stash.far'] = 'Too far from a stash location',
    ['invkit.use.busy'] = 'Already using an item',
    ['invkit.use.cancelled'] = 'Item use cancelled',
    ['invkit.key.open'] = 'Open personal stash',
    ['invkit.noox'] = 'ox_inventory is not started; aeterna_invkit is inactive',
}

for k, v in pairs(EN) do
    Locales.en[k] = v
end

return Locales.en
