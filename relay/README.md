# Rongroi Relay

An HTTPS drop box you run for your own game server, so Rongroi Connect can deliver a player's report without
reaching the game server's port. Use it when your server sits behind the Cfx proxy, when you want HTTPS, or when your
server is not FiveM. AETERNA runs no relay for you; this is yours. Design: aeterna-rongroi ADR 0097.

What it does and does not do:

- It stores **ciphertext only**. Your game server holds the private key, pulls each envelope, checks it and tells the
  relay whether it accepted it. The relay cannot read a report.
- It keeps the ticket, sizes, times and the uploader's address while a case is open, in memory. A restart forgets them.
- It never says whether a PC passed anything. Rongroi shows evidence for your staff to read; it has no verdict.
- Reports are not signed (aeterna-rongroi ADR 0040): anyone holding a case's code can upload. The relay keeps at most
  3 pending envelopes per ticket, and an envelope your server rejects frees its place.

## Run it

1. Point a domain at the machine (for example `relay.example.org`) and open ports 80 and 443.
2. Make a key for each game server:
   ```bash
   docker compose run --rm relay node main.js keygen my-server
   ```
   It prints the two `set` lines for the game server's `server.cfg` and the `RELAY_SERVERS` entry for the relay.
   The relay stores only the key's SHA-256.
3. Put the entry in `compose.yaml` (`RELAY_SERVERS`), your domain in `Caddyfile`, then `docker compose up -d`.
4. On the game server, add to `server.cfg` (with `set`, never `setr`, which would send the key to every player):
   ```
   ensure nakara_rongroi
   set rongroi_relay_url "https://relay.example.org"
   set rongroi_relay_id "my-server"
   set rongroi_relay_key "<from step 2>"
   ```
5. In the server console run `rongroi doctor`. Every line should say `ok`.

Any resource on the game server can read a `set` convar with `GetConvar`; run only resources you trust.

## API

Connect-facing (no key): `GET /<id>/policy/<ticket>`, `POST /<id>/report` (one request, up to 2 MiB, headers
`X-Rongroi-Upload-Id`, `X-Rongroi-Report-Sha256`, `X-Rongroi-Envelope: 2`), `GET /<id>/status/<ticket>/<sha256>`.

Server-facing (`Authorization: Bearer <key>`): `POST /v1/tickets`, `GET /v1/tickets/<ticket>/envelopes`,
`POST /v1/tickets/<ticket>/envelopes/<sha256>/result`, `DELETE /v1/tickets/<ticket>`, `GET /v1/health`.

Status codes follow aeterna-rongroi ADR 0089 §4. Limits: tickets live at most an hour; 120 public requests per address
per minute; results are kept 10 minutes past a ticket's expiry so Connect can read them.

## Tests

`npm test` runs the relay's own tests and an end-to-end test with the real Server Kit modules.
