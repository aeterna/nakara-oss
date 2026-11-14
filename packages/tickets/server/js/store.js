const KVP_SERVER_ID = 'nakara_tickets_server_id';
const KVP_SECRET = 'nakara_tickets_secret';
const KVP_EXECUTED = 'nakara_tickets_executed';

const memoryActions = new Map(); // actionId -> { result, timestamp }

function getServerId() {
  return GetResourceKvpString(KVP_SERVER_ID);
}

function getSecret() {
  return GetResourceKvpString(KVP_SECRET);
}

function setCredentials(serverId, secret) {
  SetResourceKvp(KVP_SERVER_ID, serverId);
  SetResourceKvp(KVP_SECRET, secret);
}

function clearCredentials() {
  DeleteResourceKvp(KVP_SERVER_ID);
  DeleteResourceKvp(KVP_SECRET);
}

function loadKvpExecutedList() {
  const raw = GetResourceKvpString(KVP_EXECUTED);
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function saveKvpExecutedList(list) {
  try {
    SetResourceKvp(KVP_EXECUTED, JSON.stringify(list));
  } catch {}
}

function getExecutedResult(actionId) {
  if (memoryActions.has(actionId)) {
    return memoryActions.get(actionId).result;
  }

  const list = loadKvpExecutedList();
  const found = list.find((item) => item.id === actionId);
  if (found) {
    memoryActions.set(actionId, { result: found.result, timestamp: found.timestamp });
    return found.result;
  }

  return null;
}

function recordExecutedAction(actionId, result) {
  const now = Date.now();
  memoryActions.set(actionId, { result, timestamp: now });

  const list = loadKvpExecutedList();
  list.push({ id: actionId, result, timestamp: now });

  // Trim list to the last 120 seconds
  const cutoff = now - 120 * 1000;
  const trimmed = list.filter((item) => typeof item.timestamp === 'number' && item.timestamp >= cutoff);
  saveKvpExecutedList(trimmed);
}

function getExecutedIds(windowSeconds = 60) {
  const cutoff = Date.now() - windowSeconds * 1000;
  const ids = new Set();

  for (const [id, entry] of memoryActions.entries()) {
    if (entry.timestamp >= cutoff) {
      ids.add(id);
    }
  }

  const list = loadKvpExecutedList();
  for (const item of list) {
    if (item.timestamp >= cutoff) {
      ids.add(item.id);
    }
  }

  return Array.from(ids);
}

module.exports = {
  getServerId,
  getSecret,
  setCredentials,
  clearCredentials,
  getExecutedResult,
  recordExecutedAction,
  getExecutedIds,
};
