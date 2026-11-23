// Rongroi Relay
// SPDX-License-Identifier: MIT
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { createRelay } = require('../relay.js');

const KEY = 'test-key-not-real-0123456789';
const OTHER = 'other-key-not-real-0123456789';
const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');
const T = '7a1c9e3f5b2d8a4c6e0f1b3d5a7c9e2f';

function make(extra = {}) {
    let ms = 1_000_000;
    const relay = createRelay({ servers: [{ id: 'srv1', keySha256: sha(KEY) }, { id: 'srv2', keySha256: sha(OTHER) }],
        trustedProxies: ['10.0.0.2'], now: () => ms, ...extra });
    const call = (method, path, { key, headers = {}, body = '', from = '198.51.100.7' } = {}) => {
        const h = { ...headers };
        if (key) h.authorization = `Bearer ${key}`;
        const out = relay.handle({ method, path, headers: h, body: Buffer.isBuffer(body) ? body : Buffer.from(body), socketAddress: from });
        let parsed = null;
        try { parsed = JSON.parse(out.body.toString()); } catch { parsed = out.body.toString(); }
        return { status: out.status, body: parsed, raw: out.body };
    };
    const register = (ticket = T, expires = ms + 300000, policy = '{"profile":"posture","policy_hash":"0123456789abcdef"}') =>
        call('POST', '/v1/tickets', { key: KEY, body: JSON.stringify({ ticket, expires_at: expires, policy: Buffer.from(policy).toString('base64') }) });
    const upload = (body, ticket = T, extraHeaders = {}, from) => call('POST', '/srv1/report', { from, body, headers: {
        'x-rongroi-upload-id': ticket, 'x-rongroi-report-sha256': sha(Buffer.from(body)), 'x-rongroi-envelope': '2', ...extraHeaders } });
    return { relay, call, register, upload, advance: (d) => { ms += d; }, at: () => ms };
}

test('the server API needs the right key; health names the server the key belongs to', () => {
    const r = make();
    assert.equal(r.call('GET', '/v1/health').status, 401);
    assert.deepEqual(r.call('GET', '/v1/health', { key: KEY }).body, { ok: true, server: 'srv1' });
    assert.equal(r.call('POST', '/v1/tickets', { key: 'wrong', body: '{}' }).status, 401);
});

test('the policy bytes are served unchanged until expiry; unknown tickets are 404', () => {
    const r = make();
    const policy = '{"b":1,"a":"ทดสอบ"}';
    assert.equal(r.register(T, r.at() + 1000, policy).status, 201);
    const got = r.call('GET', `/srv1/policy/${T}`);
    assert.equal(got.status, 200);
    assert.equal(got.raw.toString('utf8'), policy);
    assert.equal(r.call('GET', `/srv1/policy/${'e'.repeat(32)}`).status, 404);
    assert.equal(r.call('GET', `/srv2/policy/${T}`).status, 404, 'tickets are per server');
    r.advance(1000);
    assert.equal(r.call('GET', `/srv1/policy/${T}`).status, 410);
});

test('upload needs a registered ticket, envelope 2 and a matching hash, and is stored as pending', () => {
    const r = make();
    assert.equal(r.upload('env-a').status, 404);
    r.register();
    assert.equal(r.upload('env-a', T, { 'x-rongroi-envelope': '1' }).status, 400);
    assert.equal(r.upload('env-a', T, { 'x-rongroi-report-sha256': 'a'.repeat(64) }).status, 422);
    assert.equal(r.upload('env-a').status, 202);
    assert.equal(r.upload('env-a').status, 202, 'repeat');
    assert.deepEqual(r.call('GET', `/srv1/status/${T}/${sha(Buffer.from('env-a'))}`).body, { result: 'pending' });
    const pending = r.call('GET', `/v1/tickets/${T}/envelopes`, { key: KEY }).body.envelopes;
    assert.equal(pending.length, 1);
    assert.equal(Buffer.from(pending[0].body, 'base64').toString(), 'env-a');
    assert.equal(pending[0].peer_addr, '198.51.100.7');
    assert.equal(pending[0].peer_addr_source, 'socket');
    assert.equal(r.call('GET', `/v1/tickets/${T}/envelopes`, { key: OTHER }).status, 404, 'another server cannot pull it');
});

test('three open slots; a 422 result frees one; accepted closes the ticket and the status says so', () => {
    const r = make();
    r.register();
    for (const b of ['j1', 'j2', 'j3']) assert.equal(r.upload(b).status, 202);
    assert.equal(r.upload('real').status, 409);
    const res = (b, result) => r.call('POST', `/v1/tickets/${T}/envelopes/${sha(Buffer.from(b))}/result`, { key: KEY, body: JSON.stringify({ result }) });
    assert.equal(res('j1', 422).status, 200);
    assert.deepEqual(r.call('GET', `/srv1/status/${T}/${sha(Buffer.from('j1'))}`).body, { result: 422 });
    assert.equal(r.upload('real').status, 202);
    assert.equal(res('real', 'accepted').status, 200);
    assert.deepEqual(r.call('GET', `/srv1/status/${T}/${sha(Buffer.from('real'))}`).body, { result: 'accepted' });
    assert.equal(r.upload('late').status, 409);
    assert.equal(r.upload('real').status, 200, 'repeat of the accepted envelope');
    assert.equal(res('j2', 418).status, 400);
});

test('X-Forwarded-For is believed only from a trusted proxy', () => {
    const r = make();
    r.register();
    r.upload('a', T, { 'x-forwarded-for': '203.0.113.9' }, '198.51.100.7');
    r.upload('b', T, { 'x-forwarded-for': '203.0.113.9, 10.0.0.2' }, '10.0.0.2');
    const env = r.call('GET', `/v1/tickets/${T}/envelopes`, { key: KEY }).body.envelopes;
    const byBody = Object.fromEntries(env.map((e) => [Buffer.from(e.body, 'base64').toString(), e]));
    assert.deepEqual([byBody.a.peer_addr, byBody.a.peer_addr_source], ['198.51.100.7', 'socket']);
    assert.deepEqual([byBody.b.peer_addr, byBody.b.peer_addr_source], ['203.0.113.9', 'forwarded']);
});

test('uploads after expiry are 410; the sweep drops unanswered envelopes an hour later and answered tickets 10 minutes later', () => {
    const r = make();
    r.register(T, r.at() + 1000);
    assert.equal(r.upload('a').status, 202);
    r.advance(1000);
    assert.equal(r.upload('b').status, 410);
    r.advance(60 * 60 * 1000);
    r.relay.sweep();
    assert.equal(r.relay._tickets.size, 0);
    const T2 = 'b'.repeat(32);
    r.register(T2, r.at() + 1000);
    r.upload('c', T2);
    r.call('POST', `/v1/tickets/${T2}/envelopes/${sha(Buffer.from('c'))}/result`, { key: KEY, body: '{"result":"accepted"}' });
    r.advance(1000 + 10 * 60 * 1000);
    r.relay.sweep();
    assert.equal(r.relay._tickets.size, 0);
});

test('registration is checked: ttl at most an hour, no duplicates, delete removes everything', () => {
    const r = make();
    assert.equal(r.register(T, r.at() + 2 * 60 * 60 * 1000).status, 400);
    assert.equal(r.register().status, 201);
    assert.equal(r.register().status, 409);
    r.upload('x');
    assert.equal(r.call('DELETE', `/v1/tickets/${T}`, { key: KEY }).status, 200);
    assert.equal(r.call('GET', `/srv1/policy/${T}`).status, 404);
});

test('public requests are rate limited per address', () => {
    const r = make();
    let last;
    for (let i = 0; i < 121; i += 1) last = r.call('GET', `/srv1/policy/${T}`, { from: '192.0.2.1' });
    assert.equal(last.status, 429);
    assert.equal(r.call('GET', `/srv1/policy/${T}`, { from: '192.0.2.2' }).status, 404);
});

test('servers are validated at start', () => {
    assert.throws(() => createRelay({ servers: [] }), TypeError);
    assert.throws(() => createRelay({ servers: [{ id: 'v1', keySha256: sha(KEY) }] }), TypeError);
    assert.throws(() => createRelay({ servers: [{ id: 'a', keySha256: 'x' }] }), TypeError);
});

test('preflight refuses a report before its body is read: unknown ticket, bad headers, no or large Content-Length', () => {
    const r = make();
    const pre = (headers, path = '/srv1/report') => {
        const out = r.relay.preflight({ method: 'POST', path, headers, socketAddress: '198.51.100.7' });
        return out ? out.status : null;
    };
    const good = { 'x-rongroi-upload-id': T, 'x-rongroi-report-sha256': 'a'.repeat(64), 'x-rongroi-envelope': '2', 'content-length': '10' };
    assert.equal(pre(good), 404, 'ticket not registered');
    r.register();
    assert.equal(pre(good), null, 'a plausible upload goes on to read its body');
    assert.equal(pre({ ...good, 'x-rongroi-envelope': '1' }), 400);
    assert.equal(pre({ ...good, 'content-length': undefined }), 411);
    assert.equal(pre({ ...good, 'content-length': String(2 * 1024 * 1024 + 1) }), 413);
    assert.equal(pre(good, `/srv1/policy/${T}`), null, 'only report uploads are preflighted');
    assert.equal(pre(good, '/nope/report'), null, 'unknown server falls through to the normal 404');
});

test('X-Forwarded-For: only from a trusted proxy, rightmost untrusted IP entry, ::ffff: forms match', () => {
    const r = make();
    r.register();
    const via = (xff, from) => {
        r.upload(`env-${xff}-${from}`, T, xff === undefined ? {} : { 'x-forwarded-for': xff }, from);
        const listed = r.call('GET', `/v1/tickets/${T}/envelopes`, { key: KEY }).body.envelopes;
        const last = listed[listed.length - 1];
        r.call('POST', `/v1/tickets/${T}/envelopes/${last.sha256}/result`, { key: KEY, body: '{"result":409}' });
        return [last.peer_addr, last.peer_addr_source];
    };
    assert.deepEqual(via('203.0.113.9', '198.51.100.7'), ['198.51.100.7', 'socket'], 'untrusted socket: header ignored');
    assert.deepEqual(via('1.1.1.1, 203.0.113.9', '::ffff:10.0.0.2'), ['203.0.113.9', 'forwarded'], 'rightmost wins; mapped proxy address trusted');
    assert.deepEqual(via('not-an-ip', '10.0.0.2'), ['10.0.0.2', 'socket'], 'a non-IP entry is not believed');
});

test('a result is final: a second result for the same envelope is 409', () => {
    const r = make();
    r.register();
    r.upload('env-final');
    const s = sha(Buffer.from('env-final'));
    const post = (result) => r.call('POST', `/v1/tickets/${T}/envelopes/${s}/result`, { key: KEY, body: JSON.stringify({ result }) }).status;
    assert.equal(post('accepted'), 200);
    assert.equal(post(500), 409);
    assert.deepEqual(r.call('GET', `/srv1/status/${T}/${s}`).body, { result: 'accepted' });
});

test('preflight refuses the server API without the key, and a server body over 128 KiB', () => {
    const r = make();
    const pre = (headers) => { const o = r.relay.preflight({ method: 'POST', path: '/v1/tickets', headers, socketAddress: '1.2.3.4' }); return o ? o.status : null; };
    assert.equal(pre({ 'content-length': '10' }), 401);
    assert.equal(pre({ authorization: `Bearer ${KEY}`, 'content-length': String(200 * 1024) }), 413);
    assert.equal(pre({ authorization: `Bearer ${KEY}`, 'content-length': '100' }), null);
});
