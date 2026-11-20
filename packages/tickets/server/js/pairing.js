// FXServer resolves a relative require() against the resource root, not against the requiring file.
function isMissingModule(err) {
  if (!err) return false;
  return err.code === 'MODULE_NOT_FOUND' || /^Cannot find module\b/.test(err.message || '');
}

function loadSibling(loadLocal, loadRoot) {
  try {
    return loadLocal();
  } catch (err) {
    if (!isMissingModule(err)) throw err;
    return loadRoot();
  }
}

const store = loadSibling(() => require('./store.js'), () => require('./server/js/store.js'));
const api = loadSibling(() => require('./api.js'), () => require('./server/js/api.js'));

async function handleCommand(source, args, injectedApi = api) {
  // Refuse unless source === 0 (server console)
  if (source !== 0) {
    if (typeof console !== 'undefined' && console.warn) {
      console.warn('[nakara_tickets] Command refused: must be executed from server console.');
    }
    return;
  }

  const sub = args && args[0] ? String(args[0]).toLowerCase() : 'status';

  if (sub === 'pair') {
    const code = args[1] ? String(args[1]).trim() : '';
    if (!code) {
      console.log('[nakara_tickets] Usage: nakara_tickets pair <code>');
      return;
    }

    const res = await injectedApi.pair(code);
    if (res.ok && res.data) {
      store.setCredentials(res.data.serverId, res.data.secret);
      // NEVER print the secret
      console.log(`[nakara_tickets] Successfully paired with guild "${res.data.guildName}". Awaiting staff confirmation.`);
    } else {
      console.log(`[nakara_tickets] Pairing failed: ${res.message || res.error}`);
    }
  } else if (sub === 'unpair') {
    store.clearCredentials();
    console.log('[nakara_tickets] Server unpaired.');
  } else if (sub === 'status') {
    const serverId = store.getServerId();
    if (serverId) {
      console.log(`[nakara_tickets] Status: Paired (Server ID: ${serverId})`);
    } else {
      console.log('[nakara_tickets] Status: Unpaired. Run "nakara_tickets pair <code>" to pair.');
    }
  } else {
    console.log('[nakara_tickets] Unknown subcommand. Available: pair <code>, status, unpair');
  }
}

if (typeof RegisterCommand === 'function') {
  // FXServer passes the raw command string as the third argument; only forward a spec-injected api object.
  RegisterCommand(
    'nakara_tickets',
    (source, args, injectedApi) =>
      handleCommand(source, args, injectedApi && typeof injectedApi === 'object' ? injectedApi : undefined),
    true
  );
}

module.exports = {
  handleCommand,
};
