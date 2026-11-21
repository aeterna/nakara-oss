// FXServer resolves a relative require() against the resource root, not against the requiring file, so
// './store.js' only exists on plain Node. Try the file-relative path first and fall back to the
// resource-root path. Every require() argument stays a string literal for the safety scanner.
function isMissingSpecifier(err, specifier) {
  if (!err || err.code !== 'MODULE_NOT_FOUND') return false;
  const msg = err.message || '';
  const suffix = specifier.startsWith('./') ? specifier.slice(1) : (specifier.startsWith('/') ? specifier : `/${specifier}`);
  const bare = specifier.startsWith('./') ? specifier.slice(2) : specifier;
  const winSuffix = suffix.replace(/\//g, '\\');
  return (
    msg.includes(`'${specifier}'`) ||
    msg.includes(`"${specifier}"`) ||
    msg.includes(`${suffix}'`) ||
    msg.includes(`${suffix}"`) ||
    msg.includes(`${winSuffix}'`) ||
    msg.includes(`${winSuffix}"`) ||
    msg.includes(`'${bare}'`) ||
    msg.includes(`"${bare}"`)
  );
}

function loadSibling(loadLocal, loadRoot, specifier) {
  try {
    return loadLocal();
  } catch (err) {
    if (!isMissingSpecifier(err, specifier)) throw err;
    return loadRoot();
  }
}

loadSibling(() => require('./pairing.js'), () => require('./server/js/pairing.js'), './pairing.js');
const store = loadSibling(() => require('./store.js'), () => require('./server/js/store.js'), './store.js');
const api = loadSibling(() => require('./api.js'), () => require('./server/js/api.js'), './api.js');
const actions = loadSibling(() => require('./actions.js'), () => require('./server/js/actions.js'), './actions.js');
const players = loadSibling(() => require('./players.js'), () => require('./server/js/players.js'), './players.js');

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function heartbeatTick() {
  try {
    const serverId = store.getServerId();
    const secret = store.getSecret();
    if (!serverId || !secret) return;

    const onlineList = players.collectOnlinePlayers();
    const executedIds = store.getExecutedIds(60);

    await api.sendHeartbeat(serverId, secret, { players: onlineList, executedIds });
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
  collectOnlinePlayers: players.collectOnlinePlayers,
  heartbeatTick,
  stop: () => {
    pollingActive = false;
    if (heartbeatInterval) clearInterval(heartbeatInterval);
  },
};
