'use strict';

// RFC 8785 canonical JSON: UTF-16 key order, JCS string escapes, integers only.
const test = require('node:test');
const assert = require('node:assert/strict');
const { canonicalize } = require('../server/js/canonical.js');

test('object keys sort by UTF-16 code units, nested too', () => {
    assert.equal(canonicalize({ b: 1, a: 2 }), '{"a":2,"b":1}');
    assert.equal(canonicalize({ b: { d: 1, c: 2 }, a: 3 }), '{"a":3,"b":{"c":2,"d":1}}');
    // U+10000 begins with a high surrogate (0xD800), so it sorts before U+FFFF.
    assert.equal(canonicalize({ '\uFFFF': 1, '\u{10000}': 2 }), '{"\u{10000}":2,"\uFFFF":1}');
});

test('strings use JCS escapes and leave non-ASCII alone', () => {
    const value = 'a"b\\c\n\t\u0000\u001f/é';
    assert.equal(canonicalize({ s: value }), '{"s":"a\\"b\\\\c\\n\\t\\u0000\\u001f/é"}');
    assert.equal(canonicalize('\u0008\u000c\u000d'), '"\\b\\f\\r"');
});

test('arrays keep their order and objects inside them are canonical', () => {
    assert.equal(canonicalize([3, { b: 'x', a: true }, null]), '[3,{"a":true,"b":"x"},null]');
});

test('only safe integers are encoded', () => {
    assert.equal(
        canonicalize({ a: 0, b: -12, c: Number.MAX_SAFE_INTEGER }),
        '{"a":0,"b":-12,"c":9007199254740991}',
    );
    assert.equal(canonicalize([-0, 1]), '[0,1]');
    for (const value of [1.5, -0.25, 1e-7, NaN, Infinity, -Infinity, 2 ** 53]) {
        assert.throws(() => canonicalize({ n: value }), TypeError, `must refuse ${String(value)}`);
    }
});

test('values JSON cannot carry and lone surrogates are refused', () => {
    for (const value of [undefined, () => {}, Symbol('x')]) {
        assert.throws(() => canonicalize({ value }), TypeError);
    }
    assert.throws(() => canonicalize('\ud800'), TypeError);
});
