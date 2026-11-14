const { buildHeaders } = require('./signer.js');

const API = GetConvar('nakara_tickets_api', '');

async function parseJsonResponse(res) {
  try {
    const text = await res.text();
    return JSON.parse(text);
  } catch {
    return null;
  }
}

async function pair(code, payload = {}) {
  const url = API + '/bridge/v1/pair';
  const body = JSON.stringify({
    code,
    serverName: payload.serverName ?? GetConvar('sv_projectName', 'FiveM Server'),
    edition: payload.edition ?? GetConvar('gamename', 'gta5'),
    resourceVersion: payload.resourceVersion ?? '0.1.0',
    protocol: 1,
  });

  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body,
    });

    const json = await parseJsonResponse(res);
    if (
      res.ok &&
      json &&
      typeof json.serverId === 'string' &&
      typeof json.secret === 'string' &&
      typeof json.guildName === 'string'
    ) {
      return { ok: true, data: json };
    }

    return {
      ok: false,
      error: (json && json.code) ? json.code : 'pair_failed',
      message: (json && json.message) ? json.message : 'Invalid response from bridge',
    };
  } catch (err) {
    return { ok: false, error: 'network_error', message: err.message };
  }
}

async function sendHeartbeat(serverId, secret, payload = {}) {
  const pathWithQuery = '/bridge/v1/heartbeat';
  const url = API + '/bridge/v1/heartbeat';
  const body = JSON.stringify({
    players: payload.players ?? [],
    executedIds: payload.executedIds ?? [],
  });

  const authHeaders = buildHeaders(serverId, secret, 'POST', pathWithQuery, body);

  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...authHeaders,
      },
      body,
    });

    const json = await parseJsonResponse(res);
    if (res.ok && json && json.ok === true) {
      return { ok: true, data: json };
    }

    return {
      ok: false,
      error: (json && json.code) ? json.code : 'heartbeat_failed',
    };
  } catch (err) {
    return { ok: false, error: 'network_error', message: err.message };
  }
}

async function getActions(serverId, secret, wait = 25) {
  const waitParam = Math.max(0, Math.min(25, Number(wait)));
  const pathWithQuery = '/bridge/v1/actions?wait=' + waitParam;
  const url = API + '/bridge/v1/actions?wait=' + waitParam;

  const authHeaders = buildHeaders(serverId, secret, 'GET', pathWithQuery, '');

  try {
    const res = await fetch(url, {
      method: 'GET',
      headers: {
        ...authHeaders,
      },
    });

    const json = await parseJsonResponse(res);
    if (res.ok && json && typeof json === 'object' && 'action' in json) {
      return { ok: true, action: json.action };
    }

    return {
      ok: false,
      error: (json && json.code) ? json.code : 'actions_poll_failed',
    };
  } catch (err) {
    return { ok: false, error: 'network_error', message: err.message };
  }
}

async function postActionResult(serverId, secret, actionId, resultPayload) {
  const pathWithQuery = '/bridge/v1/actions/' + actionId + '/result';
  const url = API + '/bridge/v1/actions/' + actionId + '/result';
  const body = JSON.stringify(resultPayload);

  const authHeaders = buildHeaders(serverId, secret, 'POST', pathWithQuery, body);

  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...authHeaders,
      },
      body,
    });

    const json = await parseJsonResponse(res);
    if (res.ok && json && json.ok === true) {
      return { ok: true, data: json };
    }

    return {
      ok: false,
      status: res.status,
      error: (json && json.code) ? json.code : 'result_failed',
    };
  } catch (err) {
    return { ok: false, error: 'network_error', message: err.message };
  }
}

module.exports = {
  pair,
  sendHeartbeat,
  getActions,
  postActionResult,
};
