Locales = Locales or {}
Locales.th = Locales.th or {}

-- Server side only (console lines and the self-test expect line). The page's own strings are in html/locale.json.
Locales.th['loading.config.bad'] = 'html/config.json: ค่า {field} ไม่ถูกต้อง ใช้ค่าเริ่มต้นแทน'

-- Self-test expect line (shown on the testkit eye card).
Locales.th['loading.selftest.expect.page'] = 'ตอนเข้าเซิร์ฟเวอร์ หน้าโหลดแสดงชื่อเซิร์ฟเวอร์ แล้วตามด้วย แผนที่ สคริปต์พร้อมเปอร์เซ็นต์ แล้วตัวละคร และปิดไปเอง'

return Locales.th
