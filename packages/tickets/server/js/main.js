require('./pairing.js');
const store = require('./store.js');
const api = require('./api.js');
const actions = require('./actions.js');

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function collectOnlinePlayers() {
  if (typeof GetPlayers !== 'function') return [];
  const players = GetPlayers();
  const list = [];

  for (const playerId of players) {
    let discordId = null;
    if (typeof GetPlayerIdentifiers === 'function') {
      const identifiers = GetPlayerIdentifiers(playerId) || [];
      for (const idStr of identifiers) {
        if (idStr.toLowerCase().startsWith('discord:')) {
          discordId = idStr.slice(8);
          break;
        }
      }
    }

    if (discordId) {
      const name = typeof GetPlayerName === 'function' ? GetPlayerName(playerId) : 'Unknown';
      list.push({
        playerId: Number(playerId),
        discordId,
        name,
      });
    }
  }

  return list;
}

async function heartbeatTick() {
  const serverId = store.getServerId();
  const secret = store.getSecret();
  if (!serverId || !secret) return;

  const players = collectOnlinePlayers();
  const executedIds = store.getExecutedIds(60);

  await api.sendHeartbeat(serverId, secret, { players, executedIds });
}

let pollingActive = true;

async function pollActionsLoop() {
  while (pollingActive) {
    const serverId = store.getServerId();
    const secret = store.getSecret();

    if (!serverId || !secret) {
      await sleep(2000);
      continue;
    }

    const pollRes = await api.getActions(serverId, secret, 25);

    if (!pollRes.ok) {
      // On network error wait 5 s
      await sleep(5000);
      continue;
    }

    if (pollRes.action) {
      const leasedAction = pollRes.action;
      const result = await actions.executeAction(leasedAction);

      // Retry POST result with backoff (1, 2, 4 ... up to 30 s) until accepted or unpaired
      let backoffSec = 1;
      while (pollingActive) {
        const curServerId = store.getServerId();
        const curSecret = store.getSecret();
        if (!curServerId || !curSecret) break;

        const resultRes = await api.postActionResult(curServerId, curSecret, leasedAction.id, result);
        if (resultRes.ok) {
          break;
        }

        await sleep(backoffSec * 1000);
        backoffSec = Math.min(30, backoffSec * 2);
      }
    }
  }
}

// Start timers and worker loops if in FXServer or node runtime
let heartbeatInterval = null;
if (typeof setInterval === 'function') {
  heartbeatInterval = setInterval(heartbeatTick, 30_000);
}

// Kick off poll loop asynchronously
pollActionsLoop().catch(() => {});

module.exports = {
  collectOnlinePlayers,
  heartbeatTick,
  stop: () => {
    pollingActive = false;
    if (heartbeatInterval) clearInterval(heartbeatInterval);
  },
};
