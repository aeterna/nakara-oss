'use strict';

// Startup self-test. When the resource starts it checks the envelope code against the shared vector file
// (test-vectors/envelope-v1.json, also used by Connect) and prints exactly one line. The line never contains
// key material. A failure names the step: x25519, hkdf or aes-gcm.

const envelope = require('./envelope.js');

const PREFIX = 'nakara_rongroi selftest: ';
const VECTOR_FILE = 'test-vectors/envelope-v1.json';

const bytes = (value) => Buffer.from(value, 'base64url');

function fail(step, message) {
    return `${PREFIX}fail ${step} ${message}`;
}

// Returns the single result line for the vector set `v` (already parsed).
function runSelfTest(v) {
    let step = 'x25519';
    try {
        const pair = envelope.generateKeyPair();
        if (bytes(pair.publicKey).length !== 32 || bytes(pair.privateKey).length !== 32) {
            return fail(step, 'generated key is not 32 bytes');
        }
        const fromKit = envelope.agree(v.kit.privateKey, v.ephemeral.publicKey);
        const fromEphemeral = envelope.agree(v.ephemeral.privateKey, v.kit.publicKey);
        if (!fromKit.equals(fromEphemeral) || fromKit.toString('base64url') !== v.sharedSecret) {
            return fail(step, 'shared secret differs from the vector');
        }

        step = 'hkdf';
        const key = envelope.deriveKey(bytes(v.kit.publicKey), bytes(v.ephemeral.publicKey), bytes(v.sharedSecret), v.ticket);
        if (key.toString('base64url') !== v.derivedKey) {
            return fail(step, 'derived key differs from the vector');
        }

        step = 'aes-gcm';
        const opened = envelope.openEnvelope(JSON.stringify(v.envelope), v.kit.privateKey, v.kit.publicKey, v.ticket);
        if (opened !== v.plaintext) {
            return fail(step, 'envelope does not open to the vector plaintext');
        }
        const sealed = envelope.sealEnvelope(v.plaintext, v.kit.publicKey, v.ticket, {
            ephemeralPrivate: v.ephemeral.privateKey,
            iv: v.iv,
        });
        if (sealed !== JSON.stringify(v.envelope)) {
            return fail(step, 'sealed envelope differs from the vector');
        }
    } catch (err) {
        const reason = (err && (err.code || err.name)) || 'error';
        return fail(step, `threw ${reason}`);
    }
    return `${PREFIX}ok x25519 hkdf aes-gcm`;
}

function loadVectors() {
    const text = LoadResourceFile(GetCurrentResourceName(), VECTOR_FILE);
    return typeof text === 'string' ? JSON.parse(text) : null;
}

function runOnStart() {
    let vectors = null;
    try {
        vectors = loadVectors();
    } catch {
        vectors = null;
    }
    console.log(vectors ? runSelfTest(vectors) : fail('vectors', 'vector file is not readable'));
}

// FXServer provides LoadResourceFile and GetCurrentResourceName. Plain Node (the specs) does not, so the
// check runs only inside a server.
if (typeof LoadResourceFile === 'function' && typeof GetCurrentResourceName === 'function') {
    runOnStart();
}

module.exports = { runSelfTest };
