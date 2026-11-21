// Rongroi Relay
// SPDX-License-Identifier: MIT
'use strict';

// Rongroi Relay (aeterna-rongroi ADR 0097 section 3). A server owner runs it so Rongroi Connect can deliver reports
// over HTTPS without reaching the game server. It stores ciphertext only: the server that holds the private key pulls
// each envelope, checks it and posts a result. Nothing here can tell what a report says, and nothing here says
// whether a PC passed anything. State is in memory: a restart forgets pending tickets (Connect then sees 404).

const crypto = require('node:crypto');

const TICKET_RE = /^[0-9a-f]{32}$/;
const SHA256_RE = /^[0-9a-f]{64}$/;
const ID_RE = /^[a-z0-9_-]{1,64}$/;
const RESULTS = ['accepted', 404, 409, 410, 422, 500];
const MAX_ENVELOPE_BYTES = 2 * 1024 * 1024;
const MAX_POLICY_BYTES = 64 * 1024;
const MAX_SLOTS = 3;               // pending or accepted envelopes per ticket
const RESULT_KEEP_MS = 10 * 60 * 1000; // result word kept past expires_at for Connect's status poll
const UNANSWERED_KEEP_MS = 60 * 60 * 1000; // envelopes without a result are dropped this long past expires_at
const MAX_TICKET_TTL_MS = 60 * 60 * 1000;
const RATE_WINDOW_MS = 60000;
const RATE_LIMIT = 120;            // public requests per address per window

function sha256Hex(buf) {
    return crypto.createHash('sha256').update(buf).digest('hex');
}

function timingSafeEqualHex(a, b) {
    if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
    return crypto.timingSafeEqual(Buffer.from(a, 'hex'), Buffer.from(b, 'hex'));
}

// servers: [{ id, keySha256 }] — the relay stores only each key's SHA-256. trustedProxies: socket addresses whose
// X-Forwarded-For is believed.
function createRelay({ servers, trustedProxies = [], now = Date.now, log = () => {} }) {
    if (!Array.isArray(servers) || servers.length === 0) throw new TypeError('relay needs at least one server');
    const byId = new Map();
    for (const s of servers) {
        if (!s || !ID_RE.test(s.id) || s.id === 'v1' || !SHA256_RE.test(s.keySha256)) {
            throw new TypeError('each server needs an id ([a-z0-9_-], not v1) and a keySha256');
        }
        if (byId.has(s.id)) throw new TypeError(`duplicate server id ${s.id}`);
        byId.set(s.id, s);
    }
    const trusted = new Set(trustedProxies);
    const tickets = new Map(); // `${id}:${ticket}` -> { expiresAt, policy: Buffer, envelopes: Map(sha -> env) }
    const windows = new Map();

    function serverForKey(header) {
        const m = /^Bearer (.+)$/.exec(typeof header === 'string' ? header : '');
        if (!m) return null;
        const digest = sha256Hex(Buffer.from(m[1], 'utf8'));
        for (const s of byId.values()) if (timingSafeEqualHex(digest, s.keySha256)) return s.id;
        return null;
    }

    function peer(socketAddress, forwardedFor) {
        if (trusted.has(socketAddress) && typeof forwardedFor === 'string' && forwardedFor.length > 0) {
            const first = forwardedFor.split(',')[0].trim();
            if (first) return { address: first, source: 'forwarded' };
        }
        return { address: socketAddress || '', source: 'socket' };
    }

    function limited(address) {
        const at = now();
        let w = windows.get(address);
        if (!w || at >= w.end) {
            w = { end: at + RATE_WINDOW_MS, count: 0 };
            windows.set(address, w);
        }
        w.count += 1;
        return w.count > RATE_LIMIT;
    }

    function sweep() {
        const at = now();
        for (const [key, t] of tickets) {
            for (const [sha, e] of t.envelopes) {
                if (e.result === null && at >= t.expiresAt + UNANSWERED_KEEP_MS) t.envelopes.delete(sha);
            }
            const answered = [...t.envelopes.values()].every((e) => e.result !== null);
            if (answered && at >= t.expiresAt + RESULT_KEEP_MS) tickets.delete(key);
            else if (at >= t.expiresAt + UNANSWERED_KEEP_MS) tickets.delete(key);
        }
        for (const [a, w] of windows) if (at >= w.end) windows.delete(a);
    }

    const json = (status, body) => ({ status, headers: { 'Content-Type': 'application/json' }, body: Buffer.from(JSON.stringify(body)) });

    // One request: { method, path, headers (lower-case names), body: Buffer, socketAddress }. Returns { status, headers, body }.
    function handle(req) {
        const path = (req.path || '').split('?')[0];
        const h = req.headers || {};
        const parts = path.split('/').filter(Boolean);

        // Server-facing API, authenticated per server.
        if (parts[0] === 'v1') {
            if (parts[1] === 'health' && req.method === 'GET') {
                const id = serverForKey(h.authorization);
                return id ? json(200, { ok: true, server: id }) : json(401, { status: 401 });
            }
            const id = serverForKey(h.authorization);
            if (!id) return json(401, { status: 401 });
            if (parts[1] !== 'tickets') return json(404, { status: 404 });
            if (parts.length === 2 && req.method === 'POST') return register(id, req.body);
            const ticket = parts[2];
            if (!TICKET_RE.test(ticket || '')) return json(400, { status: 400 });
            const t = tickets.get(`${id}:${ticket}`);
            if (parts.length === 3 && req.method === 'DELETE') {
                tickets.delete(`${id}:${ticket}`);
                return json(200, { ok: true });
            }
            if (!t) return json(404, { status: 404 });
            if (parts.length === 4 && parts[3] === 'envelopes' && req.method === 'GET') {
                const envelopes = [];
                for (const [sha, e] of t.envelopes) {
                    if (e.result !== null) continue;
                    envelopes.push({ sha256: sha, body: e.body.toString('base64'), received_at: e.receivedAt,
                        peer_addr: e.peer.address, peer_addr_source: e.peer.source });
                }
                return json(200, { envelopes });
            }
            if (parts.length === 6 && parts[3] === 'envelopes' && parts[5] === 'result' && req.method === 'POST') {
                const e = t.envelopes.get(parts[4]);
                if (!e) return json(404, { status: 404 });
                let result;
                try { result = JSON.parse(req.body.toString('utf8')).result; } catch { result = undefined; }
                if (!RESULTS.includes(result)) return json(400, { status: 400 });
                if (result === 422) {
                    t.envelopes.delete(parts[4]); // frees the slot: junk cannot lock the player out
                    t.lastRejected = { sha: parts[4], result };
                } else {
                    e.result = result;
                    if (result === 'accepted') {
                        e.body = Buffer.alloc(0); // the server stored the record; keep only the result word
                        t.accepted = parts[4];
                    }
                }
                return json(200, { ok: true });
            }
            return json(404, { status: 404 });
        }

        // Connect-facing API: /<server id>/policy|report|status/...
        const id = parts[0];
        if (!byId.has(id || '')) return json(404, { status: 404 });
        const who = peer(req.socketAddress, h['x-forwarded-for']);
        if (limited(who.address)) return { ...json(429, { status: 429 }), headers: { 'Content-Type': 'application/json', 'Retry-After': '30' } };
        if (parts[1] === 'policy' && parts.length === 3 && req.method === 'GET') {
            const t = TICKET_RE.test(parts[2]) ? tickets.get(`${id}:${parts[2]}`) : null;
            if (!t) return json(404, { status: 404 });
            if (now() >= t.expiresAt) return json(410, { status: 410 });
            return { status: 200, headers: { 'Content-Type': 'application/json' }, body: t.policy };
        }
        if (parts[1] === 'report' && parts.length === 2 && req.method === 'POST') return upload(id, h, req.body, who);
        if (parts[1] === 'status' && parts.length === 4 && req.method === 'GET') {
            const t = TICKET_RE.test(parts[2]) ? tickets.get(`${id}:${parts[2]}`) : null;
            if (!t || !SHA256_RE.test(parts[3])) return json(404, { status: 404 });
            const e = t.envelopes.get(parts[3]);
            if (e) return json(200, { result: e.result === null ? 'pending' : e.result });
            if (t.lastRejected && t.lastRejected.sha === parts[3]) return json(200, { result: t.lastRejected.result });
            return json(404, { status: 404 });
        }
        return json(404, { status: 404 });
    }

    function register(id, body) {
        let input;
        try { input = JSON.parse(body.toString('utf8')); } catch { return json(400, { status: 400 }); }
        if (!input || !TICKET_RE.test(input.ticket) || !Number.isSafeInteger(input.expires_at) || typeof input.policy !== 'string') {
            return json(400, { status: 400 });
        }
        const at = now();
        if (input.expires_at <= at || input.expires_at > at + MAX_TICKET_TTL_MS) return json(400, { status: 400 });
        const policy = Buffer.from(input.policy, 'base64');
        if (policy.length === 0 || policy.length > MAX_POLICY_BYTES) return json(413, { status: 413 });
        const key = `${id}:${input.ticket}`;
        if (tickets.has(key)) return json(409, { status: 409 });
        tickets.set(key, { expiresAt: input.expires_at, policy, envelopes: new Map(), accepted: null, lastRejected: null });
        return json(201, { ok: true });
    }

    function upload(id, h, body, who) {
        const ticket = h['x-rongroi-upload-id'];
        const sha = h['x-rongroi-report-sha256'];
        if (!TICKET_RE.test(ticket || '') || !SHA256_RE.test(sha || '')) return json(400, { status: 400 });
        if (h['x-rongroi-envelope'] !== '2') return json(400, { status: 400 });
        if (body.length > MAX_ENVELOPE_BYTES) return json(413, { status: 413 });
        if (sha256Hex(body) !== sha) return json(422, { status: 422 });
        const t = tickets.get(`${id}:${ticket}`);
        if (!t) return json(404, { status: 404 });
        const existing = t.envelopes.get(sha);
        if (existing) {
            if (existing.result === 'accepted') return json(200, { status: 200 });
            return json(202, { status: 202 });
        }
        if (t.accepted) return json(409, { status: 409 });
        const at = now();
        if (at >= t.expiresAt) return json(410, { status: 410 });
        const open = [...t.envelopes.values()].filter((e) => e.result === null || e.result === 'accepted').length;
        if (open >= MAX_SLOTS) return json(409, { status: 409 });
        t.envelopes.set(sha, { body, receivedAt: at, peer: who, result: null });
        log(`stored ${id} ${ticket}`);
        return json(202, { status: 202 });
    }

    return { handle, sweep, _tickets: tickets };
}

module.exports = { createRelay, MAX_ENVELOPE_BYTES };
