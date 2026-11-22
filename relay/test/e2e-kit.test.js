// Rongroi Relay
// SPDX-License-Identifier: MIT
'use strict';

// Contract test: the real Server Kit modules (ticket store, rr2 code, HTTP verify, relay client) against the real
// Relay, with a sender that seals like Connect (SDK). Proves ADR 0097 section 3 end to end in one process.
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { createRelay } = require('../relay.js');
const kitDir = '../../packages/rongroi/server/js/';
const { TicketStore } = require(`${kitDir}tickets.js`);
const { createHandler } = require(`${kitDir}http.js`);
const { pairingCodeV2, policyHash } = require(`${kitDir}pairing.js`);
const { createRelayClient, parseRelayConfig } = require(`${kitDir}relay.js`);
const sdk = require('../../sdk/rongroi-envelope/index.js');

const KEY = 'e2e-key-not-real-0123456789abc';
const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');

test('a report travels Connect → Relay → Kit and only the Kit decides it was accepted', async () => {
    let ms = 2_000_000;
    let n = 0;
    const relayServer = createRelay({ servers: [{ id: 'srv1', keySha256: sha(KEY) }], now: () => ms });
    // The Kit's fetch reaches the Relay in-process: rongroi_relay_url + path.
    const fetchImpl = async (path, init) => {
        const out = relayServer.handle({ method: init.method, path, headers: { authorization: init.headers.Authorization },
            body: Buffer.from(init.body || ''), socketAddress: '10.0.0.5' });
        return { status: out.status, text: async () => out.body.toString('utf8') };
    };
    const config = parseRelayConfig({ url: 'https://relay.example.org', id: 'srv1', key: KEY }).config;
    const relay = createRelayClient({ config, fetchImpl });
    const kitKeys = sdk.generateKeyPair();
    const store = new TicketStore({ now: () => ms, randomBytes: (k) => Buffer.from(Array.from({ length: k }, () => (n = (n + 7) & 0xff))) });
    const reports = [];
    const handler = createHandler({ store, kit: kitKeys, now: () => ms, onReport: (e) => reports.push(e) });

    // Kit: open a case, bind an rr2 code to the Relay, register the policy bytes.
    const policy = { profile: 'posture', required_collectors: [], require_elevation: false, server_name: 'e2e' };
    const issued = store.issue({ caseId: 'case-e2e', policy });
    const hash = policyHash(policy);
    const { code, binding } = pairingCodeV2({ serverOrigin: relay.origin, basePath: relay.id, transport: 'relay', ticket: issued.ticket,
        nonce: issued.nonce, expiresAt: issued.expiresAt, policyHash: hash, kitPublicKey: kitKeys.publicKey });
    store.setBinding(issued.ticket, binding);
    assert.equal(await relay.register({ ticket: issued.ticket, expiresAt: issued.expiresAt, policyBody: JSON.stringify({ ...policy, policy_hash: hash }) }), true);

    // Connect: decode the code, fetch the policy from the Relay, check its hash, seal v2 and upload.
    const payload = JSON.parse(Buffer.from(code.slice(4), 'base64url').toString('utf8'));
    const pol = relayServer.handle({ method: 'GET', path: `/${payload.base_path}/policy/${payload.ticket}`, headers: {}, body: Buffer.alloc(0), socketAddress: '198.51.100.20' });
    const served = JSON.parse(pol.body.toString('utf8'));
    assert.equal(policyHash(served), payload.policy_hash);
    const record = { schema: 2, binding: { ticket: payload.ticket, nonce: payload.nonce }, note: 'e2e' };
    const envelope = Buffer.from(sdk.sealEnvelopeV2(JSON.stringify(record), payload.kit_public_key, {
        base_path: payload.base_path, policy_hash: payload.policy_hash, server_origin: payload.server_origin,
        ticket: payload.ticket, transport: payload.transport }));
    const up = relayServer.handle({ method: 'POST', path: `/${payload.base_path}/report`, body: envelope, socketAddress: '198.51.100.20',
        headers: { 'x-rongroi-upload-id': payload.ticket, 'x-rongroi-report-sha256': sha(envelope), 'x-rongroi-envelope': '2' } });
    assert.equal(up.status, 202);
    const status = () => JSON.parse(relayServer.handle({ method: 'GET', path: `/srv1/status/${payload.ticket}/${sha(envelope)}`, headers: {},
        body: Buffer.alloc(0), socketAddress: '198.51.100.20' }).body.toString()).result;
    assert.equal(status(), 'pending');

    // Kit: one pull round, exactly what main.js does.
    ms += 2000;
    for (const ticket of store.relayTickets(600000)) {
        for (const e of await relay.pending(ticket)) {
            const s = handler.ingestRelay({ ticket, sha: e.sha256, raw: e.raw, receivedAt: e.receivedAt, address: e.address, addressSource: e.addressSource });
            await relay.result(ticket, e.sha256, s);
        }
    }
    assert.equal(status(), 'accepted');
    assert.equal(store.stateOf(issued.ticket), 'consumed');
    assert.equal(reports.length, 1);
    assert.equal(reports[0].address, '198.51.100.20');
    assert.equal(reports[0].addressSource, 'relay-socket');
    assert.deepEqual(store.relayTickets(600000), []);
});
