'use strict';

// Rongroi HTTP handler (ADR 0001, section 6): GET policy/<ticket> and a direct POST report. Chunked
// uploads, rate limits and the upload page are not part of this file; no client bytes are logged.

const crypto = require('crypto');

// FXServer resolves a relative require() against the resource root, not against the requiring file, so
// './envelope.js' only exists on plain Node. Try the file-relative path first and fall back to the
// resource-root path. This needs no fs probe beyond require() itself.
function isMissingModule(err) {
    if (!err) return false;
    return err.code === 'MODULE_NOT_FOUND' || /^Cannot find module\b/.test(err.message || '');
}

function loadModule(relative, rootRelative) {
    try { return relative(); }
    catch (err) {
        if (!isMissingModule(err)) throw err;
        return rootRelative();
    }
}

const { EnvelopeError, openEnvelope } = loadModule(
    () => require('./envelope.js'),
    () => require('./server/js/envelope.js'),
);
const { policyHash } = loadModule(
    () => require('./pairing.js'),
    () => require('./server/js/pairing.js'),
);
const TICKET_RE = /^[0-9a-f]{32}$/;
const SHA256_RE = /^[0-9a-f]{64}$/;
const DECIMAL_RE = /^[0-9]+$/;
const MAX_DIRECT_BYTES = 7168; // ADR 0089's direct POST limit
function reply(res, status, headers) {
    res.writeHead(status, { 'Content-Type': 'application/json', ...headers });
    res.send(JSON.stringify({ status }));
}

// The path relative to the resource, without leading slashes or a query string.
function requestPath(path) {
    if (typeof path !== 'string') return '';
    const query = path.indexOf('?');
    return (query === -1 ? path : path.slice(0, query)).replace(/^\/+/, '');
}
function createHandler({ store, kit, now, onReport, log = () => {} }) {
    function fail(res, status, message, ticket, headers) {
        if (ticket === undefined) log(message);
        else log(message, ticket);
        return reply(res, status, headers);
    }

    function handlePolicy(res, ticket) {
        if (typeof ticket !== 'string' || !TICKET_RE.test(ticket)) {
            return fail(res, 400, 'rongroi http: policy ticket rejected');
        }
        const found = store.lookup(ticket);
        if (!found) return fail(res, 404, 'rongroi http: policy ticket unknown', ticket);
        if (found.state === 'expired' || found.policy === null) {
            return fail(res, 410, 'rongroi http: policy ticket unavailable', ticket);
        }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.send(JSON.stringify({ ...found.policy, policy_hash: policyHash(found.policy) }));
    }

    function handleReport(req, res) {
        const headers = req.headers || {};
        const ticket = headers['x-rongroi-upload-id'];
        const sha = headers['x-rongroi-report-sha256'];
        if (typeof ticket !== 'string' || !TICKET_RE.test(ticket)
            || typeof sha !== 'string' || !SHA256_RE.test(sha)) {
            return fail(res, 400, 'rongroi http: report headers rejected');
        }
        const claimedLength = headers['content-length'];
        if (claimedLength !== undefined) {
            if (typeof claimedLength !== 'string' || !DECIMAL_RE.test(claimedLength)) {
                return fail(res, 400, 'rongroi http: report content-length rejected', ticket);
            }
            if (Number(claimedLength) > MAX_DIRECT_BYTES) {
                return fail(res, 413, 'rongroi http: report content-length too large', ticket);
            }
        }

        const begun = store.beginUpload(ticket, sha);
        if (!begun.ok) {
            if (begun.status === 429) {
                return fail(res, 429, 'rongroi http: report upload refused', ticket, { 'Retry-After': '5' });
            }
            return fail(res, begun.status, 'rongroi http: report upload refused', ticket);
        }
        if (begun.repeat) return reply(res, 200);

        const uploadId = begun.uploadId;
        req.setDataHandler((body) => {
            const raw = Buffer.isBuffer(body) ? body : Buffer.from(typeof body === 'string' ? body : '', 'utf8');
            if (raw.length > MAX_DIRECT_BYTES) {
                store.drop(uploadId);
                return fail(res, 413, 'rongroi http: report body too large', ticket);
            }
            if (crypto.createHash('sha256').update(raw).digest('hex') !== sha) {
                store.drop(uploadId);
                return fail(res, 422, 'rongroi http: report sha mismatch', ticket);
            }
            let opened;
            try {
                opened = openEnvelope(raw.toString('utf8'), kit.privateKey, kit.publicKey, ticket);
            } catch (err) {
                store.drop(uploadId);
                if (err instanceof EnvelopeError && err.code === 'malformed') {
                    return fail(res, 400, 'rongroi http: report envelope malformed', ticket);
                }
                if (err instanceof EnvelopeError && err.code === 'not_authentic') {
                    return fail(res, 422, 'rongroi http: report envelope not authentic', ticket);
                }
                return fail(res, 500, 'rongroi http: report envelope check failed', ticket);
            }
            let record;
            try {
                record = JSON.parse(opened);
            } catch {
                record = undefined;
            }
            if (record === null || typeof record !== 'object' || Array.isArray(record)) {
                store.drop(uploadId);
                return fail(res, 422, 'rongroi http: report record rejected', ticket);
            }
            const found = store.lookup(ticket);
            const nonce = found ? found.nonce : null;
            const binding = record.binding;
            if (binding === null || typeof binding !== 'object' || Array.isArray(binding)
                || binding.ticket !== ticket || binding.nonce !== nonce) {
                store.drop(uploadId);
                return fail(res, 422, 'rongroi http: report binding rejected', ticket);
            }
            const declined = record.scan === 'declined';
            if (!declined && record.schema !== 2) {
                store.drop(uploadId);
                return fail(res, 422, 'rongroi http: report schema rejected', ticket);
            }
            const consumed = store.consume(ticket, sha);
            if (!consumed.ok) {
                store.drop(uploadId);
                return fail(res, consumed.status, 'rongroi http: report consume refused', ticket);
            }
            if (consumed.repeat) return reply(res, 200);
            try {
                const event = { caseId: consumed.caseId, ticket, reportSha256: sha, receivedAt: now() };
                if (declined) event.declined = true;
                else event.record = record;
                onReport(event);
            } catch {
                log('rongroi http: onReport failed', ticket);
            }
            return reply(res, 200);
        });
    }
    return (req, res) => {
        const path = requestPath(req.path);
        const policy = /^policy\/([^/]+)$/.exec(path);
        if (policy) {
            if (req.method !== 'GET') return reply(res, 405);
            return handlePolicy(res, policy[1]);
        }
        if (path === 'report') {
            if (req.method !== 'POST') return reply(res, 405);
            return handleReport(req, res);
        }
        log('rongroi http: unknown path');
        return reply(res, 404);
    };
}

// Loaded directly as a server_script FXServer provides no CommonJS `module`; the specs still get the export.
if (typeof module !== 'undefined') {
    module.exports = { createHandler };
}
