const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert/strict');

globalThis.GetResourceKvpString = () => null;
globalThis.SetResourceKvp = () => {};
globalThis.DeleteResourceKvp = () => {};
globalThis.GetConvar = (name, fallback) => fallback ?? '';

describe('tickets minors (W3b L6b)', () => {
  let mockExports;
  let mockResourceStates;

  beforeEach(() => {
    mockResourceStates = { qbx_medical: 'started' };
    mockExports = { qbx_medical: { Revive: () => true } };
    globalThis.GetResourceState = (name) => mockResourceStates[name] || 'missing';
    globalThis.exports = mockExports;
    globalThis.GetPlayers = () => ['1'];
    globalThis.GetPlayerIdentifiers = (id) => (String(id) === '1' ? ['discord:111122223333444455'] : []);
    globalThis.GetPlayerName = () => 'TestPlayer';
    globalThis.GetPlayerPed = () => 100;
  });

  it('item 1: actions loads config via LoadResourceFile when available', () => {
    const origLoad = globalThis.LoadResourceFile;
    const origGetRes = globalThis.GetCurrentResourceName;
    try {
      let called = null;
      globalThis.GetCurrentResourceName = () => 'nakara_tickets';
      globalThis.LoadResourceFile = (resName, file) => {
        called = { resName, file };
        return JSON.stringify({ enabledActions: ['test'] });
      };
      delete require.cache[require.resolve('../server/js/actions.js')];
      require('../server/js/actions.js');
      assert.deepEqual(called, { resName: 'nakara_tickets', file: 'config.json' });
    } finally {
      globalThis.LoadResourceFile = origLoad;
      globalThis.GetCurrentResourceName = origGetRes;
      delete require.cache[require.resolve('../server/js/actions.js')];
    }
  });

  it('item 2: loadSibling rethrows MODULE_NOT_FOUND when internal dependency is missing', () => {
    const actionsMod = require('../server/js/actions.js');
    const err = new Error("Cannot find module 'nonexistent_subdep'");
    err.code = 'MODULE_NOT_FOUND';
    assert.throws(
      () => actionsMod._loadSibling(() => { throw err; }, () => ({ fallback: true }), './local.js'),
      /nonexistent_subdep/
    );
  });

  it('item 3: player helpers are in server/js/players.js and imported cleanly', () => {
    const players = require('../server/js/players.js');
    assert.equal(typeof players.listPlayerIds, 'function');
    assert.equal(typeof players.listIdentifiers, 'function');
    assert.equal(typeof players.collectOnlinePlayers, 'function');
    assert.equal(players.findPlayerByDiscordId('111122223333444455'), 1);
  });

  it('item 4: qbx_medical.Revive returning false reports action as failed', async () => {
    const actions = require('../server/js/actions.js');
    actions.setConfig({ enabledActions: ['player.revive'] });
    mockExports.qbx_medical.Revive = () => false;

    const res = await actions.executeAction({
      id: 'act-revive-false',
      action: 'player.revive',
      discordId: '111122223333444455',
    });
    assert.equal(res.ok, false);
    assert.equal(res.code, 'error');
  });

  it('item 5: invalid player id guarded with Number.isFinite returns failed result', async () => {
    const actions = require('../server/js/actions.js');
    actions.setConfig({ enabledActions: ['player.info'] });
    let pedCalled = false;
    globalThis.GetPlayerPed = () => { pedCalled = true; return 100; };

    const res = await actions.executeAction({
      id: 'act-invalid-id',
      action: 'player.info',
      playerId: 'not-a-number',
    });
    assert.equal(res.ok, false);
    assert.equal(pedCalled, false);
  });

  it('item 6: api getActions clears abort timer and completes cleanly', async () => {
    const api = require('../server/js/api.js');
    const origFetch = globalThis.fetch;
    try {
      let passedSignal = null;
      globalThis.fetch = async (url, opts) => {
        passedSignal = opts.signal;
        return {
          ok: true,
          status: 200,
          text: async () => JSON.stringify({ action: null }),
        };
      };
      const res = await api.getActions('srv1', 'sec1', 25);
      assert.equal(res.ok, true);
      assert.equal(res.action, null);
      assert.equal(passedSignal.aborted, false);
    } finally {
      globalThis.fetch = origFetch;
    }
  });
});
