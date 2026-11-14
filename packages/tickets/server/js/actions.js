const store = require('./store.js');
let config = require('../../config.json');

const customActions = new Map(); // actionName -> { schema, fn }

function setConfig(cfg) {
  config = cfg;
}

function registerAction(name, schema, fn) {
  customActions.set(name, { schema, fn });
}

if (typeof globalThis.exports !== 'undefined' && typeof globalThis.exports === 'function') {
  try {
    globalThis.exports('registerAction', registerAction);
  } catch {}
}

function findPlayerByDiscordId(targetDiscordId) {
  if (!targetDiscordId || typeof GetPlayers !== 'function') return null;

  const players = GetPlayers();
  const searchPrefix = 'discord:' + targetDiscordId.toLowerCase();

  for (const playerId of players) {
    if (typeof GetPlayerIdentifiers === 'function') {
      const identifiers = GetPlayerIdentifiers(playerId) || [];
      for (const idStr of identifiers) {
        if (idStr.toLowerCase() === searchPrefix) {
          return playerId;
        }
      }
    }
  }

  return null;
}

async function executeAction(action) {
  // Check if this action id was already executed
  const storedResult = store.getExecutedResult(action.id);
  if (storedResult) {
    return storedResult;
  }

  const actionName = action.action;

  // Check if action is allowed
  const isCustom = customActions.has(actionName);
  const isEnabledBuiltIn = Array.isArray(config.enabledActions) && config.enabledActions.includes(actionName);

  if (!isCustom && !isEnabledBuiltIn) {
    return {
      ok: false,
      code: 'not_allowed',
      message: `Action ${actionName} is not enabled`,
    };
  }

  let result;

  if (isCustom) {
    const handler = customActions.get(actionName).fn;
    try {
      result = await handler(action.params ?? {}, action);
    } catch (err) {
      result = {
        ok: false,
        code: 'error',
        message: err.message,
      };
    }
  } else if (actionName === 'player.info') {
    const playerId = findPlayerByDiscordId(action.discordId);
    if (!playerId) {
      result = {
        ok: false,
        code: 'player_offline',
        message: 'Player is not online',
      };
    } else {
      const name = typeof GetPlayerName === 'function' ? GetPlayerName(playerId) : 'Unknown';
      const ping = typeof GetPlayerPing === 'function' ? GetPlayerPing(playerId) : 0;
      const ped = typeof GetPlayerPed === 'function' ? GetPlayerPed(playerId) : null;
      const coords = (ped !== null && ped !== 0 && typeof GetEntityCoords === 'function') ? GetEntityCoords(ped) : null;

      let job = null;
      if (typeof GetResourceState === 'function' && GetResourceState('qbx_core') === 'started') {
        try {
          if (
            typeof globalThis.exports !== 'undefined' &&
            globalThis.exports['qbx_core'] &&
            typeof globalThis.exports['qbx_core'].GetPlayer === 'function'
          ) {
            const qbxPlayer = globalThis.exports['qbx_core'].GetPlayer(playerId);
            job = qbxPlayer?.PlayerData?.job?.name ?? null;
          }
        } catch {}
      }

      result = {
        ok: true,
        code: 'done',
        data: {
          name,
          ping,
          coords,
          job,
        },
      };
    }
  } else if (actionName === 'player.teleport') {
    const spotName = action.params?.spot;
    const spot = config.teleportSpots?.[spotName];

    if (!spot || typeof spot.x !== 'number' || typeof spot.y !== 'number' || typeof spot.z !== 'number') {
      result = {
        ok: false,
        code: 'not_allowed',
        message: `Unknown or disallowed teleport spot: ${spotName}`,
      };
    } else {
      const playerId = findPlayerByDiscordId(action.discordId);
      if (!playerId) {
        result = {
          ok: false,
          code: 'player_offline',
          message: 'Player is not online',
        };
      } else {
        const ped = typeof GetPlayerPed === 'function' ? GetPlayerPed(playerId) : null;
        if (!ped || ped === 0) {
          result = {
            ok: false,
            code: 'error',
            message: 'Player ped not found',
          };
        } else {
          if (typeof SetEntityCoords === 'function') {
            SetEntityCoords(ped, spot.x, spot.y, spot.z, false, false, false, false);
          }
          result = {
            ok: true,
            code: 'done',
            data: { spot: spotName },
          };
        }
      }
    }
  } else {
    result = {
      ok: false,
      code: 'not_allowed',
      message: `Unsupported action: ${actionName}`,
    };
  }

  // Record executed action in store
  store.recordExecutedAction(action.id, result);
  return result;
}

module.exports = {
  executeAction,
  registerAction,
  findPlayerByDiscordId,
  setConfig,
};
