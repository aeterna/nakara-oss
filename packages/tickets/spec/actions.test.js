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
    assert.equal(reviveCalledWith, 1);
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
    assert.deepEqual(addItemArgs, { src: 1, item: 'bandage', count: 3 });
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

  it('give_item when AddItem returns [false, "invalid_inventory"] → returns ok:false, error, message containing invalid_inventory', async () => {
    actions.setConfig({
      enabledActions: ['player.info', 'player.teleport', 'player.give_item'],
      giveItem: {
        allow: {
          water: 5,
        },
      },
    });
    mockResourceStates.ox_inventory = 'started';

    mockExports.ox_inventory.CanCarryItem = () => true;
    mockExports.ox_inventory.AddItem = () => [false, 'invalid_inventory'];

    const res = await actions.executeAction({
      id: 'act-give-array-fail',
      action: 'player.give_item',
      discordId: '111122223333444455',
      params: {
        item: 'water',
        count: 1,
      },
    });

    assert.equal(res.ok, false);
    assert.equal(res.code, 'error');
    assert.match(res.message, /invalid_inventory/);
  });

  it('player id received by AddItem, CanCarryItem, and Revive is a number, while GetPlayers returns strings', async () => {
    actions.setConfig({
      enabledActions: ['player.info', 'player.teleport', 'player.revive', 'player.give_item'],
      giveItem: {
        allow: {
          water: 5,
        },
      },
    });
    mockResourceStates.ox_inventory = 'started';
    mockResourceStates.qbx_medical = 'started';

    let canCarryIdType = null;
    let addItemIdType = null;
    let reviveIdType = null;
    let getPlayersResultTypes = null;

    mockExports.ox_inventory.CanCarryItem = (src) => {
      canCarryIdType = typeof src;
      return true;
    };
    mockExports.ox_inventory.AddItem = (src) => {
      addItemIdType = typeof src;
      return true;
    };
    mockExports.qbx_medical.Revive = (src) => {
      reviveIdType = typeof src;
      return true;
    };
    const originalGetPlayers = globalThis.GetPlayers;
    globalThis.GetPlayers = () => {
      const players = originalGetPlayers();
      getPlayersResultTypes = players.map(p => typeof p);
      return players;
    };

    try {
      const resGive = await actions.executeAction({
        id: 'act-type-give',
        action: 'player.give_item',
        discordId: '111122223333444455',
        params: { item: 'water', count: 1 },
      });
      assert.equal(resGive.ok, true);

      const resRevive = await actions.executeAction({
        id: 'act-type-revive',
        action: 'player.revive',
        discordId: '111122223333444455',
      });
      assert.equal(resRevive.ok, true);

      assert.equal(addItemIdType, 'number');
      assert.equal(canCarryIdType, 'number');
      assert.equal(reviveIdType, 'number');
      assert.ok(getPlayersResultTypes.every(t => t === 'string'));
    } finally {
      globalThis.GetPlayers = originalGetPlayers;
    }
  });

  it('params.playerId of another online player is ignored and targets the discordId owner', async () => {
    onlinePlayers = ['1', '2'];
    playerIdentifiers = {
      '1': ['discord:111122223333444455'],
      '2': ['discord:222233334444555566'],
    };

    let teleportedPed = null;
    globalThis.GetPlayerPed = (src) => (Number(src) === 1 ? 101 : 102);
    globalThis.SetEntityCoords = (ped) => {
      teleportedPed = ped;
    };

    const res = await actions.executeAction({
      id: 'act-ignore-params-playerid',
      action: 'player.teleport',
      discordId: '111122223333444455',
      params: {
        spot: 'hospital',
        playerId: 2,
      },
    });

    assert.equal(res.ok, true);
    assert.equal(res.code, 'done');
    assert.equal(teleportedPed, 101);
  });

  it('params.playerId of an online player is ignored and fails with player_offline when discordId owner is not found', async () => {
    onlinePlayers = ['2'];
    playerIdentifiers = {
      '2': ['discord:222233334444555566'],
    };

    const res = await actions.executeAction({
      id: 'act-ignore-params-offline',
      action: 'player.teleport',
      discordId: '999999999999999999',
      params: {
        spot: 'hospital',
        playerId: 2,
      },
    });

    assert.equal(res.ok, false);
    assert.equal(res.code, 'player_offline');
  });

  it('action fails with invalid player ID when player lookup returns non-finite id', async () => {
    const playersModule = require('../server/js/players.js');
    const origFind = playersModule.findPlayerByDiscordId;
    try {
      playersModule.findPlayerByDiscordId = () => 'not_a_number';
      const res = await actions.executeAction({
        id: 'act-invalid-id',
        action: 'player.info',
        discordId: '111122223333444455',
      });
      assert.equal(res.ok, false);
      assert.equal(res.code, 'error');
      assert.equal(res.message, 'Invalid player ID');
    } finally {
      playersModule.findPlayerByDiscordId = origFind;
    }
  });

  it('action succeeds when player lookup returns a numeric string', async () => {
    const playersModule = require('../server/js/players.js');
    const origFind = playersModule.findPlayerByDiscordId;
    try {
      playersModule.findPlayerByDiscordId = () => '1';
      const res = await actions.executeAction({
        id: 'act-numeric-str-id',
        action: 'player.info',
        discordId: '111122223333444455',
      });
      assert.equal(res.ok, true);
      assert.equal(res.code, 'done');
    } finally {
      playersModule.findPlayerByDiscordId = origFind;
    }
  });
});
