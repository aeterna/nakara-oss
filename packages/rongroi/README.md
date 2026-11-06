# nakara_rongroi

The Rongroi Server Kit. Lane 2b so far: envelope crypto, tickets, the HTTP handler, storage, retention, and
the staff/settings panel wiring. **The NUI screens are placeholders and the gate has no behaviour yet.** See
[ADR 0001](../../docs/adr/0001-rongroi-server-kit.md) for the layout. The protocol is aeterna-rongroi ADR 0089,
sections 4 and 5. `api(1)` has `openCase`, `getCase`, `listCases`, `deleteCase`, `deletePlayerData` and
`getPairingCode`.

## Envelope v1

`server/js/envelope.js` (Node `crypto` only, CommonJS) implements the envelope of aeterna-rongroi ADR 0089,
section 5:

- `generateKeyPair()`: X25519 key pair as raw 32-byte base64url values.
- `sealEnvelope(plaintext, kitPublic, ticket)`: encrypts to the Kit's public key. Used by tests and the vector
  generator; the optional fourth argument fixes the ephemeral key and iv for the vectors only.
- `openEnvelope(envelopeJson, kitPrivate, kitPublic, ticket)`: returns the UTF-8 plaintext or throws an
  `EnvelopeError` with `code` `malformed` or `not_authentic`.
- `deriveKey` and `agree` are the primitives the vectors check.

Wire form: `{ "v": 1, "epk": …, "iv": …, "ct": … }`, base64url without padding. `epk` is 32 bytes, `iv` is 12
bytes, and `ct` is the AES-256-GCM ciphertext followed by the 16-byte tag. The key is HKDF-SHA256 with salt =
the ticket as 32 lowercase hex ASCII bytes and info = `rongroi-connect report v1` || Kit public key || `epk`.
The AES-GCM additional data is the ticket string.

## Test vectors

`test-vectors/envelope-v1.json` holds fixed inputs (a Kit key pair, an ephemeral key, an iv, a ticket and a
plaintext) and the expected values. **Connect tests against the same file.** The keys in it are test keys only
and are not used by any Server Kit.

## Self-test

When the resource starts, `server/js/selftest.js` checks the vectors once and prints exactly one line:

```
nakara_rongroi selftest: ok x25519 hkdf aes-gcm
nakara_rongroi selftest: fail <step> <message>
```

The steps are `x25519`, `hkdf`, `aes-gcm` and `vectors` (the vector file could not be read). The line never
contains key material.

## HTTP

`server/js/http.js` answers under `/nakara_rongroi/`, on both editions:

- `GET policy/<ticket>`: the case policy with its `policy_hash`.
- `POST report`: one envelope of at most 7,168 bytes.
- `POST report/chunk`: 4,096-byte slices, for larger envelopes up to 2 MiB.

Every POST needs `Content-Length`. Headers and status codes are ADR 0089 section 4. A report that cannot be saved
answers `500` and leaves the ticket unused, so the upload can start again. Per address, policy reads and requests
naming an unknown or expired ticket are limited to 30 a minute; slices to 600 a minute per ticket. Enhanced closes
the connection on a body past its 8 KiB limit before the handler sees it.

**HTTP is plain.** The envelope hides the report, but the path, the ticket and the size are visible on the network.

## Storage

Legacy stores in resource KVP. Enhanced stores in `cache/rongroi-reports/`, because a small KVP write there blocks
a tick for about 30 ms against about 8 ms for a small file (ADR 0001 section 4). The edition comes from the
`gamename` convar. Key pair and settings stay in KVP on both.

**Keep `cache/rongroi-reports/` when you update this resource.** Replacing the folder removes the stored reports
on Enhanced. On that edition a deleted case leaves empty files named by a random ticket or a hash, with no player
data in them, since no FiveM call deletes a file. KVP deletes are real deletes.

## Retention

A sweep at start and every hour removes cases older than the setting in KVP `rongroi:settings:retentionDays`:
1 to 365 days, default 30. A case's age counts from its report, or from when it was opened if none arrived. The
sweep removes one case every 250 ms.

## Commands, net events and API

`/rongroi` opens the staff panel for a holder of the `nakara_rongroi.staff` ACE and asks for the player's own
pairing code otherwise. The checks, the panel logic and its per-kind rate limits live in
`server/js/panel.js`; `server/js/main.js` wires it up and adds a coarse per-source guard.

Client to server net events (ADR 0001 section 10):

- `nakara_rongroi:requestCode` — the player's own open case.
- `nakara_rongroi:panel:open`, `nakara_rongroi:panel:case`, `nakara_rongroi:panel:openCase` — staff.
- `nakara_rongroi:settings:save`, `nakara_rongroi:exception:set` — staff.
- `nakara_rongroi:case:delete`, `nakara_rongroi:player:delete` — staff.

Server to client events: `nakara_rongroi:showCode`, `nakara_rongroi:panel:data` and
`nakara_rongroi:settings:data`, sent only to the player or staff member the handler checked.

`api(1)` adds `getCase`, `listCases`, `deleteCase`, `deletePlayerData` and `getPairingCode`. It never returns the
private key or an envelope.

## Capabilities

From [`oss.json`](oss.json): SetHttpHandler paths `policy/*`, `report` and `report/chunk`; the convar read
`gamename`; file writes in `cache/rongroi-reports/*`; the `rongroi` command the resource registers; the server
and client net events above; and NUI. No outgoing HTTP, no `ExecuteCommand`, no database. The root
`.fivem-devkit.json` carries a scanner exception for `server/js/filestore.js`, whose file names are built at
runtime and checked before use (ADR 0001 section 4).

## Tests

`npm test` inside `packages/rongroi/` runs the specs in `spec/` with `node --test`. The repository's `npm test`
and CI run them too.
