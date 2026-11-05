'use strict';

// Kit key pair storage: create once, never overwrite silently, rotate.
const test = require('node:test');
const assert = require('node:assert/strict');
const keys = require('../server/js/keys.js');
const vectors = require('../test-vectors/envelope-v1.json');

function memoryKvp(initial) {
    const store = new Map(initial ? Object.entries(initial) : []);
    const writes = [];
    return {
        get(key) {
            return store.get(key);
        },
        set(key, value) {
            writes.push([key, value]);
            store.set(key, value);
        },
        store,
        writes,
    };
}

function isKey(value) {
    if (typeof value !== 'string') return false;
    const raw = Buffer.from(value, 'base64url');
    return raw.length === 32 && raw.toString('base64url') === value;
}

test('the first load creates and stores exactly one kit key pair', () => {
    const kvp = memoryKvp();
    const pair = keys.loadOrCreateKitKey(kvp);
    assert.ok(isKey(pair.publicKey));
    assert.ok(isKey(pair.privateKey));
    assert.equal(kvp.writes.length, 1);
    assert.equal(kvp.writes[0][0], 'rongroi:key:v1');
    const stored = JSON.parse(kvp.writes[0][1]);
    assert.deepEqual(Object.keys(stored), ['publicKey', 'privateKey']);
    assert.deepEqual(stored, pair);

    assert.deepEqual(keys.loadOrCreateKitKey(kvp), pair);
    assert.equal(kvp.writes.length, 1);
});

test('an existing key pair is returned without writing', () => {
    const kvp = memoryKvp({ 'rongroi:key:v1': JSON.stringify(vectors.kit) });
    assert.deepEqual(keys.loadOrCreateKitKey(kvp), vectors.kit);
    assert.equal(kvp.writes.length, 0);
});

test('a corrupted stored key is refused and never overwritten', () => {
    const bad = ['not json', '{}', JSON.stringify({ publicKey: 'x', privateKey: 'y' })];
    for (const value of bad) {
        const kvp = memoryKvp({ 'rongroi:key:v1': value });
        assert.throws(() => keys.loadOrCreateKitKey(kvp), /rongroi:key:v1/);
        assert.equal(kvp.writes.length, 0);
        assert.equal(kvp.store.get('rongroi:key:v1'), value);
    }
});

test('rotation stores a fresh pair and later loads return it', () => {
    const kvp = memoryKvp();
    const first = keys.loadOrCreateKitKey(kvp);
    const rotated = keys.rotateKitKey(kvp);
    assert.notEqual(rotated.privateKey, first.privateKey);
    assert.notEqual(rotated.publicKey, first.publicKey);
    assert.equal(kvp.writes.length, 2);
    assert.deepEqual(JSON.parse(kvp.writes[1][1]), rotated);
    assert.deepEqual(keys.loadOrCreateKitKey(kvp), rotated);
    assert.equal(kvp.writes.length, 2);
});

test('key material is never logged', () => {
    const kvp = memoryKvp();
    const output = [];
    const original = { log: console.log, warn: console.warn, error: console.error };
    console.log = console.warn = console.error = (...args) => output.push(args);
    try {
        const pair = keys.loadOrCreateKitKey(kvp);
        keys.rotateKitKey(kvp);
        assert.equal(output.length, 0);
        for (const secret of [pair.privateKey, kvp.store.get('rongroi:key:v1')]) {
            assert.equal(JSON.stringify(output).includes(secret), false);
        }
    } finally {
        console.log = original.log;
        console.warn = original.warn;
        console.error = original.error;
    }
});
