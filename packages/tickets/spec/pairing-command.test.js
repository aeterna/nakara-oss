const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const packageRoot = path.resolve(__dirname, '..');
const serverJs = path.join(packageRoot, 'server', 'js');

const stubbedGlobals = [
  'GetConvar',
  'GetResourceKvpString',
  'SetResourceKvp',
  'DeleteResourceKvp',
  'RegisterCommand',
  'GetCurrentResourceName',
  'fetch',
];

function clearServerCache() {
  for (const key of Object.keys(require.cache)) {
    if (key.startsWith(serverJs + path.sep)) {
      delete require.cache[key];
    }
  }
}

test('nakara_tickets pair command works when FXServer passes rawCommand as the third argument', async () => {
  const kvpStore = new Map();
  const registeredCommands = new Map();
  const fetchCalls = [];
  const originals = {};
  for (const name of stubbedGlobals) originals[name] = globalThis[name];

  globalThis.GetConvar = (name, def) => {
    if (name === 'nakara_tickets_api') return 'http://tickets.test';
    return def;
  };
  globalThis.GetResourceKvpString = (key) => kvpStore.get(key) ?? null;
  globalThis.SetResourceKvp = (key, val) => kvpStore.set(key, String(val));
  globalThis.DeleteResourceKvp = (key) => kvpStore.delete(key);
  globalThis.RegisterCommand = (name, handler, restricted) => {
    registeredCommands.set(name, handler);
  };
  globalThis.GetCurrentResourceName = () => 'nakara_tickets';
  globalThis.fetch = async (url, options) => {
    fetchCalls.push({ url: String(url), options });
    return new Response(
      JSON.stringify({
        serverId: '00000000-0000-4000-8000-000000000042',
        secret: 'dGVzdC1zZWNyZXQtMzItYnl0ZXMtc3RyaW5nLWJhc2U2NA',
        guildName: 'Test Guild',
      }),
      { status: 200, headers: { 'content-type': 'application/json' } }
    );
  };

  try {
    clearServerCache();

    require('../server/js/pairing.js');
    const store = require('../server/js/store.js');

    const handler = registeredCommands.get('nakara_tickets');
    assert.ok(handler, 'nakara_tickets command must be registered');

    // FXServer invokes the handler as (source, args, rawCommand).
    await handler(0, ['pair', 'ABCDEFGH12'], 'nakara_tickets pair ABCDEFGH12');

    assert.equal(fetchCalls.length, 1, 'pair must make exactly one http request');
    assert.ok(fetchCalls[0].url.includes('/bridge/v1/pair'), 'pair must call the pair route');
    assert.equal(store.getServerId(), '00000000-0000-4000-8000-000000000042');
  } finally {
    for (const name of stubbedGlobals) {
      if (originals[name] === undefined) delete globalThis[name];
      else globalThis[name] = originals[name];
    }
    clearServerCache();
  }
});
