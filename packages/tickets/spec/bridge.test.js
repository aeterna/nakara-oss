const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');

// Stub FiveM globals on globalThis before loading modules
const kvpStore = new Map();
const registeredCommands = new Map();
let coordsSetCalled = false;
let actionExecutionCount = 0;

globalThis.GetConvar = (name, def) => {
  if (name === 'nakara_tickets_api') return 'https://tickets.example.com';
  if (name === 'gamename') return 'gta5';
  if (name === 'sv_projectName') return 'Test FiveM Server';
  return def;
};
globalThis.GetResourceKvpString = (key) => kvpStore.get(key) ?? null;
globalThis.SetResourceKvp = (key, val) => kvpStore.set(key, String(val));
globalThis.DeleteResourceKvp = (key) => kvpStore.delete(key);
globalThis.RegisterCommand = (name, handler, restricted) => {
  registeredCommands.set(name, handler);
};
globalThis.GetPlayers = () => ['1'];
globalThis.GetPlayerName = (id) => 'PlayerOne';
globalThis.GetPlayerPing = (id) => 25;
globalThis.GetPlayerPed = (id) => 1234;
globalThis.GetPlayerIdentifiers = (id) => [
  'license:1234567890abcdef',
  'discord:123456789012345678',
];
globalThis.GetEntityCoords = (ped) => ({ x: 100.0, y: 200.0, z: 30.0 });
globalThis.SetEntityCoords = (ped, x, y, z) => {
  coordsSetCalled = true;
};
globalThis.GetResourceState = (resName) => 'missing';
globalThis.exports = (name, fn) => {};

const { sha256hex, bridgeCanonical, signBridge, buildHeaders } = require('../server/js/signer.js');
const store = require('../server/js/store.js');
const api = require('../server/js/api.js');
const actions = require('../server/js/actions.js');
const pairing = require('../server/js/pairing.js');

describe('Resource nakara_tickets acceptance tests', () => {
  beforeEach(() => {
    kvpStore.clear();
    coordsSetCalled = false;
    actionExecutionCount = 0;
  });

  it('r1: signer output equals a literal vector also used in tickets/packages/core/test/hmac.test.ts (h1 input)', () => {
    const body = '{"action":"player.info"}';
    const bodyHash = sha256hex(body);
    const parts = {
      timestamp: 1700000000,
      nonce: 'fixed-nonce-123456',
      method: 'post',
      pathWithQuery: '/api/v1/bridge/actions?limit=50',
      body,
    };

    const canonical = bridgeCanonical(parts);
    const expected = `1700000000\nfixed-nonce-123456\nPOST\n/api/v1/bridge/actions?limit=50\n${bodyHash}`;
    assert.equal(canonical, expected);

    // Empty body test vector
    const partsEmpty = {
      timestamp: 1700000000,
      nonce: 'nonce-abc',
      method: 'GET',
      pathWithQuery: '/healthz',
      body: '',
    };
    const expectedEmpty = '1700000000\nnonce-abc\nGET\n/healthz\ne3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    assert.equal(bridgeCanonical(partsEmpty), expectedEmpty);

    // Signed output check
    const secret = 'test-secret-key-for-bridge-hmac-32b!';
    const sig = signBridge(secret, parts);
    const expectedSig = crypto.createHmac('sha256', secret).update(expected, 'utf8').digest('hex');
    assert.equal(sig, expectedSig);

    const headers = buildHeaders('server-uuid-1', secret, parts.method, parts.pathWithQuery, body, {
      timestamp: parts.timestamp,
      nonce: parts.nonce,
    });
    assert.equal(headers['X-Tickets-Server'], 'server-uuid-1');
    assert.equal(headers['X-Tickets-Timestamp'], '1700000000');
    assert.equal(headers['X-Tickets-Nonce'], 'fixed-nonce-123456');
    assert.equal(headers['X-Tickets-Signature'], sig);
    assert.equal(headers['X-Tickets-Protocol'], '1');
  });

  it('r2: pair refused when source ≠ 0', async () => {
    let fetchCalled = false;
    globalThis.fetch = async () => {
      fetchCalled = true;
      return new Response(JSON.stringify({ ok: true }));
    };

    const cmdHandler = registeredCommands.get('nakara_tickets');
    assert.ok(cmdHandler, 'nakara_tickets command must be registered');

    // Called by a player client (source = 1)
    await cmdHandler(1, ['pair', 'ABCD234567']);
    assert.equal(fetchCalled, false, 'fetch must not be called when source is not 0');
    assert.equal(store.getServerId(), null, 'server id must not be saved');

    // Negative control: source = 0 is allowed
    globalThis.fetch = async () => {
      fetchCalled = true;
      return new Response(JSON.stringify({
        serverId: '00000000-0000-4000-8000-000000000001',
        secret: 'dGVzdC1zZWNyZXQtMzItYnl0ZXMtc3RyaW5nLWJhc2U2NA',
        guildName: 'Test Guild',
      }), { status: 200, headers: { 'content-type': 'application/json' } });
    };

    await cmdHandler(0, ['pair', 'ABCD234567']);
    assert.equal(fetchCalled, true, 'fetch should be called when source is 0');
    assert.equal(store.getServerId(), '00000000-0000-4000-8000-000000000001');
  });

  it('r3: teleport to an unknown spot → not_allowed, natives not called', async () => {
    coordsSetCalled = false;
    const action = {
      id: '00000000-0000-4000-8000-000000000010',
      action: 'player.teleport',
      params: { spot: 'non_existent_secret_spot' },
      discordId: '123456789012345678',
    };

    const result = await actions.executeAction(action);
    assert.equal(result.ok, false);
    assert.equal(result.code, 'not_allowed');
    assert.equal(coordsSetCalled, false, 'SetEntityCoords native must not be called');
  });

  it('r4: action not enabled → not_allowed', async () => {
    const action = {
      id: '00000000-0000-4000-8000-000000000020',
      action: 'player.give_item',
      params: { item: 'bread', count: 1 },
      discordId: '123456789012345678',
    };

    const result = await actions.executeAction(action);
    assert.equal(result.ok, false);
    assert.equal(result.code, 'not_allowed');
  });

  it('r5: repeated id returns stored result, handler called once', async () => {
    actions.registerAction('custom.test_counter', null, async (params) => {
      actionExecutionCount++;
      return { ok: true, code: 'done', data: { count: actionExecutionCount } };
    });

    const action = {
      id: '00000000-0000-4000-8000-000000000030',
      action: 'custom.test_counter',
      params: {},
      discordId: '123456789012345678',
    };

    const res1 = await actions.executeAction(action);
    assert.equal(res1.ok, true);
    assert.equal(res1.data.count, 1);
    assert.equal(actionExecutionCount, 1);

    // Second execution with identical id
    const res2 = await actions.executeAction(action);
    assert.equal(res2.ok, true);
    assert.equal(res2.data.count, 1);
    assert.equal(actionExecutionCount, 1, 'handler must not be called a second time');
  });

  it('r6: non-JSON 200 body counts as failure', async () => {
    globalThis.fetch = async () => {
      return new Response('<html><head><title>502 Bad Gateway</title></head><body>Bad Gateway</body></html>', {
        status: 200,
        headers: { 'content-type': 'text/html' },
      });
    };

    const res = await api.pair('ABCD234567');
    assert.equal(res.ok, false);
    assert.ok(res.error, 'must report error when response is not valid JSON');

    const heartbeatRes = await api.sendHeartbeat('server-1', 'secret-1', { players: [] });
    assert.equal(heartbeatRes.ok, false);

    const actionsRes = await api.getActions('server-1', 'secret-1', 0);
    assert.equal(actionsRes.ok, false);
  });
});
