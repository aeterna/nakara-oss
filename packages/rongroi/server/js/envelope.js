'use strict';

// Rongroi envelope v1 (aeterna-rongroi ADR 0089, section 5). Node `crypto` only.
//
// Wire form: UTF-8 JSON `{ "v": 1, "epk": b64url(32), "iv": b64url(12), "ct": b64url(n + 16) }`, members in
// this order. `epk` is the Connect per-report X25519 public key. `ct` is the AES-256-GCM ciphertext of the
// UTF-8 record followed by the 16-byte GCM tag.
//
// Key:  HKDF-SHA256(IKM = X25519(epk private, kit public), salt = ticket as its 32 lowercase hex ASCII bytes,
//       info = "rongroi-connect report v1" || kitPublic (32) || epk (32), length 32)
// AAD:  the ticket string as ASCII.
//
// Keys and envelope members are base64url without padding. Key parameters are the server's own keys or the
// vector inputs; a bad one throws a TypeError. A bad envelope throws EnvelopeError: `malformed` or
// `not_authentic`.

const crypto = require('crypto');

const VERSION = 1;
const INFO_LABEL = 'rongroi-connect report v1';
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

// HKDF-SHA256 key for the envelope. All three key-like inputs are Buffers.
function deriveKey(kitPublic, epk, sharedSecret, ticket) {
    checkTicket(ticket);
    if (kitPublic.length !== KEY_BYTES || epk.length !== KEY_BYTES) {
        throw new TypeError('kitPublic and epk must be 32 bytes');
    }
    const info = Buffer.concat([Buffer.from(INFO_LABEL, 'utf8'), kitPublic, epk]);
    return Buffer.from(crypto.hkdfSync('sha256', sharedSecret, Buffer.from(ticket, 'ascii'), info, KEY_BYTES));
}

// Encrypt `plaintext` (a string, UTF-8) to the Kit's public key. Returns the envelope as a JSON string.
// `fixed` is for the test vectors only: `{ ephemeralPrivate, iv }` replaces the random ephemeral key and iv.
function sealEnvelope(plaintext, kitPublic, ticket, fixed) {
    if (typeof plaintext !== 'string') throw new TypeError('plaintext must be a string');
    const kitPub = keyBytes(kitPublic, 'kitPublic');
    checkTicket(ticket);

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
    const key = deriveKey(kitPub, ephPub, shared, ticket);
    const cipher = crypto.createCipheriv('aes-256-gcm', key, iv, { authTagLength: TAG_BYTES });
    cipher.setAAD(Buffer.from(ticket, 'ascii'));
    const ct = Buffer.concat([cipher.update(Buffer.from(plaintext, 'utf8')), cipher.final(), cipher.getAuthTag()]);

    return JSON.stringify({
        v: VERSION,
        epk: ephPub.toString('base64url'),
        iv: iv.toString('base64url'),
        ct: ct.toString('base64url'),
    });
}

// Decrypt an envelope JSON string for `ticket`. Returns the UTF-8 plaintext.
function openEnvelope(envelopeJson, kitPrivate, kitPublic, ticket) {
    const kitPriv = keyBytes(kitPrivate, 'kitPrivate');
    const kitPub = keyBytes(kitPublic, 'kitPublic');
    checkTicket(ticket);

    const env = parseEnvelope(envelopeJson);
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

    const key = deriveKey(kitPub, epk, shared, ticket);
    const body = ct.subarray(0, ct.length - TAG_BYTES);
    const tag = ct.subarray(ct.length - TAG_BYTES);
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv, { authTagLength: TAG_BYTES });
    decipher.setAAD(Buffer.from(ticket, 'ascii'));
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

// Check the envelope's shape: a JSON object with exactly the four members, v === 1.
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
    if (env.v !== VERSION) throw new EnvelopeError('malformed', 'unsupported envelope version');
    return env;
}

module.exports = {
    EnvelopeError,
    agree,
    deriveKey,
    generateKeyPair,
    openEnvelope,
    sealEnvelope,
};
