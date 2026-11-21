// Rongroi Relay
// SPDX-License-Identifier: MIT
'use strict';

// Runs the relay on plain HTTP behind a TLS proxy (Caddy in compose.yaml). Config from the environment:
//   RELAY_SERVERS   JSON [{ "id": "my-server", "keySha256": "<64 hex>" }]  (generate with `node main.js keygen <id>`)
//   RELAY_TRUSTED_PROXIES  comma-separated socket addresses whose X-Forwarded-For is believed (the proxy)
//   PORT            default 8080
const http = require('node:http');
const crypto = require('node:crypto');
const { createRelay, MAX_ENVELOPE_BYTES } = require('./relay.js');

if (process.argv[2] === 'keygen') {
    const id = process.argv[3];
    if (!/^[a-z0-9_-]{1,64}$/.test(id || '') || id === 'v1') {
        console.error('usage: node main.js keygen <server-id>   (id: a-z 0-9 _ -, not v1)');
        process.exit(2);
    }
    const key = crypto.randomBytes(32).toString('base64url');
    console.log(`Give this to the game server (server.cfg, set, never setr):\n  set rongroi_relay_id "${id}"\n  set rongroi_relay_key "${key}"`);
    console.log(`Add this to RELAY_SERVERS on the relay:\n  { "id": "${id}", "keySha256": "${crypto.createHash('sha256').update(key).digest('hex')}" }`);
    process.exit(0);
}

let servers;
try {
    servers = JSON.parse(process.env.RELAY_SERVERS || '[]');
} catch {
    console.error('RELAY_SERVERS is not JSON');
    process.exit(2);
}
const trustedProxies = (process.env.RELAY_TRUSTED_PROXIES || '').split(',').map((s) => s.trim()).filter(Boolean);
let relay;
try {
    relay = createRelay({ servers, trustedProxies, log: (line) => console.log(line) });
} catch (err) {
    console.error(`RELAY_SERVERS: ${err.message}`);
    process.exit(2);
}
setInterval(() => relay.sweep(), 30000).unref();

const ERROR_500 = { status: 500, headers: { 'Content-Type': 'application/json' }, body: Buffer.from('{"status":500}') };
const ERROR_413 = { status: 413, headers: { 'Content-Type': 'application/json' }, body: Buffer.from('{"status":413}') };

function send(res, out) {
    res.writeHead(out.status, out.headers);
    res.end(out.body);
}

const server = http.createServer((req, res) => {
    const base = { method: req.method, path: req.url, headers: req.headers, socketAddress: req.socket.remoteAddress };
    let early;
    try {
        early = relay.preflight(base);
    } catch {
        early = ERROR_500;
    }
    if (early) {
        // Answer without reading the body, and close: the client may still be sending.
        res.setHeader('Connection', 'close');
        send(res, early);
        req.resume();
        return;
    }
    const chunks = [];
    let size = 0;
    let over = false;
    req.on('data', (c) => {
        if (over) return;
        size += c.length;
        if (size > MAX_ENVELOPE_BYTES) {
            over = true;
            res.setHeader('Connection', 'close');
            send(res, ERROR_413);
            req.destroy();
            return;
        }
        chunks.push(c);
    });
    req.on('end', () => {
        if (over) return;
        let out;
        try {
            out = relay.handle({ ...base, body: Buffer.concat(chunks) }, { preflighted: true });
        } catch {
            out = ERROR_500;
        }
        send(res, out);
    });
});
// A slow client cannot hold a connection, and its buffer, open for long.
server.headersTimeout = 15000;
server.requestTimeout = 30000;
server.listen(Number(process.env.PORT || 8080), () => console.log(`rongroi relay listening on ${server.address().port}`));
