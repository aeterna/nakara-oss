// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
'use strict';

// Envelope v2 tests (aeterna-rongroi ADR 0097 section 4). Connect and the SDK run the same vector file
// (test-vectors/envelope-v2.json).
const test = require('node:test');
const assert = require('node:assert/strict');
const rongroi = require('../server/js/envelope.js');
const v1 = require('../test-vectors/envelope-v1.json');
const vectors = require('../test-vectors/envelope-v2.json');

const { kit, ephemeral, iv, plaintext, binding, aad, derivedKey } = vectors;
const vectorEnvelope = vectors.envelope;
const isCode = (code) => (err) => err instanceof rongroi.EnvelopeError && err.code === code;

test('v2: additional data is the JCS form of the five binding members', () => {
    assert.equal(rongroi.bindingAad(binding).toString('utf8'), aad);
});

test('v2: sealing the vector inputs reproduces the vector envelope byte for byte', () => {
    const sealed = rongroi.sealEnvelopeV2(plaintext, kit.publicKey, binding, { ephemeralPrivate: ephemeral.privateKey, iv });
    assert.equal(sealed, JSON.stringify(vectorEnvelope));
});

test('v2: the derived key uses the v2 label and matches the vector', () => {
    const shared = rongroi.agree(kit.privateKey, ephemeral.publicKey);
    const key = rongroi.deriveKey(Buffer.from(kit.publicKey, 'base64url'), Buffer.from(ephemeral.publicKey, 'base64url'),
        shared, binding.ticket, 2);
    assert.equal(key.toString('base64url'), derivedKey);
});

test('v2: the vector opens with the same binding and accept 2', () => {
    const opened = rongroi.openEnvelope(JSON.stringify(vectorEnvelope), kit.privateKey, kit.publicKey, binding.ticket,
        { accept: 2, binding });
    assert.equal(opened, plaintext);
});

test('v2: a changed binding member does not authenticate', () => {
    for (const [member, value] of [['server_origin', 'https://relay.example.net'], ['base_path', 'other'],
        ['transport', 'direct'], ['policy_hash', 'f'.repeat(16)]]) {
        assert.throws(() => rongroi.openEnvelope(JSON.stringify(vectorEnvelope), kit.privateKey, kit.publicKey,
            binding.ticket, { accept: 2, binding: { ...binding, [member]: value } }), isCode('not_authentic'), member);
    }
});

test('v2: a ticket issued for one version refuses the other', () => {
    assert.throws(() => rongroi.openEnvelope(JSON.stringify(vectorEnvelope), kit.privateKey, kit.publicKey,
        binding.ticket, { accept: 1 }), isCode('malformed'));
    assert.throws(() => rongroi.openEnvelope(JSON.stringify(v1.envelope), v1.kit.privateKey, v1.kit.publicKey,
        v1.ticket, { accept: 2, binding: { ...binding, ticket: v1.ticket } }), isCode('malformed'));
});

test('v2: default accept stays 1, so existing callers keep v1 only', () => {
    assert.equal(rongroi.openEnvelope(JSON.stringify(v1.envelope), v1.kit.privateKey, v1.kit.publicKey, v1.ticket),
        v1.plaintext);
    assert.throws(() => rongroi.openEnvelope(JSON.stringify(vectorEnvelope), kit.privateKey, kit.publicKey,
        binding.ticket), isCode('malformed'));
});

test('v2: a binding with a bad member or a different ticket is refused before decryption', () => {
    const bad = [
        { ...binding, base_path: 'v1' }, { ...binding, base_path: 'Bad/Path' }, { ...binding, transport: 'smoke' },
        { ...binding, server_origin: '' }, { ...binding, policy_hash: 3 }, { ...binding, extra: 'x' },
    ];
    for (const b of bad) assert.throws(() => rongroi.bindingAad(b), TypeError, JSON.stringify(b));
    assert.throws(() => rongroi.openEnvelope(JSON.stringify(vectorEnvelope), kit.privateKey, kit.publicKey,
        'e'.repeat(32), { accept: 2, binding }), TypeError);
});
