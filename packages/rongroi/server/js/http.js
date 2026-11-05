'use strict';

// Rongroi HTTP handler (ADR 0001, section 6): GET policy/<ticket>, a direct POST report and chunked
// POST report/chunk uploads. Rate limits and the upload page are not part of this file; no client bytes
// are logged.

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
const MAX_SLICE_BYTES = 4096;  // ADR 0001 section 6's slice size
const MAX_CHUNK_TOTAL = 512;   // 2 MiB at 4 KiB per slice
const RATE_WINDOW_MS = 60000;  // fixed rate-limit window
const MAX_ADDRESS_REQUESTS = 30; // policy GETs and unknown report/chunk per address
const MAX_SLICES_PER_TICKET = 600; // chunk requests per ticket
function reply(res, status, headers) {
    res.writeHead(status, { 'Content-Type': 'application/json', ...headers });
    res.send(JSON.stringify({ status }));
    return status;
}

// The path relative to the resource, without leading slashes or a query string.
function requestPath(path) {
    if (typeof path !== 'string') return '';
    const query = path.indexOf('?');
    return (query === -1 ? path : path.slice(0, query)).replace(/^\/+/, '');
}

// FXServer keeps the case the client sent (Content-Length, X-Rongroi-Upload-Id), so lower-case every
// name once for the handlers. A missing or non-object req.headers reads as an empty set.
function lowerCaseHeaders(headers) {
    const copy = Object.create(null);
    if (headers === null || typeof headers !== 'object') return copy;
    for (const name of Object.keys(headers)) copy[name.toLowerCase()] = headers[name];
    return copy;
}
function createHandler({ store, kit, now, onReport, log = () => {} }) {
    const buffers = new Map(); // `${ticket}:${reportSha}` -> one chunked upload in progress
    const addressWindows = new Map(); // source address -> { end, count } for one window
    const ticketWindows = new Map();  // ticket -> { end, count } for one window
    let refused = 0;                 // refused requests without a known ticket, logged by sweep()
    let lastRefusedAt = null;        // when sweep() last logged the refused counter

    // Count one request in a fixed 60 s window anchored at the first request. Returns the Retry-After
    // value when the limit is exceeded, or null.
    function bump(windows, key, limit) {
        const at = now();
        let window = windows.get(key);
        if (!window || at >= window.end) {
            window = { end: at + RATE_WINDOW_MS, count: 0 };
            windows.set(key, window);
        }
        window.count += 1;
        if (window.count <= limit) return null;
        return String(Math.max(1, Math.ceil((window.end - at) / 1000)));
    }

    // req.address without a trailing :port, so 1.2.3.4:1 and 1.2.3.4:2 share a key. A bracketed IPv6
    // address keeps its brackets; an unbracketed IPv6 value holds several colons and is kept whole.
    function addressKey(req) {
        const address = req.address;
        if (typeof address !== 'string' || address.length === 0) return 'unknown';
        const bracketed = /^(\[[^\]]*\]):\d+$/.exec(address);
        if (bracketed) return bracketed[1];
        const colon = address.indexOf(':');
        if (colon !== -1 && colon === address.lastIndexOf(':')) return address.slice(0, colon);
        return address;
    }

    function limitAddress(req) {
        return bump(addressWindows, addressKey(req), MAX_ADDRESS_REQUESTS);
    }

    function limitTicket(ticket) {
        return bump(ticketWindows, ticket, MAX_SLICES_PER_TICKET);
    }

    function dropEnded(windows) {
        const at = now();
        for (const [key, window] of windows) {
            if (at >= window.end) windows.delete(key);
        }
    }

    function fail(res, status, message, ticket, headers) {
        if (ticket === undefined) refused += 1;
        else log(message, ticket);
        return reply(res, status, headers);
    }

    // A thrown handler still answers: log a fixed string, and the ticket only when it is well formed.
    function internalError(res, ticket) {
        if (typeof ticket === 'string' && TICKET_RE.test(ticket)) log('rongroi http: request failed', ticket);
        else log('rongroi http: request failed');
        try { reply(res, 500); } catch { /* the reply itself may have thrown */ }
    }

    // Forget the reassembly bytes of upload ids that the store dropped or consumed.
    function freeDropped(dropped) {
        if (!Array.isArray(dropped)) return;
        for (const [key, buffer] of buffers) {
            if (dropped.includes(buffer.uploadId)) buffers.delete(key);
        }
    }

    // Drop one chunked upload in the store and forget its reassembly bytes, without deleting a newer
    // buffer that took over the same key.
    function dropBuffer(key, buffer) {
        store.drop(buffer.uploadId);
        if (buffers.get(key) === buffer) buffers.delete(key);
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
        const body = JSON.stringify({ ...found.policy, policy_hash: policyHash(found.policy) });
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.send(body);
    }

    // Shared by a direct POST and the last chunk: verify the whole report and answer it.
    function finish(res, ticket, sha, uploadId, raw) {
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
        if (store.stateOf(ticket) === 'consumed') {
            const consumed = store.consume(ticket, sha);
            if (!consumed.ok) {
                store.drop(uploadId);
                return fail(res, consumed.status, 'rongroi http: report consume refused', ticket);
            }
            return reply(res, 200);
        }
        if (!store.isOpen(uploadId)) {
            const gone = !found || found.state === 'expired';
            return fail(res, gone ? 410 : 422, 'rongroi http: report upload slot gone', ticket);
        }
        const event = { caseId: found.caseId, ticket, reportSha256: sha, receivedAt: now() };
        if (declined) event.declined = true;
        else event.record = record;
        try {
            onReport(event);
        } catch {
            store.drop(uploadId);
            return fail(res, 500, 'rongroi http: onReport failed', ticket);
        }
        const consumed = store.consume(ticket, sha);
        if (!consumed.ok) {
            store.drop(uploadId);
            return fail(res, consumed.status, 'rongroi http: report consume refused', ticket);
        }
        freeDropped(consumed.dropped);
        return reply(res, 200);
    }

    function handleReport(req, res, headers) {
        const ticket = headers['x-rongroi-upload-id'];
        const sha = headers['x-rongroi-report-sha256'];
        if (typeof ticket !== 'string' || !TICKET_RE.test(ticket)
            || typeof sha !== 'string' || !SHA256_RE.test(sha)) {
            return fail(res, 400, 'rongroi http: report headers rejected');
        }
        const claimedLength = headers['content-length'];
        if (claimedLength === undefined) {
            return fail(res, 400, 'rongroi http: report content-length rejected', ticket);
        }
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
            if (begun.status === 404 || begun.status === 410) {
                const retryAfter = limitAddress(req);
                if (retryAfter) {
                    return fail(res, 429, 'rongroi http: report upload refused', ticket, { 'Retry-After': retryAfter });
                }
            }
            if (begun.status === 429) {
                return fail(res, 429, 'rongroi http: report upload refused', ticket, { 'Retry-After': '5' });
            }
            return fail(res, begun.status, 'rongroi http: report upload refused', ticket);
        }
        if (begun.repeat) return reply(res, 200);

        const uploadId = begun.uploadId;
        let settled = false;
        let cancelled = false;
        req.setDataHandler((body) => {
            try {
                if (cancelled) return;
                const raw = Buffer.isBuffer(body) ? body : Buffer.from(typeof body === 'string' ? body : '', 'utf8');
                if (raw.length > MAX_DIRECT_BYTES) {
                    store.drop(uploadId);
                    return fail(res, 413, 'rongroi http: report body too large', ticket);
                }
                return finish(res, ticket, sha, uploadId, raw);
            } catch {
                store.drop(uploadId);
                internalError(res, ticket);
            } finally {
                settled = true;
            }
        });
        if (typeof req.setCancelHandler === 'function') {
            req.setCancelHandler(() => {
                if (settled) return;
                cancelled = true;
                store.drop(uploadId);
            });
        }
    }

    function handleChunk(req, res, headers) {
        const ticket = headers['x-rongroi-upload-id'];
        const reportSha = headers['x-rongroi-report-sha256'];
        const chunkSha = headers['x-rongroi-chunk-sha256'];
        const indexHeader = headers['x-rongroi-chunk-index'];
        const totalHeader = headers['x-rongroi-chunk-total'];
        if (typeof ticket !== 'string' || !TICKET_RE.test(ticket)
            || typeof reportSha !== 'string' || !SHA256_RE.test(reportSha)
            || typeof chunkSha !== 'string' || !SHA256_RE.test(chunkSha)
            || typeof indexHeader !== 'string' || !DECIMAL_RE.test(indexHeader)
            || typeof totalHeader !== 'string' || !DECIMAL_RE.test(totalHeader)) {
            return fail(res, 400, 'rongroi http: chunk headers rejected');
        }
        const index = Number(indexHeader);
        const total = Number(totalHeader);
        if (total === 0 || index >= total) {
            return fail(res, 400, 'rongroi http: chunk range rejected', ticket);
        }
        if (total > MAX_CHUNK_TOTAL) {
            return fail(res, 413, 'rongroi http: chunk total too large', ticket);
        }
        const claimedLength = headers['content-length'];
        if (claimedLength === undefined) {
            return fail(res, 400, 'rongroi http: chunk content-length rejected', ticket);
        }
        if (claimedLength !== undefined) {
            if (typeof claimedLength !== 'string' || !DECIMAL_RE.test(claimedLength)) {
                return fail(res, 400, 'rongroi http: chunk content-length rejected', ticket);
            }
            if (Number(claimedLength) > MAX_SLICE_BYTES) {
                return fail(res, 413, 'rongroi http: chunk content-length too large', ticket);
            }
        }

        const key = `${ticket}:${reportSha}`;
        let retried = false;
        let buffer = buffers.get(key);
        if (!buffer) {
            const begun = store.beginUpload(ticket, reportSha);
            if (!begun.ok) {
                if (begun.status === 404 || begun.status === 410) {
                    const retryAfter = limitAddress(req);
                    if (retryAfter) {
                        return fail(res, 429, 'rongroi http: chunk upload refused', ticket, { 'Retry-After': retryAfter });
                    }
                }
                if (begun.status === 429) {
                    return fail(res, 429, 'rongroi http: chunk upload refused', ticket, { 'Retry-After': '5' });
                }
                return fail(res, begun.status, 'rongroi http: chunk upload refused', ticket);
            }
            if (begun.repeat) return reply(res, 200);
            if (index > 0) {
                store.drop(begun.uploadId);
                return fail(res, 422, 'rongroi http: chunk upload missing', ticket);
            }
            buffer = { uploadId: begun.uploadId, total, next: 0, chunks: [], lastSha: null };
            buffers.set(key, buffer);
        } else {
            if (!store.touch(buffer.uploadId)) {
                if (buffers.get(key) === buffer) buffers.delete(key);
                return fail(res, 422, 'rongroi http: chunk upload gone', ticket);
            }
            if (buffer.total !== total) {
                dropBuffer(key, buffer);
                return fail(res, 422, 'rongroi http: chunk total changed', ticket);
            }
            if (index === buffer.next - 1 && chunkSha === buffer.lastSha) {
                retried = true;
            } else if (index !== buffer.next) {
                dropBuffer(key, buffer);
                return fail(res, 422, 'rongroi http: chunk out of order', ticket);
            }
        }

        const retryAfter = limitTicket(ticket);
        if (retryAfter) {
            return fail(res, 429, 'rongroi http: chunk rate limited', ticket, { 'Retry-After': retryAfter });
        }
        if (retried) return reply(res, 200);

        let settled = false;
        let cancelled = false;
        req.setDataHandler((body) => {
            try {
                if (cancelled) return;
                if (buffers.get(key) !== buffer) {
                    if (buffer.finished && index === buffer.next - 1 && chunkSha === buffer.lastSha) {
                        return reply(res, 200);
                    }
                    return fail(res, 422, 'rongroi http: chunk upload gone', ticket);
                }
                if (index === buffer.next - 1 && chunkSha === buffer.lastSha) return reply(res, 200);
                if (index !== buffer.next) return fail(res, 422, 'rongroi http: chunk out of order', ticket);
                const raw = Buffer.isBuffer(body) ? body : Buffer.from(typeof body === 'string' ? body : '', 'utf8');
                if (raw.length > MAX_SLICE_BYTES) {
                    dropBuffer(key, buffer);
                    return fail(res, 413, 'rongroi http: chunk body too large', ticket);
                }
                if (crypto.createHash('sha256').update(raw).digest('hex') !== chunkSha) {
                    dropBuffer(key, buffer);
                    return fail(res, 422, 'rongroi http: chunk sha mismatch', ticket);
                }
                if (index !== total - 1 && raw.length !== MAX_SLICE_BYTES) {
                    dropBuffer(key, buffer);
                    return fail(res, 422, 'rongroi http: chunk length rejected', ticket);
                }
                buffer.chunks.push(raw);
                buffer.next += 1;
                buffer.lastSha = chunkSha;
                if (index !== total - 1) return reply(res, 200);
                const whole = Buffer.concat(buffer.chunks);
                buffers.delete(key);
                const status = finish(res, ticket, reportSha, buffer.uploadId, whole);
                if (status === 200) buffer.finished = true;
                return status;
            } catch {
                dropBuffer(key, buffer);
                internalError(res, ticket);
            } finally {
                settled = true;
            }
        });
        if (typeof req.setCancelHandler === 'function') {
            req.setCancelHandler(() => {
                if (settled) return;
                cancelled = true;
                if (buffer.next === 0) dropBuffer(key, buffer);
            });
        }
    }

    function route(req, res, state) {
        const path = requestPath(req.path);
        const headers = lowerCaseHeaders(req.headers);
        const policy = /^policy\/([^/]+)$/.exec(path);
        state.ticket = policy ? policy[1] : headers['x-rongroi-upload-id'];
        if (policy) {
            if (req.method !== 'GET') return reply(res, 405);
            const retryAfter = limitAddress(req);
            if (retryAfter) return reply(res, 429, { 'Retry-After': retryAfter });
            return handlePolicy(res, policy[1]);
        }
        if (path === 'report') {
            if (req.method !== 'POST') return reply(res, 405);
            return handleReport(req, res, headers);
        }
        if (path === 'report/chunk') {
            if (req.method !== 'POST') return reply(res, 405);
            return handleChunk(req, res, headers);
        }
        refused += 1;
        return reply(res, 404);
    }
    const handler = (req, res) => {
        const state = {};
        try {
            return route(req, res, state);
        } catch {
            internalError(res, state.ticket);
        }
    };
    handler.sweep = () => {
        store.expireDue();
        freeDropped(store.sweepIdle());
        dropEnded(addressWindows);
        dropEnded(ticketWindows);
        const at = now();
        if (refused > 0 && (lastRefusedAt === null || at - lastRefusedAt >= RATE_WINDOW_MS)) {
            log(`rongroi http: refused ${refused} requests`);
            lastRefusedAt = at;
            refused = 0;
        }
    };
    return handler;
}

// Loaded directly as a server_script FXServer provides no CommonJS `module`; the specs still get the export.
if (typeof module !== 'undefined') {
    module.exports = { createHandler };
}
