// nakara_tickets — Tickets Server Kit
// SPDX-License-Identifier: MIT
'use strict';

// One bridge request through Node's https.request instead of the global fetch. On FXServer (b177 Enhanced, 2026-11-22)
// every fetch POST with a body from nakara_tickets logged "Unhandled promise rejection ... Invalid state: Reader released"
// even though the request itself succeeded: 26 of 26 POSTs did, GETs 0 of 45, and https.request 0 in the same kind of test.
// `start(options, onResponse)` is the caller's https.request bound to the URL, so the destination stays in api.js.
// Resolves { status, ok, text() } like the fetch Response api.js reads; rejects on a network error, after `timeoutMs`
// for the whole request, or above MAX_RESPONSE_BYTES (bridge answers are small JSON). https.request does not follow
// redirects, unlike fetch: a 3xx comes back as that status, which api.js treats as a refusal.

const MAX_RESPONSE_BYTES = 1024 * 1024;

function sendRequest(start, { method = 'GET', headers = {}, body } = {}, timeoutMs) {
    return new Promise((resolve, reject) => {
        let settled = false;
        let req = null;
        const finish = (fn, value) => {
            if (settled) return;
            settled = true;
            clearTimeout(timer);
            fn(value);
        };
        const fail = (err) => finish(reject, err instanceof Error ? err : new Error(String(err)));
        const timer = setTimeout(() => {
            const err = new Error('bridge request timed out');
            fail(err);
            if (req) req.destroy(err);
        }, timeoutMs);

        const data = body === undefined || body === null ? null : Buffer.from(body, 'utf8');
        const sendHeaders = { ...headers };
        if (data) sendHeaders['Content-Length'] = data.length;

        try {
            req = start({ method, headers: sendHeaders }, (res) => {
                const chunks = [];
                let size = 0;
                res.on('data', (chunk) => {
                    if (settled) return;
                    size += chunk.length;
                    if (size > MAX_RESPONSE_BYTES) {
                        const err = new Error('bridge answer too large');
                        fail(err);
                        req.destroy(err);
                        return;
                    }
                    chunks.push(chunk);
                });
                res.on('end', () => {
                    const text = Buffer.concat(chunks).toString('utf8');
                    finish(resolve, { status: res.statusCode, ok: res.statusCode >= 200 && res.statusCode < 300, text: async () => text });
                });
                res.on('error', fail);
            });
        } catch (err) {
            fail(err);
            return;
        }
        req.on('error', fail);
        if (data) req.end(data);
        else req.end();
    });
}

// Loaded directly as a server_script FXServer provides no CommonJS `module`; the specs still get the export.
if (typeof module !== 'undefined') {
    module.exports = { sendRequest, MAX_RESPONSE_BYTES };
}
