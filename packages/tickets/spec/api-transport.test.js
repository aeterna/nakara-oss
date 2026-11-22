const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const https = require('https');
const http = require('http');
const BASE = 'https://tickets.example.com';
const SECRET = 'dGVzdC1zZWNyZXQtMzItYnl0ZXMtc3RyaW5nLWJhc2U2NA';
const PAIR = { serverName: 'Srv', edition: 'gta5', resourceVersion: '0.1.0' };
const saved = { https: https.request, http: http.request, fetch: globalThis.fetch, GetConvar: globalThis.GetConvar };
let fetchCalls = [];

// Replaces request() on lib (https or http): records each call and answers 200 JSON chosen by route.
function stubRequest(lib) {
  const calls = [];
  lib.request = (url, options, onResponse) => {
    const call = { url, method: options.method, headers: options.headers, body: null };
    calls.push(call);
    const req = new EventEmitter();
    req.end = (data) => {
      call.body = data === undefined ? null : data.toString('utf8');
      const reply = url.endsWith('/pair') ? { serverId: 'srv-1', secret: 'sec-1', guildName: 'Guild' }
        : url.includes('?wait=') ? { action: null } : { ok: true };
      setImmediate(() => {
        const res = new EventEmitter();
        res.statusCode = 200;
        onResponse(res);
        res.emit('data', Buffer.from(JSON.stringify(reply)));
        res.emit('end');
      });
    };
    return req;
  };
  return calls;
}
// api.js reads nakara_tickets_api once at load, so each case loads it fresh with its own base.
function loadApi(base) {
  Object.defineProperty(globalThis, 'GetConvar', { value: (name, def) => (name === 'nakara_tickets_api' ? base : def), configurable: true, writable: true });
  delete require.cache[require.resolve('../server/js/api.js')];
  return require('../server/js/api.js');
}
// One recorded call: URL, method, exact body, and Content-Length (absent when there is no body).
function assertSent(call, url, method, body) {
  assert.deepEqual([call.url, call.method, call.body, call.headers['Content-Length']], [url, method, body, body === null ? undefined : Buffer.byteLength(body)]);
}

describe('api.js transport: bridge calls use https.request / http.request, never fetch', () => {
  beforeEach(() => {
    fetchCalls = [];
    globalThis.fetch = async (url) => { fetchCalls.push(String(url)); throw new Error('fetch must not be called'); };
  });
  afterEach(() => {
    https.request = saved.https;
    http.request = saved.http;
    globalThis.fetch = saved.fetch;
    if (saved.GetConvar === undefined) delete globalThis.GetConvar;
    else globalThis.GetConvar = saved.GetConvar;
    delete require.cache[require.resolve('../server/js/api.js')];
  });

  it('https base: pair, heartbeat, action result and actions poll go through https.request with the full URL', async () => {
    const api = loadApi(BASE);
    const calls = stubRequest(https);
    const pair = await api.pair('ABCD234567', PAIR);
    const hb = await api.sendHeartbeat('srv-1', SECRET, { players: [], executedIds: ['act-0'] });
    const result = await api.postActionResult('srv-1', SECRET, 'act-1', { ok: true, code: 'done' });
    const poll = await api.getActions('srv-1', SECRET, 25);

    assert.equal(fetchCalls.length, 0, 'fetch must not be called');
    assert.equal(calls.length, 4);
    const [p, h, r, g] = calls;
    assertSent(p, BASE + '/bridge/v1/pair', 'POST', JSON.stringify({ code: 'ABCD234567', serverName: 'Srv', edition: 'gta5', resourceVersion: '0.1.0', protocol: 1 }));
    assertSent(h, BASE + '/bridge/v1/heartbeat', 'POST', JSON.stringify({ players: [], executedIds: ['act-0'] }));
    assertSent(r, BASE + '/bridge/v1/actions/act-1/result', 'POST', JSON.stringify({ ok: true, code: 'done' }));
    assertSent(g, BASE + '/bridge/v1/actions?wait=25', 'GET', null);
    assert.equal(h.headers['X-Tickets-Server'], 'srv-1');
    assert.deepEqual(pair, { ok: true, data: { serverId: 'srv-1', secret: 'sec-1', guildName: 'Guild' } });
    assert.deepEqual(hb, { ok: true, data: { ok: true } });
    assert.deepEqual(result, { ok: true, data: { ok: true } });
    assert.deepEqual(poll, { ok: true, action: null });
  });

  it('http base: pair goes through http.request and https.request is not used', async () => {
    const api = loadApi('http://tickets-app-1:8080');
    const httpCalls = stubRequest(http);
    const httpsCalls = stubRequest(https);
    const pair = await api.pair('ABCD234567', PAIR);
    assert.equal(fetchCalls.length, 0, 'fetch must not be called');
    assert.equal(httpCalls.length, 1);
    assert.equal(httpCalls[0].url, 'http://tickets-app-1:8080/bridge/v1/pair');
    assert.equal(httpsCalls.length, 0, 'https.request must not be used for an http base');
    assert.equal(pair.ok, true);
  });
});
