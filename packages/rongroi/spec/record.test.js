'use strict';

// Saved report records: shape caps and visual-hash facts.
const test = require('node:test');
const assert = require('node:assert/strict');
const { checkRecordCaps, visualHash, visualHashFact } = require('../server/js/record.js');

const vector = require('../test-vectors/visual-hash-v1.json');

function reverseKeys(value) {
    if (Array.isArray(value)) return value.map(reverseKeys);
    if (value !== null && typeof value === 'object') {
        const out = {};
        for (const key of Object.keys(value).reverse()) out[key] = reverseKeys(value[key]);
        return out;
    }
    return value;
}

function nestedObjects(depth) {
    let value = {};
    for (let i = 1; i < depth; i++) value = { child: value };
    return value;
}

function nestedArrays(depth) {
    let value = [];
    for (let i = 1; i < depth; i++) value = [value];
    return value;
}

test('the saved vector hashes to its own visual_hash', () => {
    assert.equal(visualHash(vector), '5777137e45484779');
    assert.equal(visualHash(vector), vector.visual_hash);
});

test('reordering top-level and nested keys does not change the hash', () => {
    assert.equal(visualHash(reverseKeys(vector)), visualHash(vector));
});

test('only the top-level visual_hash member is left out of the hashed bytes', () => {
    const withoutHash = { ...vector };
    delete withoutHash.visual_hash;
    assert.match(visualHash(withoutHash), /^[0-9a-f]{16}$/);

    const withNested = { view: { visual_hash: '0123456789abcdef' } };
    const withoutNested = { view: {} };
    assert.notEqual(visualHash(withNested), visualHash(withoutNested));
});

test('visualHashFact states recorded, recomputed and equal without judging the report', () => {
    assert.deepEqual(visualHashFact(vector), {
        recorded: '5777137e45484779',
        recomputed: '5777137e45484779',
        equal: true,
    });

    const changed = visualHashFact({ ...vector, rongroi_version: '9.9.9' });
    assert.equal(changed.recorded, vector.visual_hash);
    assert.equal(changed.equal, false);

    const malformed = visualHashFact({ ...vector, visual_hash: 'ABC' });
    assert.equal(malformed.recorded, null);
    assert.equal(malformed.equal, null);

    const float = visualHashFact({ x: 1.5 });
    assert.equal(float.recorded, null);
    assert.equal(float.recomputed, null);
    assert.equal(float.equal, null);

    assert.deepEqual(visualHashFact(null), { recorded: null, recomputed: null, equal: null });
    assert.deepEqual(visualHashFact([]), { recorded: null, recomputed: null, equal: null });
});

test('visualHash refuses records that are not plain objects', () => {
    for (const value of [null, [], 'record']) {
        assert.throws(() => visualHash(value), TypeError);
    }
});

test('checkRecordCaps stops at 32 levels of nesting', () => {
    assert.deepEqual(checkRecordCaps(nestedObjects(32)), { ok: true });
    assert.deepEqual(checkRecordCaps(nestedObjects(33)), { ok: false, reason: 'depth' });
    assert.deepEqual(checkRecordCaps(nestedArrays(32)), { ok: true });
    assert.deepEqual(checkRecordCaps(nestedArrays(33)), { ok: false, reason: 'depth' });
});

test('checkRecordCaps measures strings and keys in UTF-8 bytes', () => {
    assert.deepEqual(checkRecordCaps('a'.repeat(8192)), { ok: true });
    assert.deepEqual(checkRecordCaps('a'.repeat(8193)), { ok: false, reason: 'string' });
    assert.deepEqual(checkRecordCaps({ ['k'.repeat(8193)]: 1 }), { ok: false, reason: 'string' });
    assert.deepEqual(checkRecordCaps({ s: 'é'.repeat(4096) }), { ok: true });
    assert.deepEqual(checkRecordCaps({ s: 'é'.repeat(4097) }), { ok: false, reason: 'string' });
});

test('checkRecordCaps limits arrays but not object keys', () => {
    assert.deepEqual(checkRecordCaps(new Array(10000).fill(0)), { ok: true });
    assert.deepEqual(checkRecordCaps(new Array(10001).fill(0)), { ok: false, reason: 'array' });
});

test('checkRecordCaps refuses values JSON cannot carry', () => {
    assert.deepEqual(checkRecordCaps({ a: undefined }), { ok: false, reason: 'not_json' });
    assert.deepEqual(checkRecordCaps({ a: () => {} }), { ok: false, reason: 'not_json' });
    assert.deepEqual(checkRecordCaps({ a: Symbol('x') }), { ok: false, reason: 'not_json' });
});

test('the saved vector passes the caps', () => {
    assert.deepEqual(checkRecordCaps(vector), { ok: true });
});

test('record exports exactly the three report helpers', () => {
    const record = require('../server/js/record.js');
    assert.deepEqual(Object.keys(record).sort(), ['checkRecordCaps', 'visualHash', 'visualHashFact']);
});
