// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
// owner reviews
(function (root, factory) {
    'use strict';
    if (typeof module === 'object' && module.exports) module.exports = factory();
    else (root.Rongroi = root.Rongroi || {}).strings = Object.assign(root.Rongroi.strings || {}, { code: factory() });
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
    'use strict';
    return {
        en: {
            title: 'Pairing code',
            hint: 'Paste this code into Rongroi Connect.',
            copy: 'Copy',
            copied: 'Copied',
            copyFailed: 'Could not copy',
            expiresIn: 'Expires in {time}',
            expired: 'This code has expired.',
            empty: 'No pairing code yet.',
            onlyPaste: 'Only paste this code from the game.',
        },
        th: {
            title: 'รหัสจับคู่',
            hint: 'วางรหัสนี้ใน Rongroi Connect',
            copy: 'คัดลอก',
            copied: 'คัดลอกแล้ว',
            copyFailed: 'คัดลอกไม่ได้',
            expiresIn: 'หมดอายุใน {time}',
            expired: 'รหัสนี้หมดอายุแล้ว',
            empty: 'ยังไม่มีรหัสจับคู่',
            onlyPaste: 'วางรหัสนี้จากในเกมเท่านั้น',
        },
    };
}));
