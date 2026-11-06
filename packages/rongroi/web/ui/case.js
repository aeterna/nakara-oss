// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
(function (root, factory) {
    'use strict';
    if (typeof module === 'object' && module.exports) module.exports = factory();
    else (root.Rongroi = root.Rongroi || {}).screens = Object.assign(root.Rongroi.screens || {}, { case: factory() });
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
    'use strict';
    return {
        viewModel: function (data) { return { screen: 'case', built: false, data: data || null }; },
        render: function (root) { root.textContent = 'Not built yet.'; },
    };
}));
