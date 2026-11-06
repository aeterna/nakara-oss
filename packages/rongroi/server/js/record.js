'use strict';

// Saved report record caps and visual-hash facts. Node built-ins only.
//
// The server never decides whether a report is good or bad: it refuses records that are too large
// in shape and recomputes the hash so staff can compare it with the value the record carries.

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

const MAX_DEPTH = 32;
const MAX_STRING_BYTES = 8192;
const MAX_ARRAY_ITEMS = 10000;
const VISUAL_HASH_RE = /^[0-9a-f]{16}$/;

function isPlainObject(value) {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
    const proto = Object.getPrototypeOf(value);
    return proto === Object.prototype || proto === null;
}

// Returns a reason string on the first failure, or null when the value fits.
function checkCaps(value, depth) {
    if (depth > MAX_DEPTH) return 'depth';
    if (value === null) return null;
    const type = typeof value;
    if (type === 'boolean' || type === 'number') return null;
    if (type === 'string') {
        return Buffer.byteLength(value, 'utf8') > MAX_STRING_BYTES ? 'string' : null;
    }
    if (type !== 'object') return 'not_json';
    if (Array.isArray(value)) {
        if (value.length > MAX_ARRAY_ITEMS) return 'array';
        for (let i = 0; i < value.length; i++) {
            const reason = checkCaps(value[i], depth + 1);
            if (reason !== null) return reason;
        }
        return null;
    }
    if (!isPlainObject(value)) return 'not_json';
    const keys = Object.keys(value);
    for (const key of keys) {
        if (Buffer.byteLength(key, 'utf8') > MAX_STRING_BYTES) return 'string';
    }
    for (const key of keys) {
        const reason = checkCaps(value[key], depth + 1);
        if (reason !== null) return reason;
    }
    return null;
}

function checkRecordCaps(value) {
    const reason = checkCaps(value, 1);
    return reason === null ? { ok: true } : { ok: false, reason };
}

// First 64 bits of SHA-256 over the canonical record without its top-level `visual_hash` member.
function visualHash(record) {
    if (!isPlainObject(record)) throw new TypeError('record must be an object');
    const copy = { ...record };
    delete copy.visual_hash;
    const digest = crypto.createHash('sha256').update(canonicalize(copy), 'utf8').digest('hex');
    return digest.slice(0, 16);
}

// Never throws: a malformed record simply yields null where a fact cannot be stated.
function visualHashFact(record) {
    let recorded = null;
    try {
        if (record !== null && typeof record === 'object') {
            const value = record.visual_hash;
            if (typeof value === 'string' && VISUAL_HASH_RE.test(value)) recorded = value;
        }
    } catch {
        recorded = null;
    }
    let recomputed = null;
    try {
        recomputed = visualHash(record);
    } catch {
        recomputed = null;
    }
    const equal = recorded !== null && recomputed !== null ? recorded === recomputed : null;
    return { recorded, recomputed, equal };
}

// Loaded directly as a server_script FXServer provides no CommonJS `module`; the specs still get the export.
if (typeof module !== 'undefined') {
    module.exports = { checkRecordCaps, visualHash, visualHashFact };
}
