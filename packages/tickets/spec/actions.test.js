const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert/strict');

// Stub FiveM globals before requiring modules
globalThis.GetResourceKvpString = () => null;
globalThis.SetResourceKvp = () => {};
globalThis.DeleteResourceKvp = () => {};

const actions = require('../server/js/actions.js');

describe('packages/tickets actions execution (g1)', () => {
  let mockExports;
  let mockResourceStates;
  let onlinePlayers;
  let playerIdentifiers;

  beforeEach(() => {
    mockResourceStates = {
      qbx_medical: 'missing',
      ox_inventory: 'missing',
      qbx_core: 'missing',
    };

    mockExports = {
      qbx_medical: {
        Revive: () => {},
      },
      ox_inventory: {
        CanCarryItem: () => true,
        AddItem: () => true,
      },
    };

    onlinePlayers = ['1'];
    playerIdentifiers = {
      '1': ['discord:111122223333444455'],
    };

    globalThis.GetResourceState = (resourceName) => mockResourceStates[resourceName] || 'missing';
    globalThis.GetPlayers = () => onlinePlayers;
    globalThis.GetPlayerIdentifiers = (playerId) => playerIdentifiers[playerId] || [];
    globalThis.GetPlayerName = () => 'TestPlayer';
    globalThis.GetPlayerPed = () => 100;
    globalThis.GetEntityCoords = () => ({ x: 0, y: 0, z: 0 });
    globalThis.exports = mockExports;

    // Reset config
    actions.setConfig({
      enabledActions: ['player.info', 'player.teleport'],
      teleportSpots: { hospital: { x: 300, y: -600, z: 43 } },
      giveItem: {
        allow: {},
      },
      logPrefix: '[nakara_tickets]',
    });
  });

  it('revive without qbx_medical → adapter_missing', async () => {
    actions.setConfig({
      enabledActions: ['player.info', 'player.teleport', 'player.revive'],
      giveItem: { allow: {} },
    });
    mockResourceStates.qbx_medical = 'missing';

    const res = await actions.executeAction({
      id: 'act-revive-missing',
      action: 'player.revive',
      discordId: '111122223333444455',
    });

    assert.equal(res.ok, false);
    assert.equal(res.code, 'adapter_missing');
  });

  it('revive when disabled → not_allowed', async () => {
    actions.setConfig({
      enabledActions: ['player.info', 'player.teleport'], // revive omitted
      giveItem: { allow: {} },
    });
    mockResourceStates.qbx_medical = 'started';

    const res = await actions.executeAction({
      id: 'act-revive-disabled',
      action: 'player.revive',
      discordId: '111122223333444455',
    });

    assert.equal(res.ok, false);
    assert.equal(res.code, 'not_allowed');
  });

  it('revive happy path calls exports.qbx_medical.Revive once', async () => {
    actions.setConfig({
      enabledActions: ['player.info', 'player.teleport', 'player.revive'],
      giveItem: { allow: {} },
    });
    mockResourceStates.qbx_medical = 'started';

    let reviveCalledWith = null;
    let reviveCallCount = 0;
    mockExports.qbx_medical.Revive = (src) => {
      reviveCallCount++;
      reviveCalledWith = src;
      return true;
    };

    const res = await actions.executeAction({
      id: 'act-revive-happy',
      action: 'player.revive',
      discordId: '111122223333444455',
    });

    assert.equal(res.ok, true);
    assert.equal(res.code, 'done');
    assert.equal(reviveCallCount, 1);
    assert.equal(reviveCalledWith, '1');
  });

  it('give_item not in allow → not_allowed', async () => {
    actions.setConfig({
      enabledActions: ['player.info', 'player.teleport', 'player.give_item'],
      giveItem: {
        allow: {
          bandage: 5,
        },
      },
    });
    mockResourceStates.ox_inventory = 'started';

    const res = await actions.executeAction({
      id: 'act-give-disallowed',
      action: 'player.give_item',
      discordId: '111122223333444455',
      params: {
        item: 'unauthorized_weapon',
        count: 1,
      },
    });

    assert.equal(res.ok, false);
    assert.equal(res.code, 'not_allowed');
  });

  it('give_item count above cap → over_cap', async () => {
    actions.setConfig({
      enabledActions: ['player.info', 'player.teleport', 'player.give_item'],
      giveItem: {
        allow: {
          bandage: 5,
        },
      },
    });
    mockResourceStates.ox_inventory = 'started';

    const res = await actions.executeAction({
      id: 'act-give-over-cap',
      action: 'player.give_item',
      discordId: '111122223333444455',
      params: {
        item: 'bandage',
        count: 10,
      },
    });

    assert.equal(res.ok, false);
    assert.equal(res.code, 'over_cap');
  });

  it('give_item happy path calls AddItem once', async () => {
    actions.setConfig({
      enabledActions: ['player.info', 'player.teleport', 'player.give_item'],
      giveItem: {
        allow: {
          bandage: 5,
        },
      },
    });
    mockResourceStates.ox_inventory = 'started';

    let canCarryCalled = false;
    let addItemCalledCount = 0;
    let addItemArgs = null;

    mockExports.ox_inventory.CanCarryItem = (src, item, count) => {
      canCarryCalled = true;
      return true;
    };
    mockExports.ox_inventory.AddItem = (src, item, count) => {
      addItemCalledCount++;
      addItemArgs = { src, item, count };
      return true;
    };

    const res = await actions.executeAction({
      id: 'act-give-happy',
      action: 'player.give_item',
      discordId: '111122223333444455',
      params: {
        item: 'bandage',
        count: 3,
      },
    });

    assert.equal(res.ok, true);
    assert.equal(res.code, 'done');
    assert.equal(canCarryCalled, true);
    assert.equal(addItemCalledCount, 1);
    assert.deepEqual(addItemArgs, { src: '1', item: 'bandage', count: 3 });
  });

  it('give_item prototype property rejection (Object.hasOwn) → not_allowed', async () => {
    actions.setConfig({
      enabledActions: ['player.give_item'],
      giveItem: {
        allow: {},
      },
    });
    mockResourceStates.ox_inventory = 'started';

    const res = await actions.executeAction({
      id: 'act-give-proto',
      action: 'player.give_item',
      discordId: '111122223333444455',
      params: {
        item: 'toString',
        count: 1,
      },
    });

    assert.equal(res.ok, false);
    assert.equal(res.code, 'not_allowed');
  });

  it('give_item non-integer or non-positive max cap → not_allowed', async () => {
    actions.setConfig({
      enabledActions: ['player.give_item'],
      giveItem: {
        allow: {
          zero_cap: 0,
          negative_cap: -2,
          float_cap: 3.5,
          string_cap: '10',
        },
      },
    });
    mockResourceStates.ox_inventory = 'started';

    const resZero = await actions.executeAction({
      id: 'act-give-zero',
      action: 'player.give_item',
      discordId: '111122223333444455',
      params: { item: 'zero_cap', count: 1 },
    });
    assert.equal(resZero.ok, false);
    assert.equal(resZero.code, 'not_allowed');

    const resNeg = await actions.executeAction({
      id: 'act-give-neg',
      action: 'player.give_item',
      discordId: '111122223333444455',
      params: { item: 'negative_cap', count: 1 },
    });
    assert.equal(resNeg.ok, false);
    assert.equal(resNeg.code, 'not_allowed');

    const resFloat = await actions.executeAction({
      id: 'act-give-float',
      action: 'player.give_item',
      discordId: '111122223333444455',
      params: { item: 'float_cap', count: 1 },
    });
    assert.equal(resFloat.ok, false);
    assert.equal(resFloat.code, 'not_allowed');

    const resStr = await actions.executeAction({
      id: 'act-give-str',
      action: 'player.give_item',
      discordId: '111122223333444455',
      params: { item: 'string_cap', count: 1 },
    });
    assert.equal(resStr.ok, false);
    assert.equal(resStr.code, 'not_allowed');
  });

  it('player.info uses lowercase getPlayers when GetPlayers is absent', async () => {
    const originalGetPlayers = globalThis.GetPlayers;
    try {
      delete globalThis.GetPlayers;
      globalThis.getPlayers = () => ['7'];
      playerIdentifiers = {
        '7': ['license:x', 'discord:111122223333444455'],
      };

      const res = await actions.executeAction({
        id: 'act-info-getplayers',
        action: 'player.info',
        discordId: '111122223333444455',
      });

      assert.notEqual(res.code, 'player_offline');
      assert.equal(res.ok, true);
      assert.equal(res.code, 'done');
    } finally {
      globalThis.GetPlayers = originalGetPlayers;
      delete globalThis.getPlayers;
    }
  });

  it('player.info uses player indices when GetPlayers and getPlayers are absent', async () => {
    const originalGetPlayers = globalThis.GetPlayers;
    try {
      delete globalThis.GetPlayers;
      playerIdentifiers = {
        '9': ['license:x', 'discord:111122223333444455'],
      };
      globalThis.GetNumPlayerIndices = () => 1;
      globalThis.GetPlayerFromIndex = (index) => (index === 0 ? 9 : null);

      const res = await actions.executeAction({
        id: 'act-info-indices',
        action: 'player.info',
        discordId: '111122223333444455',
      });

      assert.notEqual(res.code, 'player_offline');
      assert.equal(res.ok, true);
      assert.equal(res.code, 'done');
    } finally {
      globalThis.GetPlayers = originalGetPlayers;
      delete globalThis.GetNumPlayerIndices;
      delete globalThis.GetPlayerFromIndex;
    }
  });

  it('player.info uses GetNumPlayerIdentifiers and GetPlayerIdentifier when GetPlayerIdentifiers is absent', async () => {
    const originalGetPlayerIdentifiers = globalThis.GetPlayerIdentifiers;
    try {
      delete globalThis.GetPlayerIdentifiers;
      onlinePlayers = ['7'];
      const p7Identifiers = ['license:x', 'discord:111122223333444455'];
      globalThis.GetNumPlayerIdentifiers = (playerId) => (String(playerId) === '7' ? p7Identifiers.length : 0);
      globalThis.GetPlayerIdentifier = (playerId, index) => (String(playerId) === '7' ? p7Identifiers[index] : null);

      const res = await actions.executeAction({
        id: 'act-info-num-identifiers',
        action: 'player.info',
        discordId: '111122223333444455',
      });

      assert.notEqual(res.code, 'player_offline');
      assert.equal(res.ok, true);
      assert.equal(res.code, 'done');
    } finally {
      globalThis.GetPlayerIdentifiers = originalGetPlayerIdentifiers;
      delete globalThis.GetNumPlayerIdentifiers;
      delete globalThis.GetPlayerIdentifier;
    }
  });
});
