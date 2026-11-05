'use strict';

// Kit key pair storage (ADR 0001 section 3). The private key lives in KVP `rongroi:key:v1` and is written
// once. Nothing here logs key material.

// FXServer resolves a relative require() against the resource root, not against the requiring file, so
// './envelope.js' only exists on plain Node. Try the file-relative path first and fall back to the
// resource-root path. This needs no fs probe beyond require() itself.
function isMissingModule(err) {
    if (!err) return false;
    return err.code === 'MODULE_NOT_FOUND' || /^Cannot find module\b/.test(err.message || '');
}

function loadEnvelope() {
    try {
        return require('./envelope.js');
    } catch (err) {
        if (!isMissingModule(err)) throw err;
        return require('./server/js/envelope.js');
    }
}

const envelope = loadEnvelope();

const KVP_KEY = 'rongroi:key:v1';
const KEY_BYTES = 32;
const B64URL_RE = /^[A-Za-z0-9_-]+$/;

function checkKvp(kvp) {
    if (!kvp || typeof kvp.get !== 'function' || typeof kvp.set !== 'function') {
        throw new TypeError('kvp must provide get(key) and set(key, value)');
    }
}

function checkKey(value, name) {
    if (typeof value !== 'string' || !B64URL_RE.test(value)) {
        throw new Error(`${KVP_KEY} has an invalid ${name}`);
    }
    const raw = Buffer.from(value, 'base64url');
    if (raw.length !== KEY_BYTES || raw.toString('base64url') !== value) {
        throw new Error(`${KVP_KEY} has an invalid ${name}`);
    }
    return value;
}

function parseStoredKey(stored) {
    let parsed;
    try {
        parsed = JSON.parse(stored);
    } catch {
        throw new Error(`${KVP_KEY} is not valid JSON`);
    }
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new Error(`${KVP_KEY} must hold a key pair`);
    }
    if (Object.keys(parsed).sort().join() !== 'privateKey,publicKey') {
        throw new Error(`${KVP_KEY} must hold exactly publicKey and privateKey`);
    }
    checkKey(parsed.publicKey, 'publicKey');
    checkKey(parsed.privateKey, 'privateKey');
    return { publicKey: parsed.publicKey, privateKey: parsed.privateKey };
}

// Read the Kit key pair, creating and storing one the first time only.
function loadOrCreateKitKey(kvp) {
    checkKvp(kvp);
    const stored = kvp.get(KVP_KEY);
    if (stored !== undefined && stored !== null) return parseStoredKey(stored);
    const pair = envelope.generateKeyPair();
    kvp.set(KVP_KEY, JSON.stringify(pair));
    return { publicKey: pair.publicKey, privateKey: pair.privateKey };
}

// Replace the Kit key pair. The caller invalidates open tickets; stored reports stay decrypted.
function rotateKitKey(kvp) {
    checkKvp(kvp);
    const pair = envelope.generateKeyPair();
    kvp.set(KVP_KEY, JSON.stringify(pair));
    return { publicKey: pair.publicKey, privateKey: pair.privateKey };
}

// Loaded directly as a server_script FXServer provides no CommonJS `module`; the specs still get the export.
if (typeof module !== 'undefined') {
    module.exports = { KVP_KEY, loadOrCreateKitKey, rotateKitKey };
}
