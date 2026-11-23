// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
'use strict';

// One relay request through Node's https.request instead of fetch(). On FXServer (kit-test, 2026-11-22) every fetch()
// POST with a body logged "Unhandled promise rejection ... Invalid state: Reader released" from Node's web streams,
// even though the request itself succeeded: 6 of 6 POSTs did, GETs did not, and https.request did 0 of 6.
// `start(options, onResponse)` is the caller's https.request bound to the URL, so the destination stays in main.js.
// Resolves { status, text() } like the fetch Response the relay client reads; rejects on a network error, after
// `timeoutMs` for the whole request, or when the answer is larger than MAX_RESPONSE_BYTES.
// Unlike fetch(), https.request does not follow redirects: a 3xx comes back as that status, which the relay client
// treats as a refusal. rongroi_relay_url names the Relay itself, so nothing should redirect.

const MAX_RESPONSE_BYTES = 16 * 1024 * 1024; // three 2 MiB envelopes as base64 fit with room to spare

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
            const err = new Error('relay request timed out');
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
                        const err = new Error('relay answer too large');
                        fail(err);
                        req.destroy(err);
                        return;
                    }
                    chunks.push(chunk);
                });
                res.on('end', () => {
                    const text = Buffer.concat(chunks).toString('utf8');
                    finish(resolve, { status: res.statusCode, text: async () => text });
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
