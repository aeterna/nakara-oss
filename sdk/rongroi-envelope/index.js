'use strict';

// Rongroi envelope v1 (aeterna-rongroi ADR 0089, section 5) and v2 (ADR 0097, section 4). Node `crypto` only.
//
// Wire form: UTF-8 JSON `{ "v": 1, "epk": b64url(32), "iv": b64url(12), "ct": b64url(n + 16) }`, members in
// this order. `epk` is the Connect per-report X25519 public key. `ct` is the AES-256-GCM ciphertext of the
// UTF-8 record followed by the 16-byte GCM tag.
//
// Key:  HKDF-SHA256(IKM = X25519(epk private, kit public), salt = ticket as its 32 lowercase hex ASCII bytes,
//       info = "rongroi-connect report v1" || kitPublic (32) || epk (32), length 32)
// AAD:  the ticket string as ASCII.
//
// v2 differs in two places: `"v": 2`, info starts with "rongroi-connect report v2", and the AAD is the JCS form of
// the binding `{ base_path, policy_hash, server_origin, ticket, transport }` (exact strings from the pairing code).
// A ticket accepts one version only: openEnvelope's `accept` (default 1) must equal the envelope's `v`.
//
// Keys and envelope members are base64url without padding. Key parameters are the server's own keys or the
// vector inputs; a bad one throws a TypeError. A bad envelope throws EnvelopeError: `malformed` or
// `not_authentic`.

const crypto = require('crypto');

const VERSIONS = [1, 2];
const INFO_LABELS = { 1: 'rongroi-connect report v1', 2: 'rongroi-connect report v2' };
const BASE_PATH_RE = /^[a-z0-9_-]{1,64}$/;
const TRANSPORTS = ['direct', 'relay'];
const BINDING_MEMBERS = ['base_path', 'policy_hash', 'server_origin', 'ticket', 'transport'];
const TICKET_RE = /^[0-9a-f]{32}$/;
const B64URL_RE = /^[A-Za-z0-9_-]*$/;
const KEY_BYTES = 32;
const IV_BYTES = 12;
const TAG_BYTES = 16;
const ENVELOPE_MEMBERS = ['ct', 'epk', 'iv', 'v'];

class EnvelopeError extends Error {
    constructor(code, message) {
        super(message);
        this.name = 'EnvelopeError';
        this.code = code;
    }
}

// Decode strict base64url: the alphabet, no padding, and a canonical re-encoding. Returns null on any fault.
function parseB64url(value, bytes) {
    if (typeof value !== 'string' || !B64URL_RE.test(value) || value.length % 4 === 1) return null;
    const buf = Buffer.from(value, 'base64url');
    if (buf.toString('base64url') !== value) return null;
    if (bytes !== undefined && buf.length !== bytes) return null;
    return buf;
}

function keyBytes(value, name, bytes = KEY_BYTES) {
    const buf = parseB64url(value, bytes);
    if (buf === null) throw new TypeError(`${name} must be ${bytes} bytes of base64url`);
    return buf;
}

function checkTicket(ticket) {
    if (typeof ticket !== 'string' || !TICKET_RE.test(ticket)) {
        throw new TypeError('ticket must be 32 lowercase hex characters');
    }
}

// Raw 32-byte X25519 keys as Node key objects. The private key is wrapped in a PKCS#8 header (RFC 8410).
const PKCS8_X25519_PREFIX = Buffer.from('302e020100300506032b656e04220420', 'hex');

function publicKeyObject(publicRaw) {
    return crypto.createPublicKey({ key: { kty: 'OKP', crv: 'X25519', x: publicRaw.toString('base64url') }, format: 'jwk' });
}

function privateKeyObject(privateRaw) {
    return crypto.createPrivateKey({
        key: Buffer.concat([PKCS8_X25519_PREFIX, privateRaw]),
        format: 'der',
        type: 'pkcs8',
    });
}

// Fresh X25519 key pair as raw 32-byte base64url values.
function generateKeyPair() {
    const { publicKey, privateKey } = crypto.generateKeyPairSync('x25519');
    return { publicKey: publicKey.export({ format: 'jwk' }).x, privateKey: privateKey.export({ format: 'jwk' }).d };
}

// X25519 shared secret of raw key buffers. Returns a 32-byte Buffer.
function agreeRaw(privateRaw, publicRaw) {
    return crypto.diffieHellman({ privateKey: privateKeyObject(privateRaw), publicKey: publicKeyObject(publicRaw) });
}

// X25519 shared secret from base64url keys.
function agree(privateKey, publicKey) {
    return agreeRaw(keyBytes(privateKey, 'privateKey'), keyBytes(publicKey, 'publicKey'));
}

// The v2 binding as its JCS bytes (flat object of strings, keys sorted). A bad binding throws a TypeError.
function bindingAad(binding) {
    if (binding === null || typeof binding !== 'object' || Array.isArray(binding)
        || Object.keys(binding).sort().join() !== BINDING_MEMBERS.join()) {
        throw new TypeError(`binding must have exactly the members ${BINDING_MEMBERS.join(', ')}`);
    }
    checkTicket(binding.ticket);
    if (typeof binding.base_path !== 'string' || !BASE_PATH_RE.test(binding.base_path) || binding.base_path === 'v1') {
        throw new TypeError('binding.base_path must match [a-z0-9_-]{1,64} and not be "v1"');
    }
    if (!TRANSPORTS.includes(binding.transport)) throw new TypeError('binding.transport must be direct or relay');
    for (const name of ['server_origin', 'policy_hash']) {
        if (typeof binding[name] !== 'string' || binding[name].length === 0) {
            throw new TypeError(`binding.${name} must be a non-empty string`);
        }
    }
    const sorted = {};
    for (const name of BINDING_MEMBERS) sorted[name] = binding[name];
    return Buffer.from(JSON.stringify(sorted), 'utf8');
}

// HKDF-SHA256 key for the envelope. All three key-like inputs are Buffers. `version` picks the info label.
function deriveKey(kitPublic, epk, sharedSecret, ticket, version = 1) {
    checkTicket(ticket);
    if (!VERSIONS.includes(version)) throw new TypeError('version must be 1 or 2');
    if (kitPublic.length !== KEY_BYTES || epk.length !== KEY_BYTES) {
        throw new TypeError('kitPublic and epk must be 32 bytes');
    }
    const info = Buffer.concat([Buffer.from(INFO_LABELS[version], 'utf8'), kitPublic, epk]);
    return Buffer.from(crypto.hkdfSync('sha256', sharedSecret, Buffer.from(ticket, 'ascii'), info, KEY_BYTES));
}

// Encrypt `plaintext` (a string, UTF-8) to the Kit's public key. Returns the envelope as a JSON string.
// `fixed` is for the test vectors only: `{ ephemeralPrivate, iv }` replaces the random ephemeral key and iv.
function sealEnvelope(plaintext, kitPublic, ticket, fixed) {
    checkTicket(ticket);
    return sealWith(1, plaintext, kitPublic, ticket, Buffer.from(ticket, 'ascii'), fixed);
}

// Envelope v2: the same, bound to the pairing code's five members (ADR 0097 section 4).
function sealEnvelopeV2(plaintext, kitPublic, binding, fixed) {
    const aad = bindingAad(binding);
    return sealWith(2, plaintext, kitPublic, binding.ticket, aad, fixed);
}

function sealWith(version, plaintext, kitPublic, ticket, aad, fixed) {
    if (typeof plaintext !== 'string') throw new TypeError('plaintext must be a string');
    const kitPub = keyBytes(kitPublic, 'kitPublic');

    let ephPriv;
    let ephPub;
    let iv;
    if (fixed) {
        ephPriv = keyBytes(fixed.ephemeralPrivate, 'ephemeralPrivate');
        ephPub = Buffer.from(crypto.createPublicKey(privateKeyObject(ephPriv)).export({ format: 'jwk' }).x, 'base64url');
        iv = keyBytes(fixed.iv, 'iv', IV_BYTES);
    } else {
        const pair = generateKeyPair();
        ephPriv = Buffer.from(pair.privateKey, 'base64url');
        ephPub = Buffer.from(pair.publicKey, 'base64url');
        iv = crypto.randomBytes(IV_BYTES);
    }

    const shared = agreeRaw(ephPriv, kitPub);
    const key = deriveKey(kitPub, ephPub, shared, ticket, version);
    const cipher = crypto.createCipheriv('aes-256-gcm', key, iv, { authTagLength: TAG_BYTES });
    cipher.setAAD(aad);
    const ct = Buffer.concat([cipher.update(Buffer.from(plaintext, 'utf8')), cipher.final(), cipher.getAuthTag()]);

    return JSON.stringify({
        v: version,
        epk: ephPub.toString('base64url'),
        iv: iv.toString('base64url'),
        ct: ct.toString('base64url'),
    });
}

// Decrypt an envelope JSON string for `ticket`. Returns the UTF-8 plaintext. `accept` is the one version this
// ticket was issued for (1 for rr1 codes, 2 for rr2); v2 needs the `binding` the Kit issued, with this ticket.
function openEnvelope(envelopeJson, kitPrivate, kitPublic, ticket, { accept = 1, binding } = {}) {
    const kitPriv = keyBytes(kitPrivate, 'kitPrivate');
    const kitPub = keyBytes(kitPublic, 'kitPublic');
    checkTicket(ticket);
    if (!VERSIONS.includes(accept)) throw new TypeError('accept must be 1 or 2');
    let aad = Buffer.from(ticket, 'ascii');
    if (accept === 2) {
        aad = bindingAad(binding);
        if (binding.ticket !== ticket) throw new TypeError('binding.ticket must equal ticket');
    }

    const env = parseEnvelope(envelopeJson);
    if (env.v !== accept) throw new EnvelopeError('malformed', `this ticket accepts envelope v${accept} only`);
    const epk = parseB64url(env.epk, KEY_BYTES);
    const iv = parseB64url(env.iv, IV_BYTES);
    const ct = parseB64url(env.ct);
    if (epk === null || iv === null || ct === null || ct.length < TAG_BYTES) {
        throw new EnvelopeError('malformed', 'envelope members are not valid base64url of the expected length');
    }

    let shared;
    try {
        shared = agreeRaw(kitPriv, epk);
    } catch {
        throw new EnvelopeError('malformed', 'epk is not a usable X25519 public key');
    }

    const key = deriveKey(kitPub, epk, shared, ticket, accept);
    const body = ct.subarray(0, ct.length - TAG_BYTES);
    const tag = ct.subarray(ct.length - TAG_BYTES);
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv, { authTagLength: TAG_BYTES });
    decipher.setAAD(aad);
    decipher.setAuthTag(tag);

    let plain;
    try {
        plain = Buffer.concat([decipher.update(body), decipher.final()]);
    } catch {
        throw new EnvelopeError('not_authentic', 'envelope does not authenticate for this ticket and kit key');
    }
    try {
        return new TextDecoder('utf-8', { fatal: true }).decode(plain);
    } catch {
        throw new EnvelopeError('malformed', 'authenticated plaintext is not UTF-8');
    }
}

// Check the envelope's shape: a JSON object with exactly the four members, v 1 or 2.
function parseEnvelope(envelopeJson) {
    if (typeof envelopeJson !== 'string') throw new EnvelopeError('malformed', 'envelope must be a JSON string');
    let env;
    try {
        env = JSON.parse(envelopeJson);
    } catch {
        throw new EnvelopeError('malformed', 'envelope is not JSON');
    }
    if (env === null || typeof env !== 'object' || Array.isArray(env)) {
        throw new EnvelopeError('malformed', 'envelope must be a JSON object');
    }
    if (Object.keys(env).sort().join() !== ENVELOPE_MEMBERS.join()) {
        throw new EnvelopeError('malformed', 'envelope must have exactly the members v, epk, iv, ct');
    }
    if (!VERSIONS.includes(env.v)) throw new EnvelopeError('malformed', 'unsupported envelope version');
    return env;
}

// Loaded directly as a server_script FXServer provides no CommonJS `module`; the specs still get the export.
if (typeof module !== 'undefined') {
    module.exports = {
        EnvelopeError,
        agree,
        bindingAad,
        deriveKey,
        generateKeyPair,
        openEnvelope,
        sealEnvelope,
        sealEnvelopeV2,
    };
}
