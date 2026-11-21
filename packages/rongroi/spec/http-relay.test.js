// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
'use strict';

// Envelopes pulled from a Rongroi Relay (aeterna-rongroi ADR 0097 section 3; Server Kit ADR 0001 section 14).
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { sealEnvelope, sealEnvelopeV2 } = require('../server/js/envelope.js');
const { TicketStore } = require('../server/js/tickets.js');
const { createHandler } = require('../server/js/http.js');
const kit = require('../test-vectors/envelope-v1.json').kit;

const TTL = 300000;
const POLICY = { collectors: ['a'], version: 2 };

function harness() {
    let ms = 1000000;
    let next = 0;
    const store = new TicketStore({ now: () => ms, randomBytes: (n) => Buffer.from(Array.from({ length: n }, () => (next = (next + 1) & 0xff))) });
    const reports = [];
    const handler = createHandler({ store, kit, now: () => ms, onReport: (e) => reports.push(e), log: () => {} });
    return { store, handler, reports, at: () => ms, advance: (d) => { ms += d; } };
}

function relayTicket(h) {
    const issued = h.store.issue({ caseId: 'case-r', policy: POLICY });
    const binding = { base_path: 'srv1', policy_hash: '0123456789abcdef', server_origin: 'https://relay.example.org', ticket: issued.ticket, transport: 'relay' };
    h.store.setBinding(issued.ticket, binding);
    return { ...issued, binding };
}

function sealed(issued, binding, extra = {}) {
    const record = { schema: 2, binding: { ticket: issued.ticket, nonce: issued.nonce }, note: 'relay', ...extra };
    const raw = Buffer.from(sealEnvelopeV2(JSON.stringify(record), kit.publicKey, binding), 'utf8');
    return { raw, sha: crypto.createHash('sha256').update(raw).digest('hex') };
}

test('a v2 envelope with the issued binding is accepted, stored with the relay address and consumes the ticket', () => {
    const h = harness();
    const t = relayTicket(h);
    const e = sealed(t, t.binding);
    assert.equal(h.handler.ingestRelay({ ticket: t.ticket, sha: e.sha, raw: e.raw, receivedAt: h.at(), address: '203.0.113.4', addressSource: 'relay-socket' }), 200);
    assert.equal(h.store.stateOf(t.ticket), 'consumed');
    assert.equal(h.reports[0].address, '203.0.113.4');
    assert.equal(h.reports[0].addressSource, 'relay-socket');
    assert.equal(h.handler.ingestRelay({ ticket: t.ticket, sha: e.sha, raw: e.raw }), 200, 'repeat of the accepted envelope');
});

test('an envelope bound to another origin, or a v1 envelope, is refused and leaves the ticket usable', () => {
    const h = harness();
    const t = relayTicket(h);
    const wrong = sealed(t, { ...t.binding, server_origin: 'https://evil.example.net' });
    assert.equal(h.handler.ingestRelay({ ticket: t.ticket, sha: wrong.sha, raw: wrong.raw }), 422);
    const v1raw = Buffer.from(sealEnvelope(JSON.stringify({ schema: 2, binding: { ticket: t.ticket, nonce: t.nonce } }), kit.publicKey, t.ticket));
    assert.equal(h.handler.ingestRelay({ ticket: t.ticket, sha: crypto.createHash('sha256').update(v1raw).digest('hex'), raw: v1raw }), 400);
    assert.notEqual(h.store.stateOf(t.ticket), 'consumed');
    const good = sealed(t, t.binding);
    assert.equal(h.handler.ingestRelay({ ticket: t.ticket, sha: good.sha, raw: good.raw }), 200);
});

test('received before expires_at but pulled after it is accepted; received after it is 410', () => {
    const h = harness();
    const t = relayTicket(h);
    const e = sealed(t, t.binding);
    h.advance(TTL + 60000);
    assert.equal(h.handler.ingestRelay({ ticket: t.ticket, sha: e.sha, raw: e.raw, receivedAt: t.expiresAt + 1 }), 410);
    const t2 = relayTicket(h);
    const e2 = sealed(t2, t2.binding);
    h.advance(TTL + 60000);
    assert.equal(h.handler.ingestRelay({ ticket: t2.ticket, sha: e2.sha, raw: e2.raw, receivedAt: t2.expiresAt - 5 }), 200);
});

test('malformed input never throws: bad sha, unknown ticket, sha mismatch', () => {
    const h = harness();
    const t = relayTicket(h);
    const e = sealed(t, t.binding);
    assert.equal(h.handler.ingestRelay({ ticket: t.ticket, sha: 'x', raw: e.raw }), 400);
    assert.equal(h.handler.ingestRelay({ ticket: 'e'.repeat(32), sha: e.sha, raw: e.raw }), 404);
    assert.equal(h.handler.ingestRelay({ ticket: t.ticket, sha: 'b'.repeat(64), raw: e.raw }), 422);
    assert.equal(h.handler.ingestRelay({}), 400);
});
