const crypto = require('node:crypto');

function sha256hex(data = '') {
  const buf = Buffer.isBuffer(data) ? data : Buffer.from(data ?? '', 'utf8');
  return crypto.createHash('sha256').update(buf).digest('hex');
}

function bridgeCanonical(parts) {
  const method = parts.method.toUpperCase();
  const bodyHash = sha256hex(parts.body ?? '');
  return `${parts.timestamp}\n${parts.nonce}\n${method}\n${parts.pathWithQuery}\n${bodyHash}`;
}

function signBridge(secret, parts) {
  const key = Buffer.isBuffer(secret) ? secret : Buffer.from(secret, 'base64url');
  const canonical = bridgeCanonical(parts);
  return crypto.createHmac('sha256', key).update(canonical, 'utf8').digest('hex');
}

function buildHeaders(serverId, secret, method, pathWithQuery, body, options = {}) {
  const timestamp = options.timestamp !== undefined ? options.timestamp : Math.floor(Date.now() / 1000);
  const nonce = options.nonce !== undefined ? options.nonce : crypto.randomBytes(16).toString('hex');
  const signature = signBridge(secret, {
    timestamp,
    nonce,
    method,
    pathWithQuery,
    body: body ?? '',
  });

  return {
    'X-Tickets-Server': serverId,
    'X-Tickets-Timestamp': String(timestamp),
    'X-Tickets-Nonce': nonce,
    'X-Tickets-Signature': signature,
    'X-Tickets-Protocol': '1',
  };
}

module.exports = {
  sha256hex,
  bridgeCanonical,
  signBridge,
  buildHeaders,
};
