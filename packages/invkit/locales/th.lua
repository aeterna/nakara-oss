Locales = Locales or {}
Locales.th = Locales.th or {}

local TH = {
    ['invkit.stash.label'] = 'ตู้เก็บของส่วนตัว',
    ['invkit.stash.hint'] = 'เปิดตู้เก็บของ',
    ['invkit.stash.far'] = 'อยู่ห่างจากจุดเปิดตู้เก็บของเกินไป',
    ['invkit.use.busy'] = 'กำลังใช้งานไอเทมอื่นอยู่',
    ['invkit.use.cancelled'] = 'ยกเลิกการใช้ไอเทมแล้ว',
    ['invkit.key.open'] = 'เปิดตู้เก็บของส่วนตัว',
    ['invkit.noox'] = 'ไม่ได้เปิดใช้งาน ox_inventory ระบบ aeterna_invkit จึงไม่ทำงาน',
}

for k, v in pairs(TH) do
    Locales.th[k] = v
end

return Locales.th
