'use strict';

// Pairing code and policy digest (ADR 0089 sections 4-5, ADR 0001 section 3). Node built-ins only.

const crypto = require('crypto');

// FXServer resolves a relative require() against the resource root, not against the requiring file, so
// './canonical.js' only exists on plain Node. Try the file-relative path first and fall back to the
// resource-root path. This needs no fs probe beyond require() itself.
function isMissingModule(err) {
    if (!err) return false;
    return err.code === 'MODULE_NOT_FOUND' || /^Cannot find module\b/.test(err.message || '');
}

function loadCanonical() {
    try {
        return require('./canonical.js');
    } catch (err) {
        if (!isMissingModule(err)) throw err;
        return require('./server/js/canonical.js');
    }
}

const { canonicalize } = loadCanonical();

const PREFIX = 'rr1.';
const ORIGIN_RE = /^(https?):\/\/(\[[0-9a-f:.]+\]|[a-z0-9.-]+)(?::([0-9]{1,5}))?$/i;
const TICKET_RE = /^[0-9a-f]{32}$/;
const POLICY_HASH_RE = /^[0-9a-f]{16}$/;
const B64URL_RE = /^[A-Za-z0-9_-]+$/;
const KEY_BYTES = 32;

// An origin the player's PC can reach: scheme://host[:port], no path, query, fragment or userinfo.
function checkOrigin(origin) {
    if (typeof origin !== 'string') throw new TypeError('serverOrigin must be a string');
    const match = ORIGIN_RE.exec(origin);
    if (!match) {
        throw new TypeError('serverOrigin must be http(s)://host[:port] with no path or userinfo');
    }
    if (match[3] !== undefined) {
        const port = Number(match[3]);
        if (port < 1 || port > 65535) throw new TypeError('serverOrigin port must be 1-65535');
    }
    let url;
    try {
        url = new URL(origin);
    } catch {
        throw new TypeError('serverOrigin is not a valid origin');
    }
    if (url.username || url.password || url.pathname !== '/' || url.search || url.hash) {
        throw new TypeError('serverOrigin must be http(s)://host[:port] with no path or userinfo');
    }
    return origin;
}

function checkTicket(ticket) {
    if (typeof ticket !== 'string' || !TICKET_RE.test(ticket)) {
        throw new TypeError('ticket must be 32 lowercase hex characters');
    }
    return ticket;
}

function checkNonce(nonce) {
    if (typeof nonce !== 'string' || nonce.length === 0) throw new TypeError('nonce must be a non-empty string');
    return nonce;
}

function checkExpiresAt(expiresAt) {
    if (!Number.isSafeInteger(expiresAt) || expiresAt < 0) {
        throw new TypeError('expiresAt must be a non-negative integer');
    }
    return expiresAt;
}

// ISO-8601 UTC without milliseconds, the only form the Connect pairing reader accepts.
function formatExpiresAt(expiresAt) {
    return new Date(expiresAt).toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function checkPolicyHash(hash) {
    if (typeof hash !== 'string' || !POLICY_HASH_RE.test(hash)) {
        throw new TypeError('policyHash must be 16 lowercase hex characters');
    }
    return hash;
}

function checkKitPublicKey(value) {
    if (typeof value !== 'string' || !B64URL_RE.test(value)) {
        throw new TypeError('kitPublicKey must be 32 bytes of base64url');
    }
    const raw = Buffer.from(value, 'base64url');
    if (raw.length !== KEY_BYTES || raw.toString('base64url') !== value) {
        throw new TypeError('kitPublicKey must be 32 bytes of base64url');
    }
    return value;
}

// `rr1.` plus base64url of the six-member JSON object, in this order.
function pairingCode(input) {
    if (input === null || typeof input !== 'object' || Array.isArray(input)) {
        throw new TypeError('pairing code input must be an object');
    }
    const { serverOrigin, ticket, nonce, expiresAt, policyHash: hash, kitPublicKey } = input;
    checkOrigin(serverOrigin);
    checkTicket(ticket);
    checkNonce(nonce);
    checkExpiresAt(expiresAt);
    checkPolicyHash(hash);
    checkKitPublicKey(kitPublicKey);

    const payload = {
        server_origin: serverOrigin,
        ticket,
        nonce,
        expires_at: formatExpiresAt(expiresAt),
        policy_hash: hash,
        kit_public_key: kitPublicKey,
    };
    return PREFIX + Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
}

// First 64 bits of SHA-256 over the canonical policy without its top-level `policy_hash` member.
function policyHash(policy) {
    if (policy === null || typeof policy !== 'object' || Array.isArray(policy)) {
        throw new TypeError('policy must be an object');
    }
    const body = { ...policy };
    delete body.policy_hash;
    const digest = crypto.createHash('sha256').update(canonicalize(body), 'utf8').digest('hex');
    return digest.slice(0, 16);
}

// Loaded directly as a server_script FXServer provides no CommonJS `module`; the specs still get the export.
if (typeof module !== 'undefined') {
    module.exports = { pairingCode, policyHash };
}
