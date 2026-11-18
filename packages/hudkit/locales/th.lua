-- locales/th.lua -- Thai strings for aeterna_hudkit.

Locales = Locales or {}
Locales.th = Locales.th or {}

local STRINGS = {
    ['hudkit.menu.entry'] = 'ตั้งค่า HUD',
    ['hudkit.key.settings'] = 'ตั้งค่า HUD',
    ['hudkit.bar.health'] = 'พลังชีวิต',
    ['hudkit.bar.armour'] = 'เกราะ',
    ['hudkit.bar.hunger'] = 'ความหิว',
    ['hudkit.bar.thirst'] = 'ความกระหาย',
    ['hudkit.bar.stress'] = 'ความเครียด',
    ['hudkit.vehicle.fuel'] = 'น้ำมัน',
    ['hudkit.vehicle.gear'] = 'เกียร์',
    ['hudkit.unit.kmh'] = 'กม./ชม.',
    ['hudkit.unit.mph'] = 'ไมล์/ชม.',
    ['hudkit.part.status'] = 'แถบสถานะ',
    ['hudkit.part.vehicle'] = 'แผงยานพาหนะ',
    ['hudkit.part.street'] = 'ตำแหน่งและเข็มทิศ',
    ['hudkit.part.minimap'] = 'แผนที่ย่อ',
    ['hudkit.settings.title'] = 'ตั้งค่า HUD',
    ['hudkit.settings.numbers'] = 'แสดงตัวเลขบนแถบสถานะ',
    ['hudkit.settings.speedUnit'] = 'หน่วยความเร็ว',
    ['hudkit.settings.minimap'] = 'แผนที่ย่อ',
    ['hudkit.settings.minimap.always'] = 'ตลอดเวลา',
    ['hudkit.settings.minimap.vehicle'] = 'เฉพาะในยานพาหนะ',
    ['hudkit.settings.minimap.never'] = 'ไม่แสดง',
    ['hudkit.settings.layout'] = 'แก้ไขเลย์เอาต์',
    ['hudkit.settings.close'] = 'ปิด',
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
    Locales.th[k] = v
end
