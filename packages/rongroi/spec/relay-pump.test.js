// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createRelayPump } = require('../server/js/relay-pump.js');

const T = '7a1c9e3f5b2d8a4c6e0f1b3d5a7c9e2f';
const SHA = 'a'.repeat(64);

function fakeStore(initial = 'issued') {
    const t = { state: initial, expiresAt: Date.now() + 300000 };
    return {
        t,
        lookup: (ticket) => (ticket === T ? { state: t.state, expiresAt: t.expiresAt } : null),
        relayTickets: () => (t.state === 'consumed' ? [] : [T]),
    };
}

function fakeRelay(script = {}) {
    const calls = { register: 0, result: [], poll: 0 };
    return {
        calls,
        register: async () => { calls.register += 1; return script.register ? script.register(calls.register) : true; },
        poll: async () => { calls.poll += 1; return script.poll ? script.poll(calls.poll) : { status: 200, envelopes: [] }; },
        result: async (ticket, sha, status) => { calls.result.push(status); return script.result ? script.result(calls.result.length) : true; },
    };
}

test('registration is retried each round until the Relay confirms, then not repeated', async () => {
    const store = fakeStore();
    const relay = fakeRelay({ register: (n) => n >= 3 });
    const pump = createRelayPump({ relay, store, ingest: () => 200, graceMs: 600000 });
    pump.issued({ ticket: T, expiresAt: store.t.expiresAt, policyBody: '{}' });
    await pump.round();
    await pump.round();
    await pump.round();
    await pump.round();
    assert.equal(relay.calls.register, 3);
});

test('a result that does not reach the Relay is posted again next round, even after the ticket is consumed', async () => {
    const store = fakeStore();
    const relay = fakeRelay({
        poll: (n) => (n === 1 ? { status: 200, envelopes: [{ sha256: SHA, raw: Buffer.from('x') }] } : { status: 200, envelopes: [] }),
        result: (n) => n >= 2,
    });
    const pump = createRelayPump({ relay, store, ingest: () => { store.t.state = 'consumed'; return 200; }, graceMs: 600000 });
    await pump.round();
    assert.deepEqual(pump.state().toResult, [`${T}:${SHA}`]);
    await pump.round();
    assert.deepEqual(relay.calls.result, [200, 200]);
    assert.deepEqual(pump.state().toResult, []);
});

test('a Relay that forgot the ticket (404 on poll) gets it registered again while it is still issued', async () => {
    const store = fakeStore();
    const relay = fakeRelay({ poll: (n) => (n === 1 ? { status: 404, envelopes: [] } : { status: 200, envelopes: [] }) });
    const pump = createRelayPump({ relay, store, ingest: () => 200, graceMs: 600000 });
    pump.issued({ ticket: T, expiresAt: store.t.expiresAt, policyBody: '{}' });
    await pump.round(); // register (1), poll -> 404 -> marked again
    await pump.round(); // register (2)
    assert.equal(relay.calls.register, 2);
});

test('statuses map to listed results; 429 is left on the Relay', async () => {
    const statuses = [429, 400, 413, 418, 410];
    let i = 0;
    const store = fakeStore();
    const relay = fakeRelay({ poll: () => ({ status: 200, envelopes: statuses.map((_, k) => ({ sha256: String(k).repeat(64).slice(0, 64), raw: Buffer.alloc(1) })) }) });
    const pump = createRelayPump({ relay, store, ingest: () => statuses[i++], graceMs: 600000 });
    await pump.round();
    assert.deepEqual(relay.calls.result, [422, 422, 500, 410]);
});

test('forget drops pending registrations and results for the ticket', async () => {
    const store = fakeStore();
    const relay = fakeRelay({ register: () => false });
    const pump = createRelayPump({ relay, store, ingest: () => 200, graceMs: 600000 });
    pump.issued({ ticket: T, expiresAt: 1, policyBody: '{}' });
    pump.forget(T);
    assert.deepEqual(pump.state(), { toRegister: [], toResult: [] });
});

test('overlapping rounds never run in parallel', async () => {
    const store = fakeStore();
    let inFlight = 0;
    let maxInFlight = 0;
    const relay = fakeRelay({ poll: async () => { inFlight += 1; maxInFlight = Math.max(maxInFlight, inFlight); await new Promise((r) => setTimeout(r, 5)); inFlight -= 1; return { status: 200, envelopes: [] }; } });
    const pump = createRelayPump({ relay, store, ingest: () => 200, graceMs: 600000 });
    await Promise.all([pump.round(), pump.round(), pump.round()]);
    assert.equal(maxInFlight, 1);
    assert.equal(relay.calls.poll, 2, 'the first round plus one more for the calls that came in during it');
});
