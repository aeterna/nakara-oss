function listPlayerIds() {
  if (typeof GetPlayers === 'function') return GetPlayers().map(String);
  if (typeof getPlayers === 'function') return getPlayers().map(String);
  if (typeof GetNumPlayerIndices === 'function' && typeof GetPlayerFromIndex === 'function') {
    const ids = [];
    const count = GetNumPlayerIndices();
    for (let i = 0; i < count; i++) ids.push(String(GetPlayerFromIndex(i)));
    return ids;
  }
  return [];
}

function listIdentifiers(playerId) {
  const idNum = Number(playerId);
  if (!Number.isFinite(idNum)) return [];
  if (typeof GetPlayerIdentifiers === 'function') return GetPlayerIdentifiers(playerId) || [];
  if (typeof GetNumPlayerIdentifiers === 'function' && typeof GetPlayerIdentifier === 'function') {
    const ids = [];
    const count = GetNumPlayerIdentifiers(playerId);
    for (let k = 0; k < count; k++) ids.push(String(GetPlayerIdentifier(playerId, k)));
    return ids;
  }
  return [];
}

function collectOnlinePlayers() {
  const list = [];
  for (const rawId of listPlayerIds()) {
    const idNum = Number(rawId);
    if (!Number.isFinite(idNum)) continue;
    let discordId = null;
    for (const idStr of listIdentifiers(idNum) || []) {
      if (typeof idStr === 'string' && idStr.toLowerCase().startsWith('discord:')) {
        discordId = idStr.slice(8);
        break;
      }
    }
    if (discordId) {
      const name = typeof GetPlayerName === 'function' ? GetPlayerName(idNum) : 'Unknown';
      list.push({ playerId: idNum, discordId, name });
    }
  }
  return list;
}

function findPlayerByDiscordId(targetDiscordId) {
  if (!targetDiscordId) return null;
  const searchPrefix = 'discord:' + String(targetDiscordId).toLowerCase();
  for (const rawId of listPlayerIds()) {
    const idNum = Number(rawId);
    if (!Number.isFinite(idNum)) continue;
    for (const idStr of listIdentifiers(idNum) || []) {
      if (typeof idStr === 'string' && idStr.toLowerCase() === searchPrefix) return idNum;
    }
  }
  return null;
}

module.exports = {
  listPlayerIds,
  listIdentifiers,
  collectOnlinePlayers,
  findPlayerByDiscordId,
};
