// nakara_tickets — Tickets Server Kit
// SPDX-License-Identifier: MIT
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { sendRequest, MAX_RESPONSE_BYTES } = require('../server/js/http-request.js');

// A stand-in for https.request: records the options and body, and lets the test answer, fail or hang.
function fakeStart(answer) {
    const seen = { options: null, written: null, destroyed: null };
    const start = (options, onResponse) => {
        seen.options = options;
        const req = new EventEmitter();
        req.destroy = (err) => { seen.destroyed = err || true; setImmediate(() => req.emit('error', err || new Error('destroyed'))); };
        req.end = (data) => { seen.written = data ?? null; setImmediate(() => answer({ req, onResponse })); };
        return req;
    };
    return { start, seen };
}

function respond(onResponse, status, chunks) {
    const res = new EventEmitter();
    res.statusCode = status;
    onResponse(res);
    for (const c of chunks) res.emit('data', Buffer.from(c));
    res.emit('end');
}

const GET = { method: 'GET', headers: {} };
test('POST sends the body with its length and resolves status and text', async () => {
    const { start, seen } = fakeStart(({ onResponse }) => respond(onResponse, 201, ['{"ok":', 'true}']));
    const res = await sendRequest(start, { method: 'POST', headers: { A: 'b' }, body: '{"x":1}' }, 1000);
    assert.equal(res.status, 201);
    assert.equal(await res.text(), '{"ok":true}');
    assert.equal(seen.options.method, 'POST');
    assert.equal(seen.options.headers.A, 'b');
    assert.equal(seen.options.headers['Content-Length'], 7);
    assert.equal(seen.written.toString('utf8'), '{"x":1}');
});
test('GET sends no body and no Content-Length', async () => {
    const { start, seen } = fakeStart(({ onResponse }) => respond(onResponse, 200, []));
    const res = await sendRequest(start, GET, 1000);
    assert.equal(res.status, 200);
    assert.equal(await res.text(), '');
    assert.equal(seen.written, null);
    assert.equal(seen.options.headers['Content-Length'], undefined);
});
test('ok is true for 2xx and false otherwise', async () => {
    for (const [status, expected] of [[200, true], [299, true], [300, false], [404, false]]) {
        const { start } = fakeStart(({ onResponse }) => respond(onResponse, status, []));
        const res = await sendRequest(start, GET, 1000);
        assert.equal(res.ok, expected, `status ${status}`);
    }
});
test('Content-Length counts UTF-8 bytes, not characters', async () => {
    const { start, seen } = fakeStart(({ onResponse }) => respond(onResponse, 200, []));
    await sendRequest(start, { method: 'POST', headers: {}, body: 'ä' }, 1000);
    assert.equal(seen.options.headers['Content-Length'], 2);
    assert.equal(seen.written.length, 2);
});
test('a network error rejects', async () => {
    const { start } = fakeStart(({ req }) => req.emit('error', new Error('ECONNREFUSED')));
    await assert.rejects(sendRequest(start, GET, 1000), /ECONNREFUSED/);
});
test('a request that never answers is destroyed and rejects after the timeout', async () => {
    const { start, seen } = fakeStart(() => {});
    const t0 = Date.now();
    await assert.rejects(sendRequest(start, GET, 50), /timed out/);
    assert.ok(Date.now() - t0 < 1000);
    assert.ok(seen.destroyed);
});
test('a response larger than the cap is destroyed and rejects', async () => {
    const big = 'x'.repeat(1024 * 1024);
    const { start, seen } = fakeStart(({ onResponse }) => {
        const res = new EventEmitter();
        res.statusCode = 200;
        onResponse(res);
        for (let sent = 0; sent <= MAX_RESPONSE_BYTES; sent += big.length) res.emit('data', Buffer.from(big));
        res.emit('end');
    });
    await assert.rejects(sendRequest(start, GET, 1000), /too large/);
    assert.ok(seen.destroyed, 'the request is destroyed once the cap is passed');
});
test('a response that stalls after its first bytes is destroyed and rejects after the timeout', async () => {
    const { start, seen } = fakeStart(({ onResponse }) => {
        const res = new EventEmitter();
        res.statusCode = 200;
        onResponse(res);
        res.emit('data', Buffer.from('{"action":'));
    });
    await assert.rejects(sendRequest(start, GET, 50), /timed out/);
    assert.ok(seen.destroyed);
});
test('start throwing (bad URL) rejects instead of throwing', async () => {
    const start = () => { throw new TypeError('Invalid URL'); };
    await assert.rejects(sendRequest(start, GET, 1000), /Invalid URL/);
});
test('it settles once: an error after the answer changes nothing', async () => {
    const { start } = fakeStart(({ req, onResponse }) => { respond(onResponse, 200, ['a']); req.emit('error', new Error('late')); });
    const res = await sendRequest(start, GET, 1000);
    assert.equal(await res.text(), 'a');
});
