// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
// owner reviews
(function (root, factory) {
    'use strict';
    if (typeof module === 'object' && module.exports) module.exports = factory();
    else (root.Rongroi = root.Rongroi || {}).strings = Object.assign(root.Rongroi.strings || {}, { settings: factory() });
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
    'use strict';
    return {
        en: {
            title: 'Settings',
            hint: 'These settings apply to this server kit.',
            save: 'Save settings',
            rotate: 'Rotate key',
            rotateConfirm: 'Rotate key',
            rotateCancel: 'Cancel',
            rotateConfirmHint: 'Open pairing codes stop working.',
            deletePlayerLabel: 'Player identifier',
            deletePlayer: 'Delete player data',
            deletePlayerConfirmHint: 'This removes every case and report for that player. This cannot be undone.',
            deletePlayerConfirm: 'Delete player data',
            deletePlayerCancel: 'Cancel',
            corrupt: '{count} stored settings could not be read and use their defaults.',
            fields: {
                publicOrigin: 'Public origin',
                retentionDays: 'Retention days',
                backendOverride: 'Backend',
                uploadPageEnabled: 'Upload page',
            },
            options: { backendOverride: { auto: 'Auto', kvp: 'Resource KVP', file: 'File' } },
            unknownError: 'The settings were not saved.',
            reasons: {
                invalid_policy: 'The policy is not valid.', invalid_public_origin: 'The public origin must be http(s)://host with no path.',
                invalid_retention_days: 'Retention must be a number of days.', invalid_backend_override: 'Choose auto, resource KVP or file.',
                invalid_upload_page_enabled: 'The upload page setting must be on or off.', invalid_server_name: 'The server name must be 1 to 128 characters with no control characters.',
                invalid_ttl_ms: 'The pairing lifetime must be 1 to 60 minutes.', unknown_setting: 'That setting is not known.',
                public_origin_missing: 'Set the public origin before opening a case.', server_name_missing: 'Set the server name before opening a case.',
                invalid_case_id: 'The case id is not valid.', case_not_found: 'That case was not found.',
                invalid_target: 'Choose a player first.', player_not_found: 'That player was not found.',
                settings_unavailable: 'The settings could not be read.', case_not_opened: 'The case could not be opened.',
                invalid_settings: 'The settings are not valid.', delete_failed: 'The delete did not finish.',
                invalid_identifier: 'The player identifier is not valid.', key_rotation_failed: 'The key could not be rotated.',
            },
        },
        th: {
            title: 'ตั้งค่า',
            hint: 'การตั้งค่านี้ใช้กับ Server Kit บนเซิร์ฟเวอร์นี้',
            save: 'บันทึกการตั้งค่า',
            rotate: 'เปลี่ยนกุญแจ',
            rotateConfirm: 'เปลี่ยนกุญแจ',
            rotateCancel: 'ยกเลิก',
            rotateConfirmHint: 'รหัสจับคู่ที่เปิดอยู่จะใช้ไม่ได้',
            deletePlayerLabel: 'รหัสผู้เล่น',
            deletePlayer: 'ลบข้อมูลผู้เล่น',
            deletePlayerConfirmHint: 'การลบนี้จะลบทุกเคสและรายงานของผู้เล่นนั้นและย้อนกลับไม่ได้',
            deletePlayerConfirm: 'ลบข้อมูลผู้เล่น',
            deletePlayerCancel: 'ยกเลิก',
            corrupt: 'อ่านการตั้งค่าที่บันทึกไว้ {count} รายการไม่ได้ จึงใช้ค่าเริ่มต้น',
            fields: {
                publicOrigin: 'ที่อยู่สาธารณะ',
                retentionDays: 'จำนวนวันเก็บรักษา',
                backendOverride: 'ระบบจัดเก็บ',
                uploadPageEnabled: 'หน้าอัปโหลด',
            },
            options: { backendOverride: { auto: 'อัตโนมัติ', kvp: 'KVP ของรีซอร์ส', file: 'ไฟล์' } },
            unknownError: 'บันทึกการตั้งค่าไม่ได้',
            reasons: {
                invalid_policy: 'นโยบายไม่ถูกต้อง', invalid_public_origin: 'ที่อยู่สาธารณะต้องเป็น http(s)://host และไม่มีพาธ',
                invalid_retention_days: 'ระยะเก็บรักษาต้องเป็นจำนวนวัน', invalid_backend_override: 'เลือกอัตโนมัติ, KVP ของรีซอร์ส หรือไฟล์',
                invalid_upload_page_enabled: 'การตั้งค่าหน้าอัปโหลดต้องเป็นเปิดหรือปิด', invalid_server_name: 'ชื่อเซิร์ฟเวอร์ต้องมี 1 ถึง 128 ตัวอักษรและไม่มีอักขระควบคุม',
                invalid_ttl_ms: 'อายุรหัสจับคู่ต้องอยู่ระหว่าง 1 ถึง 60 นาที', unknown_setting: 'ไม่รู้จักการตั้งค่านี้',
                public_origin_missing: 'ตั้งค่าที่อยู่สาธารณะก่อนเปิดเคส', server_name_missing: 'ตั้งชื่อเซิร์ฟเวอร์ก่อนเปิดเคส',
                invalid_case_id: 'รหัสเคสไม่ถูกต้อง', case_not_found: 'ไม่พบเคสนั้น',
                invalid_target: 'เลือกผู้เล่นก่อน', player_not_found: 'ไม่พบผู้เล่นนั้น',
                settings_unavailable: 'อ่านการตั้งค่าไม่ได้', case_not_opened: 'เปิดเคสไม่ได้',
                invalid_settings: 'การตั้งค่าไม่ถูกต้อง', delete_failed: 'การลบไม่สำเร็จ',
                invalid_identifier: 'รหัสผู้เล่นไม่ถูกต้อง', key_rotation_failed: 'เปลี่ยนกุญแจไม่ได้',
            },
        },
    };
}));
