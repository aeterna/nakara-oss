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
  try {
    const serverId = store.getServerId();
    const secret = store.getSecret();
    if (!serverId || !secret) return;

    const players = collectOnlinePlayers();
    const executedIds = store.getExecutedIds(60);

    await api.sendHeartbeat(serverId, secret, { players, executedIds });
  } catch (err) {
    console.error('[nakara_tickets] Heartbeat error:', err.message);
  }
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

    try {
      const pollRes = await api.getActions(serverId, secret, 25);

      if (!pollRes.ok) {
        console.warn(`[nakara_tickets] Actions poll failed: ${pollRes.error || 'network error'}`);
        await sleep(5000);
        continue;
      }

      if (pollRes.action) {
        const leasedAction = pollRes.action;
        const result = await actions.executeAction(leasedAction);

        let backoffSec = 1;
        let attempts = 0;
        while (pollingActive && attempts < 10) {
          const curServerId = store.getServerId();
          const curSecret = store.getSecret();
          if (!curServerId || !curSecret) break;

          attempts++;
          const resultRes = await api.postActionResult(curServerId, curSecret, leasedAction.id, result);
          if (resultRes.ok) {
            break;
          }

          if (resultRes.status && resultRes.status >= 400 && resultRes.status < 500 && resultRes.status !== 429) {
            console.warn(`[nakara_tickets] Result rejected with 4xx status ${resultRes.status} (${resultRes.error}): dropping action ${leasedAction.id}`);
            break;
          }

          if (attempts >= 10) {
            console.warn(`[nakara_tickets] Result retry exceeded 10 attempts for action ${leasedAction.id}: dropping`);
            break;
          }

          await sleep(backoffSec * 1000);
          backoffSec = Math.min(30, backoffSec * 2);
        }
      } else {
        // null action received -> sleep at least 1 s
        await sleep(1000);
      }
    } catch (err) {
      console.error('[nakara_tickets] Error in actions poll loop:', err.message);
      await sleep(5000);
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
