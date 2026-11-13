// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
'use strict';

// Code-screen view model only: countdown, expiry, empty code and the groups of four.
const test = require('node:test');
const assert = require('node:assert/strict');
const { viewModel } = require('../web/ui/code.js');

test('countdown seconds come from expiresAt and the injected now', () => {
    const model = viewModel({ code: 'ABCDEFGH', expiresAt: 100000 }, 40000);
    assert.equal(model.seconds, 60);
    assert.equal(model.countdown, '1:00');
    assert.equal(model.expired, false);
    // A partial second still shows as one second until the clock passes expiresAt.
    assert.equal(viewModel({ code: 'ABCDEFGH', expiresAt: 100500 }, 100000).seconds, 1);
});

test('an expired code has no countdown', () => {
    const model = viewModel({ code: 'ABCDEFGH', expiresAt: 100000 }, 100000);
    assert.equal(model.expired, true);
    assert.equal(model.seconds, 0);
    assert.equal(model.countdown, '');
    assert.equal(viewModel({ code: 'ABCDEFGH', expiresAt: 100000 }, 100001).expired, true);
});

test('an empty or missing code is empty and never expired', () => {
    for (const data of [undefined, {}, { code: '' }, { code: null }, { code: 42 }]) {
        const model = viewModel(data, 1000);
        assert.equal(model.empty, true);
        assert.deepEqual(model.groups, []);
        assert.equal(model.grouped, '');
        assert.equal(model.expired, false);
    }
});

test('the code is split into groups of four with thin spaces between them', () => {
    const model = viewModel({ code: 'ABCDEFGHIJKLMNOP', expiresAt: 100000 }, 0);
    assert.deepEqual(model.groups, ['ABCD', 'EFGH', 'IJKL', 'MNOP']);
    assert.equal(model.grouped, 'ABCD\u2009EFGH\u2009IJKL\u2009MNOP');
    assert.deepEqual(viewModel({ code: 'ABCD EFGH IJ', expiresAt: 100000 }, 0).groups, [
        'ABCD',
        'EFGH',
        'IJ',
    ]);
});
