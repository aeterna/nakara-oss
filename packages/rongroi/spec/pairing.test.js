'use strict';

// Pairing code and policy digest (ADR 0089 sections 4-5).
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { generateKeyPair } = require('../server/js/envelope.js');
const { pairingCode, policyHash } = require('../server/js/pairing.js');

const kit = generateKeyPair();
const input = {
    serverOrigin: 'http://192.0.2.10:30120',
    ticket: 'a'.repeat(32),
    nonce: 'nonce-1',
    expiresAt: 1893456000000,
    policyHash: '0123456789abcdef',
    kitPublicKey: kit.publicKey,
};

function decode(code) {
    assert.ok(code.startsWith('rr1.'));
    const body = code.slice(4);
    assert.equal(Buffer.from(body, 'base64url').toString('base64url'), body);
    return JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
}

test('a pairing code round-trips to exactly the six members in order', () => {
    const decoded = decode(pairingCode(input));
    assert.deepEqual(decoded, {
        server_origin: input.serverOrigin,
        ticket: input.ticket,
        nonce: input.nonce,
        expires_at: '2030-01-01T00:00:00Z',
        policy_hash: input.policyHash,
        kit_public_key: input.kitPublicKey,
    });
    assert.deepEqual(Object.keys(decoded), [
        'server_origin',
        'ticket',
        'nonce',
        'expires_at',
        'policy_hash',
        'kit_public_key',
    ]);
});

test('expires_at is an ISO-8601 UTC timestamp with no milliseconds', () => {
    const decoded = decode(pairingCode({ ...input, expiresAt: 1893456000789 }));
    assert.match(decoded.expires_at, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
    assert.equal(decoded.expires_at, '2030-01-01T00:00:00Z');
});

test('http and https origins with names, IPv4 and bracketed IPv6 are accepted', () => {
    const origins = ['https://server.example', 'http://127.0.0.1:30120', 'https://[2001:db8::1]:8443'];
    for (const serverOrigin of origins) {
        assert.equal(decode(pairingCode({ ...input, serverOrigin })).server_origin, serverOrigin);
    }
});

test('hostile origins are refused', () => {
    const hostile = [
        'ftp://server.example',
        'javascript:alert(1)',
        'https://user:pass@server.example',
        'https://user@server.example',
        'https://server.example/path',
        'https://server.example/',
        'https://server.example?query',
        'https://server.example#fragment',
        '//server.example',
        'server.example:30120',
        'http://',
        'http://:30120',
        'http://server.example:0',
        'http://server.example:65536',
        'http://server.example:abc',
        'http://serve r.example',
        'http://server.example\\path',
        'http://[::1',
    ];
    for (const serverOrigin of hostile) {
        assert.throws(() => pairingCode({ ...input, serverOrigin }), TypeError, serverOrigin);
    }
});

test('malformed tickets, nonces, expiry, digests and key material are refused', () => {
    const bad = [
        { ticket: 'A'.repeat(32) },
        { ticket: 'a'.repeat(31) },
        { nonce: '' },
        { expiresAt: 1.5 },
        { expiresAt: Number.MAX_SAFE_INTEGER + 1 },
        { expiresAt: -1 },
        { policyHash: '0123456789ABCDEF' },
        { policyHash: '0'.repeat(15) },
        { kitPublicKey: 'not a key' },
        { kitPublicKey: Buffer.alloc(31).toString('base64url') },
    ];
    for (const change of bad) {
        assert.throws(() => pairingCode({ ...input, ...change }), TypeError, JSON.stringify(change));
    }
});

test('policyHash is the first 64 bits of SHA-256 over the canonical policy', () => {
    const policy = { version: 2, name: 'Example ✓', collectors: ['a', 'b'] };
    const canonical = '{"collectors":["a","b"],"name":"Example ✓","version":2}';
    const expected = crypto.createHash('sha256').update(canonical, 'utf8').digest('hex').slice(0, 16);
    assert.equal(policyHash(policy), expected);
    assert.match(policyHash(policy), /^[0-9a-f]{16}$/);
});

test('policyHash ignores a top-level policy_hash and does not mutate the policy', () => {
    const policy = { z: 1, policy_hash: 'ffffffffffffffff', a: 2 };
    assert.equal(policyHash(policy), policyHash({ z: 1, a: 2 }));
    assert.equal(policy.policy_hash, 'ffffffffffffffff');
    assert.deepEqual(Object.keys(policy), ['z', 'policy_hash', 'a']);
});

test('policyHash is order-independent, and floats and non-objects are refused', () => {
    assert.equal(policyHash({ a: 1, b: 2 }), policyHash({ b: 2, a: 1 }));
    assert.throws(() => policyHash({ a: 1.5 }), TypeError);
    assert.throws(() => policyHash(null), TypeError);
    assert.throws(() => policyHash([]), TypeError);
    // Only the top-level member is removed; a nested policy_hash is part of the digest.
    assert.notEqual(policyHash({ a: { policy_hash: 1 } }), policyHash({ a: {} }));
});
