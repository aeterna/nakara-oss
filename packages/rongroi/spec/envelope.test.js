'use strict';

// Envelope v1 tests. Connect runs the same vector file (test-vectors/envelope-v1.json).
const test = require('node:test');
const assert = require('node:assert/strict');
const rongroi = require('../server/js/envelope.js');
const vectors = require('../test-vectors/envelope-v1.json');

const { ticket, kit, ephemeral, iv, plaintext, sharedSecret, derivedKey } = vectors;
const vectorEnvelope = vectors.envelope;
const otherTicket = 'f'.repeat(32);

// Build a tampered envelope string from the vector envelope, overriding some members.
function withMembers(changes) {
    return JSON.stringify({ ...vectorEnvelope, ...changes });
}

function assertErrorCode(code) {
    return (err) => err instanceof rongroi.EnvelopeError && err.code === code;
}

test('the vector envelope decrypts to the vector plaintext exactly', () => {
    const opened = rongroi.openEnvelope(JSON.stringify(vectorEnvelope), kit.privateKey, kit.publicKey, ticket);
    assert.equal(opened, plaintext);
});

test('sealing the vector inputs reproduces the vector envelope byte for byte', () => {
    const sealed = rongroi.sealEnvelope(plaintext, kit.publicKey, ticket, {
        ephemeralPrivate: ephemeral.privateKey,
        iv,
    });
    assert.equal(sealed, JSON.stringify(vectorEnvelope));
});

test('X25519 agreement matches the vector shared secret from both sides', () => {
    const fromKit = rongroi.agree(kit.privateKey, ephemeral.publicKey);
    const fromEphemeral = rongroi.agree(ephemeral.privateKey, kit.publicKey);
    assert.equal(fromKit.toString('base64url'), sharedSecret);
    assert.deepEqual(fromEphemeral, fromKit);
});

test('HKDF derives the vector key from the shared secret, ticket, kit key and epk', () => {
    const key = rongroi.deriveKey(
        Buffer.from(kit.publicKey, 'base64url'),
        Buffer.from(ephemeral.publicKey, 'base64url'),
        Buffer.from(sharedSecret, 'base64url'),
        ticket,
    );
    assert.equal(key.toString('base64url'), derivedKey);
});

test('generated keys are 32-byte base64url values and seal/open round-trips', () => {
    const pair = rongroi.generateKeyPair();
    assert.equal(Buffer.from(pair.publicKey, 'base64url').length, 32);
    assert.equal(Buffer.from(pair.privateKey, 'base64url').length, 32);
    assert.equal(pair.publicKey.length, 43);

    const text = 'round trip é ✓';
    const sealed = rongroi.sealEnvelope(text, pair.publicKey, ticket);
    assert.equal(rongroi.openEnvelope(sealed, pair.privateKey, pair.publicKey, ticket), text);

    const env = JSON.parse(sealed);
    assert.deepEqual(Object.keys(env), ['v', 'epk', 'iv', 'ct']);
    assert.equal(env.v, 1);
    assert.equal(Buffer.from(env.iv, 'base64url').length, 12);
    assert.equal(Buffer.from(env.ct, 'base64url').length, Buffer.byteLength(text) + 16);
});

test('each seal uses a fresh ephemeral key and a fresh iv', () => {
    const pair = rongroi.generateKeyPair();
    const a = JSON.parse(rongroi.sealEnvelope('same', pair.publicKey, ticket));
    const b = JSON.parse(rongroi.sealEnvelope('same', pair.publicKey, ticket));
    assert.notEqual(a.epk, b.epk);
    assert.notEqual(a.iv, b.iv);
});

test('a wrong ticket is not_authentic', () => {
    assert.throws(
        () => rongroi.openEnvelope(JSON.stringify(vectorEnvelope), kit.privateKey, kit.publicKey, otherTicket),
        assertErrorCode('not_authentic'),
    );
});

test('a flipped byte in the ciphertext body or the tag is not_authentic', () => {
    const ct = Buffer.from(vectorEnvelope.ct, 'base64url');
    for (const index of [0, ct.length - 1]) {
        const flipped = Buffer.from(ct);
        flipped[index] ^= 0x01;
        const env = withMembers({ ct: flipped.toString('base64url') });
        assert.throws(
            () => rongroi.openEnvelope(env, kit.privateKey, kit.publicKey, ticket),
            assertErrorCode('not_authentic'),
            `flipped byte ${index} must not authenticate`,
        );
    }
});

test('a bad base64url member is malformed', () => {
    const epk = vectorEnvelope.epk;
    const bad = [
        withMembers({ ct: vectorEnvelope.ct + '=' }),
        withMembers({ epk: epk.slice(0, -1) + '!' }),
        withMembers({ iv: vectorEnvelope.iv.replace(/[A-Za-z0-9]/, '+') }),
        withMembers({ iv: vectorEnvelope.iv.slice(0, -1) + ' ' }),
        'not json',
        '[]',
    ];
    for (const text of bad) {
        assert.throws(
            () => rongroi.openEnvelope(text, kit.privateKey, kit.publicKey, ticket),
            assertErrorCode('malformed'),
            `input must be malformed: ${text.slice(0, 60)}`,
        );
    }
});

test('a wrong v is malformed', () => {
    for (const v of [2, 0, '1', null]) {
        assert.throws(
            () => rongroi.openEnvelope(withMembers({ v }), kit.privateKey, kit.publicKey, ticket),
            assertErrorCode('malformed'),
            `v=${JSON.stringify(v)} must be malformed`,
        );
    }
});

test('a short epk is malformed', () => {
    const shortEpk = Buffer.from(ephemeral.publicKey, 'base64url').subarray(0, 31).toString('base64url');
    assert.throws(
        () => rongroi.openEnvelope(withMembers({ epk: shortEpk }), kit.privateKey, kit.publicKey, ticket),
        assertErrorCode('malformed'),
    );
});

test('a short iv, a ct without a tag, or an extra member is malformed', () => {
    const cases = [
        withMembers({ iv: Buffer.alloc(11).toString('base64url') }),
        withMembers({ ct: Buffer.alloc(15).toString('base64url') }),
        JSON.stringify({ ...vectorEnvelope, extra: 'x' }),
    ];
    for (const text of cases) {
        assert.throws(
            () => rongroi.openEnvelope(text, kit.privateKey, kit.publicKey, ticket),
            assertErrorCode('malformed'),
        );
    }
});
