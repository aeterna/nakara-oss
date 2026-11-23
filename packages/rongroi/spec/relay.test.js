// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createRelayClient, parseRelayConfig } = require('../server/js/relay.js');

const KEY = 'k'.repeat(24);
const T = '7a1c9e3f5b2d8a4c6e0f1b3d5a7c9e2f';
const SHA = 'a'.repeat(64);

function fakeFetch(responses) {
    const calls = [];
    const fn = async (url, init) => {
        calls.push({ url, ...init });
        const next = responses.shift() || { status: 200, body: {} };
        if (next.throws) throw new Error('network');
        return { status: next.status, text: async () => (next.body === undefined ? '' : JSON.stringify(next.body)) };
    };
    return { fn, calls };
}

test('config: off when nothing is set; https, id and key are checked', () => {
    assert.deepEqual(parseRelayConfig({}), { ok: false, reason: 'off' });
    assert.equal(parseRelayConfig({ url: 'http://r.example.org', id: 'srv', key: KEY }).ok, false);
    assert.equal(parseRelayConfig({ url: 'https://r.example.org', id: 'v1', key: KEY }).ok, false);
    assert.equal(parseRelayConfig({ url: 'https://r.example.org', id: 'Srv', key: KEY }).ok, false);
    assert.equal(parseRelayConfig({ url: 'https://r.example.org', id: 'srv', key: 'short' }).ok, false);
    assert.equal(parseRelayConfig({ url: 'https://r.example.org/base/', id: 'srv', key: KEY }).ok, false);
    const good = parseRelayConfig({ url: 'https://Relay.Example.org/base', id: 'srv', key: KEY });
    assert.deepEqual(good, { ok: true, config: { base: 'https://Relay.Example.org/base', origin: 'https://relay.example.org', id: 'srv', key: KEY } });
});

test('register posts the ticket and base64 policy bytes with the bearer key', async () => {
    const f = fakeFetch([{ status: 201, body: { ok: true } }]);
    const relay = createRelayClient({ config: parseRelayConfig({ url: 'https://r.example.org', id: 'srv', key: KEY }).config, fetchImpl: f.fn });
    assert.equal(await relay.register({ ticket: T, expiresAt: 5, policyBody: '{"a":1}' }), true);
    assert.equal(f.calls[0].url, '/v1/tickets');
    assert.equal(f.calls[0].method, 'POST');
    assert.equal(f.calls[0].headers.Authorization, `Bearer ${KEY}`);
    assert.deepEqual(JSON.parse(f.calls[0].body), { ticket: T, expires_at: 5, policy: Buffer.from('{"a":1}').toString('base64') });
});

test('pending keeps only well-formed envelopes and labels the address source', async () => {
    const f = fakeFetch([{ status: 200, body: { envelopes: [
        { sha256: SHA, body: Buffer.from('xyz').toString('base64'), received_at: 9, peer_addr: '203.0.113.4', peer_addr_source: 'forwarded' },
        { sha256: 'nothex', body: 'AA==' },
        { sha256: SHA, body: 3 },
    ] } }]);
    const relay = createRelayClient({ config: parseRelayConfig({ url: 'https://r.example.org', id: 'srv', key: KEY }).config, fetchImpl: f.fn });
    const got = await relay.pending(T);
    assert.equal(got.length, 1);
    assert.equal(got[0].raw.toString(), 'xyz');
    assert.equal(got[0].receivedAt, 9);
    assert.equal(got[0].addressSource, 'relay-forwarded');
});

test('result maps 200 to accepted, refuses unknown statuses; network errors and bad bodies never throw', async () => {
    const f = fakeFetch([{ status: 200 }, { throws: true }, { status: 200, body: { envelopes: 'x' } }]);
    const relay = createRelayClient({ config: parseRelayConfig({ url: 'https://r.example.org', id: 'srv', key: KEY }).config, fetchImpl: f.fn });
    assert.equal(await relay.result(T, SHA, 200), true);
    assert.deepEqual(JSON.parse(f.calls[0].body), { result: 'accepted' });
    await assert.rejects(relay.result(T, SHA, 418), TypeError);
    assert.equal(await relay.remove(T), false);
    assert.deepEqual(await relay.pending(T), []);
});

test('the API key never appears in a log line', async () => {
    const lines = [];
    const f = fakeFetch([{ status: 403 }, { status: 500 }]);
    const relay = createRelayClient({ config: parseRelayConfig({ url: 'https://r.example.org', id: 'srv', key: KEY }).config,
        fetchImpl: f.fn, log: (...a) => lines.push(a.join(' ')) });
    await relay.register({ ticket: T, expiresAt: 1, policyBody: '{}' });
    await relay.result(T, SHA, 422);
    assert.equal(lines.length, 2);
    assert.ok(lines.every((l) => !l.includes(KEY)));
});
