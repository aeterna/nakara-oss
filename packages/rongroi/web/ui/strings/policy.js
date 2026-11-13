// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
// owner reviews
(function (root, factory) {
    'use strict';
    if (typeof module === 'object' && module.exports) module.exports = factory(root);
    else (root.Rongroi = root.Rongroi || {}).strings = Object.assign(root.Rongroi.strings || {}, { policy: factory(root) });
}(typeof globalThis !== 'undefined' ? globalThis : this, function (root) {
    'use strict';
    // The reason codes are shared with settings.js; load its table in Node or after it in the browser.
    var shared = root.Rongroi && root.Rongroi.strings && root.Rongroi.strings.settings;
    if (!shared && typeof module === 'object' && module.exports) shared = require('./settings.js');
    shared = shared || { en: {}, th: {} };
    return {
        en: {
            title: 'Policy',
            hint: 'What a Connect upload includes.',
            save: 'Save policy',
            emptyHash: 'No policy hash yet.',
            fields: {
                profile: 'Profile',
                required_collectors: 'Collectors',
                require_elevation: 'Elevation',
                serverName: 'Server name',
                policy_hash: 'Policy hash',
            },
            options: { profile: { posture: 'Posture', standard: 'Standard', custom: 'Custom' } },
            unknownError: 'The policy was not saved.',
            reasons: shared.en.reasons || {},
        },
        th: {
            title: 'นโยบาย',
            hint: 'สิ่งที่ Connect จะส่งขึ้นมา',
            save: 'บันทึกนโยบาย',
            emptyHash: 'ยังไม่มีแฮชของนโยบาย',
            fields: {
                profile: 'โปรไฟล์',
                required_collectors: 'ตัวเก็บข้อมูล',
                require_elevation: 'สิทธิ์ผู้ดูแลระบบ',
                serverName: 'ชื่อเซิร์ฟเวอร์',
                policy_hash: 'แฮชของนโยบาย',
            },
            options: { profile: { posture: 'ตรวจสภาพเครื่อง', standard: 'มาตรฐาน', custom: 'กำหนดเอง' } },
            unknownError: 'บันทึกนโยบายไม่ได้',
            reasons: shared.th.reasons || {},
        },
    };
}));
