// Plain top-level requires: fivem-devkit safety must see every http/https destination in this file.
const http = require('http');
const https = require('https');

// FXServer resolves a relative require() against the resource root, not against the requiring file.
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

const { buildHeaders } = loadSibling(
  () => require('./signer.js'),
  () => require('./server/js/signer.js'),
  './signer.js'
);

const { sendRequest } = loadSibling(
  () => require('./http-request.js'),
  () => require('./server/js/http-request.js'),
  './http-request.js'
);

const API = GetConvar('nakara_tickets_api', '');
const REQUEST_TIMEOUT_MS = 35000;

// Every module-level bridge call goes through sendRequest, never the global fetch: fetch POSTs with a body log an
// unhandled rejection on FXServer (http-request.js). An https: base uses https.request, anything else http.request.
function bridgeRequest(pathWithQuery, options) {
  const start = (requestOptions, onResponse) => (API + pathWithQuery).startsWith('https:')
    ? https.request(API + pathWithQuery, requestOptions, onResponse)
    : http.request(API + pathWithQuery, requestOptions, onResponse);
  return sendRequest(start, options, REQUEST_TIMEOUT_MS);
}

async function parseJsonResponse(res) {
  try {
    const text = await res.text();
    try {
      return JSON.parse(text);
    } catch {
      return null;
    }
  } catch {
    if (res?.body && !res.bodyUsed) {
      try {
        await res.body.cancel();
      } catch {}
    }
    return null;
  }
}

async function pair(code, payload = {}) {
  const body = JSON.stringify({
    code,
    serverName: payload.serverName ?? GetConvar('sv_projectName', 'FiveM Server'),
    edition: payload.edition ?? GetConvar('gamename', 'gta5'),
    resourceVersion: payload.resourceVersion ?? '0.1.0',
    protocol: 1,
  });

  try {
    const res = await bridgeRequest('/bridge/v1/pair', {
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
  const body = JSON.stringify({
    players: payload.players ?? [],
    executedIds: payload.executedIds ?? [],
  });

  const authHeaders = buildHeaders(serverId, secret, 'POST', pathWithQuery, body);

  try {
    const res = await bridgeRequest(pathWithQuery, {
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

  const authHeaders = buildHeaders(serverId, secret, 'GET', pathWithQuery, '');
  try {
    const res = await bridgeRequest(pathWithQuery, {
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
  const body = JSON.stringify(resultPayload);

  const authHeaders = buildHeaders(serverId, secret, 'POST', pathWithQuery, body);

  try {
    const res = await bridgeRequest(pathWithQuery, {
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

function createApi({ fetchImpl, apiBase } = {}) {
  const customFetch = fetchImpl;
  const customBase = apiBase !== undefined ? apiBase : API;

  return {
    async pair(code, payload = {}) {
      const body = JSON.stringify({
        code,
        serverName: payload.serverName ?? 'Test FiveM Server',
        edition: payload.edition ?? 'gta5',
        resourceVersion: payload.resourceVersion ?? '0.1.0',
        protocol: 1,
      });

      try {
        const res = await customFetch(customBase + '/bridge/v1/pair', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body,
          signal: AbortSignal.timeout(35000),
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
    },

    async sendHeartbeat(serverId, secret, payload = {}) {
      const pathWithQuery = '/bridge/v1/heartbeat';
      const body = JSON.stringify({
        players: payload.players ?? [],
        executedIds: payload.executedIds ?? [],
      });

      const authHeaders = buildHeaders(serverId, secret, 'POST', pathWithQuery, body);

      try {
        const res = await customFetch(customBase + pathWithQuery, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            ...authHeaders,
          },
          body,
          signal: AbortSignal.timeout(35000),
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
    },

    async getActions(serverId, secret, wait = 25) {
      const waitParam = Math.max(0, Math.min(25, Number(wait)));
      const pathWithQuery = '/bridge/v1/actions?wait=' + waitParam;

      const authHeaders = buildHeaders(serverId, secret, 'GET', pathWithQuery, '');
      const controller = new AbortController();
      const timer = setTimeout(() => {
        try { controller.abort(); } catch {}
      }, 35000);

      try {
        const res = await customFetch(customBase + pathWithQuery, {
          method: 'GET',
          headers: {
            ...authHeaders,
          },
          signal: controller.signal,
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
      } finally {
        clearTimeout(timer);
      }
    },

    async postActionResult(serverId, secret, actionId, resultPayload) {
      const pathWithQuery = '/bridge/v1/actions/' + actionId + '/result';
      const body = JSON.stringify(resultPayload);

      const authHeaders = buildHeaders(serverId, secret, 'POST', pathWithQuery, body);

      try {
        const res = await customFetch(customBase + pathWithQuery, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            ...authHeaders,
          },
          body,
          signal: AbortSignal.timeout(35000),
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
    },
  };
}

module.exports = {
  pair,
  sendHeartbeat,
  getActions,
  postActionResult,
  createApi,
};
