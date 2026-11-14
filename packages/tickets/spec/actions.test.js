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
});
