-- locales/en.lua -- English strings for aeterna_hudkit.

Locales = Locales or {}
Locales.en = Locales.en or {}

local STRINGS = {
    ['hudkit.menu.entry'] = 'HUD settings',
    ['hudkit.key.settings'] = 'HUD settings',
    ['hudkit.bar.health'] = 'Health',
    ['hudkit.bar.armour'] = 'Armour',
    ['hudkit.bar.hunger'] = 'Hunger',
    ['hudkit.bar.thirst'] = 'Thirst',
    ['hudkit.bar.stress'] = 'Stress',
    ['hudkit.vehicle.fuel'] = 'Fuel',
    ['hudkit.vehicle.gear'] = 'Gear',
    ['hudkit.unit.kmh'] = 'km/h',
    ['hudkit.unit.mph'] = 'mph',
    ['hudkit.part.status'] = 'Status bars',
    ['hudkit.part.vehicle'] = 'Vehicle panel',
    ['hudkit.part.street'] = 'Street and compass',
    ['hudkit.part.minimap'] = 'Minimap',
    ['hudkit.settings.title'] = 'HUD settings',
    ['hudkit.settings.numbers'] = 'Show numbers on bars',
    ['hudkit.settings.speedUnit'] = 'Speed unit',
    ['hudkit.settings.minimap'] = 'Minimap',
    ['hudkit.settings.minimap.always'] = 'Always',
    ['hudkit.settings.minimap.vehicle'] = 'In vehicle',
    ['hudkit.settings.minimap.never'] = 'Never',
    ['hudkit.settings.layout'] = 'Edit layout',
    ['hudkit.settings.close'] = 'Close',
    ['hudkit.dir.n'] = 'N',
    ['hudkit.dir.ne'] = 'NE',
    ['hudkit.dir.e'] = 'E',
    ['hudkit.dir.se'] = 'SE',
    ['hudkit.dir.s'] = 'S',
    ['hudkit.dir.sw'] = 'SW',
    ['hudkit.dir.w'] = 'W',
    ['hudkit.dir.nw'] = 'NW',
}

for k, v in pairs(STRINGS) do
    Locales.en[k] = v
end
