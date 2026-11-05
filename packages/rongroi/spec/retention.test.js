'use strict';

// Retention tests: the setting is clamped to 1..365 with a default of 30, and a case is due when its last
// activity (consumedAt, else openedAt) is at least the retention window old.
const test = require('node:test');
const assert = require('node:assert/strict');
const { clampDays, dueCases } = require('../server/js/retention.js');

const DAY = 86400000;
const NOW = 100 * DAY;

test('clampDays: defaults, bounds and floors', () => {
    assert.equal(clampDays(undefined), 30);
    assert.equal(clampDays(NaN), 30);
    assert.equal(clampDays(0), 1);
    assert.equal(clampDays(1), 1);
    assert.equal(clampDays(365), 365);
    assert.equal(clampDays(366), 365);
    assert.equal(clampDays(12.9), 12);
});

test('dueCases: a consumed case is due from consumedAt', () => {
    const entries = [{ caseId: 'a', openedAt: NOW, consumedAt: NOW - 2 * DAY }];
    assert.deepEqual(dueCases(entries, NOW, 2), ['a']);
});

test('dueCases: an open case is due from openedAt', () => {
    const entries = [
        { caseId: 'old', openedAt: NOW - 5 * DAY, consumedAt: null },
        { caseId: 'new', openedAt: NOW - DAY, consumedAt: null },
    ];
    assert.deepEqual(dueCases(entries, NOW, 3), ['old']);
});

test('dueCases: exactly at the limit is due, just under is not', () => {
    const entries = [
        { caseId: 'exact', openedAt: null, consumedAt: NOW - 3 * DAY },
        { caseId: 'under', openedAt: null, consumedAt: NOW - 3 * DAY + 1 },
    ];
    assert.deepEqual(dueCases(entries, NOW, 3), ['exact']);
});

test('dueCases: consumedAt wins over an older openedAt', () => {
    const entries = [{ caseId: 'recent', openedAt: NOW - 10 * DAY, consumedAt: NOW - DAY }];
    assert.deepEqual(dueCases(entries, NOW, 2), []);
});

test('dueCases: an entry with neither timestamp is left out', () => {
    const entries = [{ caseId: 'none' }, { caseId: 'nulls', openedAt: null, consumedAt: null }];
    assert.deepEqual(dueCases(entries, NOW, 1), []);
});
