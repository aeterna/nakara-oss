// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { sendRequest, MAX_RESPONSE_BYTES } = require('../server/js/relay-http.js');

// A stand-in for https.request: records what it was given and lets the test answer, fail or hang.
function fakeStart(answer) {
    const seen = { options: null, written: null, destroyed: null };
    const start = (options, onResponse) => {
        seen.options = options;
        const req = new EventEmitter();
        req.destroy = (err) => { seen.destroyed = err || true; setImmediate(() => req.emit('error', err || new Error('destroyed'))); };
        req.end = (data) => {
            seen.written = data === undefined ? null : data;
            setImmediate(() => answer({ req, onResponse }));
        };
        return req;
    };
    return { start, seen };
}

function respond(onResponse, status, chunks) {
    const res = new EventEmitter();
    res.statusCode = status;
    res.resume = () => {};
    onResponse(res);
    for (const c of chunks) res.emit('data', Buffer.from(c));
    res.emit('end');
}

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
    const res = await sendRequest(start, { method: 'GET', headers: {} }, 1000);
    assert.equal(res.status, 200);
    assert.equal(await res.text(), '');
    assert.equal(seen.written, null);
    assert.equal(seen.options.headers['Content-Length'], undefined);
});

test('a network error rejects', async () => {
    const { start } = fakeStart(({ req }) => req.emit('error', new Error('ECONNREFUSED')));
    await assert.rejects(sendRequest(start, { method: 'GET', headers: {} }, 1000), /ECONNREFUSED/);
});

test('a request that never answers is destroyed and rejects after the timeout', async () => {
    const { start, seen } = fakeStart(() => {});
    const t0 = Date.now();
    await assert.rejects(sendRequest(start, { method: 'GET', headers: {} }, 50), /timed out/);
    assert.ok(Date.now() - t0 < 1000);
    assert.ok(seen.destroyed);
});

test('a response larger than the cap is destroyed and rejects', async () => {
    const big = 'x'.repeat(1024 * 1024);
    const probe = fakeStart(({ onResponse }) => {
        const res = new EventEmitter();
        res.statusCode = 200;
        onResponse(res);
        for (let sent = 0; sent <= MAX_RESPONSE_BYTES; sent += big.length) res.emit('data', Buffer.from(big));
        res.emit('end');
    });
    const { seen } = probe;
    await assert.rejects(sendRequest(probe.start, { method: 'GET', headers: {} }, 1000), /too large/);
    assert.ok(seen.destroyed, 'the request is destroyed once the cap is passed');
});

test('a response that stalls after its first bytes is destroyed and rejects after the timeout', async () => {
    const { start, seen } = fakeStart(({ onResponse }) => {
        const res = new EventEmitter();
        res.statusCode = 200;
        onResponse(res);
        res.emit('data', Buffer.from('{"envelopes":['));
    });
    await assert.rejects(sendRequest(start, { method: 'GET', headers: {} }, 50), /timed out/);
    assert.ok(seen.destroyed);
});

test('start throwing (bad URL) rejects instead of throwing', async () => {
    const start = () => { throw new TypeError('Invalid URL'); };
    await assert.rejects(sendRequest(start, { method: 'GET', headers: {} }, 1000), /Invalid URL/);
});

test('it settles once: an error after the answer changes nothing', async () => {
    const { start } = fakeStart(({ req, onResponse }) => { respond(onResponse, 200, ['a']); req.emit('error', new Error('late')); });
    const res = await sendRequest(start, { method: 'GET', headers: {} }, 1000);
    assert.equal(await res.text(), 'a');
});
