Locales = Locales or {}
Locales.th = Locales.th or {}

Locales.th['notify.motd.dismiss'] = 'ไม่ต้องแสดงอีก'
Locales.th['notify.motd.continue'] = 'ดำเนินการต่อ'
Locales.th['notify.announce.title'] = 'ประกาศ'
Locales.th['notify.announce.by'] = 'โดย {name}'
Locales.th['notify.announce.console'] = 'คอนโซล'
Locales.th['notify.announce.usage'] = 'วิธีใช้: aeterna_announce <ข้อความ>'
Locales.th['notify.announce.denied'] = 'คุณไม่มีสิทธิ์ส่งประกาศ'
Locales.th['notify.action.unbound'] = 'ยังไม่ได้ตั้งปุ่ม'
Locales.th['notify.sound.on'] = 'เปิดเสียงแจ้งเตือนแล้ว'
Locales.th['notify.sound.off'] = 'ปิดเสียงแจ้งเตือนแล้ว'
Locales.th['notify.sound.disabled'] = 'เซิร์ฟเวอร์นี้ปิดเสียงแจ้งเตือนไว้'
Locales.th['notify.countdown.title'] = 'นับถอยหลัง'
Locales.th['notify.countdown.usage'] = 'วิธีใช้: aeterna_announce_countdown <นาที 1-60> <ข้อความ>'
Locales.th['notify.countdown.busy'] = 'มีการนับถอยหลังอยู่แล้ว'
Locales.th['notify.key.action1'] = 'การแจ้งเตือน: ปุ่มแรก'
Locales.th['notify.key.action2'] = 'การแจ้งเตือน: ปุ่มที่สอง'

-- 0.2 self-tests (expect texts and test toast strings)
Locales.th['notify.selftest.toast_types'] = 'ทอสต์สี่อัน หนึ่งอันต่อหนึ่งประเภท อยู่ที่มุมที่ตั้งไว้ แต่ละอันมีแถบอายุที่หดจนหมดตามเวลา'
Locales.th['notify.selftest.stack_merge'] = 'ทอสต์ที่เหมือนกันหกอันแสดงเป็นทอสต์เดียวที่เขียนว่า ×6 และไม่กระโดด'
Locales.th['notify.selftest.action_press'] = 'ทอสต์ที่มีปุ่มสองปุ่ม กดปุ่มที่ผูกกับ action 1 แล้วทอสต์ปิด และการทดสอบได้รับ id ของ action แรก'
Locales.th['notify.selftest.sound_plays'] = 'ทอสต์แต่ละประเภทเล่นเสียงของตัวเองหนึ่งครั้ง เมื่อผู้เล่นปิดเสียงไว้จะไม่มีเสียงเลย'
Locales.th['notify.selftest.countdown_banner'] = 'แบนเนอร์นับถอยหลัง 30 วินาที นับลงแบบ mm:ss และหายไปเมื่อถึงศูนย์'
Locales.th['notify.selftest.motion_reduced'] = 'เมื่อเปิดลดการเคลื่อนไหว ทอสต์ปรากฏและหายไปโดยไม่เลื่อนและไม่มีแถบอายุ'
Locales.th['notify.selftest.toast'] = 'ทดสอบตัวเอง: ทอสต์ประเภท {type}'
Locales.th['notify.selftest.merge'] = 'ทดสอบตัวเอง: ทอสต์เดียวกันหกครั้ง'
Locales.th['notify.selftest.action'] = 'ทดสอบตัวเอง: ทอสต์ที่มีปุ่มสองปุ่ม'
Locales.th['notify.selftest.action1'] = 'ปุ่มแรก'
Locales.th['notify.selftest.action2'] = 'ปุ่มสอง'
Locales.th['notify.selftest.sound_on'] = 'เปิดเสียง: {type}'
Locales.th['notify.selftest.sound_off'] = 'ปิดเสียงของผู้เล่น: {type}'
Locales.th['notify.selftest.countdown'] = 'ทดสอบนับถอยหลัง'
Locales.th['notify.selftest.motion'] = 'ทดสอบตัวเอง: ทอสต์นี้มาแล้วก็ไป'

return Locales.th
