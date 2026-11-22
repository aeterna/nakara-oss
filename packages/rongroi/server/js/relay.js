'use strict';

// Rongroi Relay client (aeterna-rongroi ADR 0097 section 3; Server Kit ADR 0001 section 14). The Kit registers each
// relay ticket with its policy bytes, pulls the envelopes Connect stored there, verifies them itself and posts a
// result per envelope. The Relay never sees a private key. Every call authenticates with the server's API key, which
// is never logged.

const BASE_PATH_RE = /^[a-z0-9_-]{1,64}$/;
const TICKET_RE = /^[0-9a-f]{32}$/;
const SHA256_RE = /^[0-9a-f]{64}$/;
const RESULTS = ['accepted', 404, 409, 410, 422, 500];

// Check the four convar values. Returns { ok: true, config } or { ok: false, reason } with a fixed reason string.
function parseRelayConfig({ url, id, key } = {}) {
    const any = [url, id, key].some((v) => typeof v === 'string' && v.length > 0);
    if (!any) return { ok: false, reason: 'off' };
    let parsed;
    try {
        parsed = new URL(url);
    } catch {
        return { ok: false, reason: 'rongroi_relay_url is not a URL' };
    }
    if (parsed.protocol !== 'https:') return { ok: false, reason: 'rongroi_relay_url must be https' };
    if (parsed.username || parsed.password || parsed.search || parsed.hash) {
        return { ok: false, reason: 'rongroi_relay_url must have no user, query or fragment' };
    }
    if (url.endsWith('/')) return { ok: false, reason: 'rongroi_relay_url must not end with /' };
    if (typeof id !== 'string' || !BASE_PATH_RE.test(id) || id === 'v1') {
        return { ok: false, reason: 'rongroi_relay_id must match [a-z0-9_-]{1,64} and not be v1' };
    }
    if (typeof key !== 'string' || key.length < 16) return { ok: false, reason: 'rongroi_relay_key must be set (16+ characters)' };
    return { ok: true, config: { base: url, origin: parsed.origin, id, key } };
}

// `fetchImpl(path, init)` sends to rongroi_relay_url + path (main.js: https.request through relay-http.js) and resolves
// { status, text() }. main.js builds the URL from the convar itself, so the
// only destination is the one the owner set (fivem-devkit safety folds a convar URL built that way).
function createRelayClient({ config, fetchImpl, log = () => {} }) {
    if (!config || typeof fetchImpl !== 'function') throw new TypeError('relay client needs a config and fetch');
    const headers = { Authorization: `Bearer ${config.key}`, 'Content-Type': 'application/json' };

    let down = false; // the last request did not reach the Relay at all (network error or timeout)

    async function call(method, path, body) {
        let res;
        down = false;
        try {
            res = await fetchImpl(path, {
                method,
                headers,
                body: body === undefined ? undefined : JSON.stringify(body),
            });
        } catch {
            down = true;
            return { ok: false, status: 0, body: null };
        }
        let parsed = null;
        try {
            const text = await res.text();
            parsed = text ? JSON.parse(text) : null;
        } catch {
            parsed = null;
        }
        return { ok: res.status >= 200 && res.status < 300, status: res.status, body: parsed };
    }

    async function register({ ticket, expiresAt, policyBody }) {
        if (!TICKET_RE.test(ticket) || typeof policyBody !== 'string') throw new TypeError('register needs a ticket and policy bytes');
        const r = await call('POST', '/v1/tickets', {
            ticket,
            expires_at: expiresAt,
            policy: Buffer.from(policyBody, 'utf8').toString('base64'),
        });
        // 409: the Relay already has it (an earlier answer was lost), which is what we wanted.
        const ok = r.ok || r.status === 409;
        if (!ok) log(`rongroi relay: register refused (${r.status})`, ticket);
        return ok;
    }

    // Pending envelopes for one ticket: { status, envelopes: [{ sha256, raw: Buffer, receivedAt, address, addressSource }] }.
    // status 404 means the Relay no longer knows the ticket (it restarted), so the Kit registers it again.
    async function poll(ticket) {
        const r = await call('GET', `/v1/tickets/${ticket}/envelopes`);
        if (!r.ok || !r.body || !Array.isArray(r.body.envelopes)) return { status: r.status, envelopes: [] };
        const out = [];
        for (const e of r.body.envelopes) {
            if (!e || typeof e.sha256 !== 'string' || !SHA256_RE.test(e.sha256) || typeof e.body !== 'string') continue;
            out.push({
                sha256: e.sha256,
                raw: Buffer.from(e.body, 'base64'),
                receivedAt: Number.isFinite(e.received_at) ? e.received_at : undefined,
                address: typeof e.peer_addr === 'string' ? e.peer_addr : undefined,
                addressSource: e.peer_addr_source === 'socket' || e.peer_addr_source === 'forwarded'
                    ? `relay-${e.peer_addr_source}` : undefined,
            });
        }
        return { status: r.status, envelopes: out };
    }

    async function pending(ticket) {
        return (await poll(ticket)).envelopes;
    }

    async function result(ticket, sha256, status) {
        const value = status === 200 ? 'accepted' : status;
        if (!RESULTS.includes(value)) throw new TypeError('result must be accepted or a listed status');
        const r = await call('POST', `/v1/tickets/${ticket}/envelopes/${sha256}/result`, { result: value });
        // Settled: stored now (2xx), already stored by a post whose answer was lost (409), or the envelope is gone
        // (404: freed after a 422, swept, or the Relay restarted). Anything else is posted again next round.
        const settled = r.ok || r.status === 409 || r.status === 404;
        if (!settled) log(`rongroi relay: result not stored (${r.status})`, ticket);
        return settled;
    }

    async function remove(ticket) {
        const r = await call('DELETE', `/v1/tickets/${ticket}`);
        return r.ok || r.status === 404;
    }

    async function health() {
        const r = await call('GET', '/v1/health');
        return { ok: r.ok, status: r.status, server: r.body && typeof r.body.server === 'string' ? r.body.server : null };
    }

    return { register, poll, pending, result, remove, health, unreachable: () => down, origin: config.origin, id: config.id };
}

// Loaded directly as a server_script FXServer provides no CommonJS `module`; the specs still get the export.
if (typeof module !== 'undefined') {
    module.exports = { createRelayClient, parseRelayConfig };
}
