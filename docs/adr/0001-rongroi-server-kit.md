# ADR 0001 — Rongroi Server Kit (`nakara_rongroi`)

- Status: accepted — owner, 2026-11-01 (every owner question answered as recommended)
- Date: 2026-11-01
- Related: aeterna-rongroi ADR 0089, "Rongroi product line and schema 2" (not merged yet:
  [aeterna/aeterna-rongroi#252](https://github.com/aeterna/aeterna-rongroi/pull/252)); aeterna-rongroi
  ADR 0090 (proposed, the collector behind `defender` rules); this repo's `AGENTS.md` hard rules 3 to 5,
  `oss.schema.json`, `packages/devkit/docs/safety.md`
- Written by: Claude Code - Claude Opus 5.5

## Context

ADR 0089 splits Rongroi into three products. The third, the Server Kit, is a FiveM resource in this repo. It
mints a pairing ticket when staff open a case, serves the case policy, receives an encrypted report over
HTTP, and shows it to staff in game. ADR 0089 owns the protocol: ticket states and lifetime, the
`X-Rongroi-*` headers on both `POST report` and `POST report/chunk`, the 7,168-byte direct limit and 4 KiB
slices, the 60 s idle reassembly TTL, up to 2 open uploads per ticket, the envelope and its key derivation,
the pairing code, the policy fetch, `policy_hash`, `visual_hash`, the shared status-code table and the
`declined` answer. This ADR references those and does not restate them. It decides only what the Kit does.

What PoC Spike W1a measured on Legacy (master 35245) and Enhanced (early-access b170), 2026-10-31:

- **S1.** Enhanced drops any HTTP body of 8,193 bytes or more (curl error 52). Legacy took 1 MiB.
- **S3.** Node's `crypto` and `zlib` load in both editions. Parsing or deflating 1 MiB stalls a tick by at
  most 7.5 ms. X25519, HKDF and AES-GCM themselves were not called.
- **S5.** A 1 MiB resource KVP write takes 17–27 ms on Legacy and 192–222 ms on Enhanced. Small values were
  not measured.
- **S4** (latent event) was tested on the server half only. **S2** (NUI file picker) and **S6** (deferrals
  card) did not run.

Two limits of this repo matter here. `fivem-devkit safety` rejects JS `fs`, so files are written only with
`SaveResourceFile` inside the resource's folder, and no native deletes a file. And `oss.schema.json` has no
entry for `SetHttpHandler`, which the scanner does not detect today.

The product rules hold for every screen and API below: no verdict, no "verified" or "clean" badge, no
auto-ban, nothing vouches for a program, a file or a PC. ADR 0089 section 1 names the only two facts the Kit
may show: the server received this report after it opened this case, and the `visual_hash` the server
recomputes equals the value in the record. Staff may compare that value with what the player reports from
the screen, but a player who controls Connect can show or choose any value, and 64 bits is sized for people
comparing, not for collision resistance. The uploader is not identified: anyone holding the code can upload.

### Owner decisions (Pik, 2026-10-28)

Lives in nakara-oss · resource `nakara_rongroi` · npm validator ships in W4 · add `httpHandlers` to
`oss.schema.json` · UI customisable at 4 levels · framework auto-detect is the default · settings panel in
game only · gate only on machine requirements (posture), never on cheat traces · a new gate runs in shadow
mode for 7 days · privacy template, retention setting, delete on request (each server is the data
controller) · Lua API `api(1)` plus events · plug-ins are rule packs, data only · WASM later.

### Kit proposals (accepted by the owner, 2026-11-01)

Per-player exceptions · the upload page for saved reports, chunked like Connect · every change to a gate's
rule list reruns 7 days of shadow mode · the framework list Qbox, QBCore, ESX, standalone · the reading of
the 4 UI levels in section 11 · every default number in this ADR.

## Decision

### 1. Resource layout: Lua for the game, JS for bytes and crypto

```
packages/rongroi/
  fxmanifest.lua  oss.json  README.md  CHANGELOG.md  PRIVACY-TEMPLATE.md
  server/*.lua      framework bridge, staff permission, cases, gate, settings, Lua API, events
  server/js/*.js    HTTP handler, ticket store, reassembly, decrypt, validator, report storage
  client/*.lua      pairing code display, staff panel, settings panel (NUI)
  web/ui/  web/upload/  rulepacks/*.json  sql/install.sql  spec/
```

Everything that touches report bytes runs in server JS: the HTTP handler, tickets, reassembly, SHA-256 checks,
decryption, the validator and `visual_hash` recomputation. Lua never holds a decrypted body. Lua owns staff,
cases, the gate, settings and the API. The halves talk through resource-local events and exports. Reasons:
Node's `crypto` is present in both editions (S3), Lua has no X25519 or AES-GCM, and one runtime avoids
copying up to 2 MiB across the Lua and JS boundary.

### 2. Probe first (W2 exit gate)

Before other code, a probe resource on both editions runs the shared ADR 0089 test-vector file (produced in
lane 2b) through `crypto.generateKeyPairSync('x25519')`, `crypto.diffieHellman`, `crypto.hkdfSync` and
`aes-256-gcm`, times a 1 MiB `SaveResourceFile` write and a 200-byte KVP write and read, and settles how to
detect the edition. **Unverified until then.** W2 does not exit until all pass on both editions. A missing
call sends the protocol back to the owner; the Kit never falls back to a weaker cipher. If a small KVP write
on Enhanced costs a visible hitch, section 4's index design is revisited before any storage code.

### 3. Key pair and tickets

- At first start the Kit creates one X25519 key pair in JS and stores the private key in KVP
  `rongroi:key:v1` on both editions (32 bytes, written once). It is never logged, sent to a client, shown in
  a panel or returned by the API. Staff can rotate it from the settings panel; rotation invalidates open
  tickets only, since stored reports are kept decrypted.
- Issued and uploading tickets live in a JS `Map`; a restart drops them and staff open a new case. Ticket
  state changes follow ADR 0089 exactly. A consumed ticket is kept with its case, so after a restart a
  reuse still gets `409`, and a repeat of the accepted envelope still gets `200`.
- Expiry uses the server's clock only.

### 4. Storage per edition

| What | Legacy | Enhanced |
|---|---|---|
| Case (metadata, state, facts) | one KVP key `rongroi:case:<id>` | same |
| Case index | KVP pages `rongroi:index:<n>`, 100 ids each | same (pending the W2 probe) |
| Report body (decrypted record) | KVP `rongroi:report:<id>` | file `cache/rongroi-reports/<ticket>.json`, or oxmysql if started |
| Settings, exceptions, gate log | small KVP keys | same |

- ADR 0089 names `server-data/cache/rongroi-reports/`. The Kit cannot write there under this repo's rules, so
  the folder is `<resource>/cache/rongroi-reports/`, declared as `files.write: ["cache/rongroi-reports/*"]`.
  The same change is proposed for ADR 0089.
- The panel can override the detected backend with `kvp`, `file` or `oxmysql`. oxmysql is used only when it
  is started, with table `nakara_rongroi_reports`; `sql/install.sql` makes `db.ddl` true.
- Only the validated record is stored, never the envelope.

### 5. Retention and deletion

- `PRIVACY-TEMPLATE.md` is filled in by the server: what is collected, why, how long, how to ask for deletion.
- Retention is a setting in days, default 30, range 1 to 365. A sweep runs at start and hourly.
- Staff delete one case, or every case and gate-log entry of one identifier, from the panel or the API.
- On the file backend, deletion overwrites the file with an empty one and drops it from the index. The
  zero-byte file is named by a random ticket and holds no player data. The README tells servers this and
  that KVP and oxmysql deletes are real deletes.

### 6. HTTP endpoints, limits and abuse

One `SetHttpHandler` in server JS answers under `/nakara_rongroi/`. Anyone who reaches the port can call it.

| Endpoint | Purpose |
|---|---|
| `GET policy/<ticket>` | case policy (ADR 0089) |
| `POST report`, `POST report/chunk` | Connect upload and the upload page (ADR 0089) |
| `GET upload`, `GET upload/<file>` | upload page, fixed file list, only when enabled (section 12) |

Status codes are ADR 0089's shared table; `429` carries `Retry-After`. Kit decisions:

- The largest envelope is 2 MiB, so `X-Rongroi-Chunk-Total` is at most 512. Slices arrive in order; the last
  index may repeat with the same `Chunk-Sha256` (a retry).
- A started upload is bounded by the 60 s idle TTL of ADR 0089, not by the 300 s ticket lifetime: an upload
  that keeps sending slices may run past `expires_at`.
- At most 16 open uploads in total (2 per ticket by ADR 0089), so reassembly holds at most 32 MiB. The 17th
  first slice gets `429`.
- Per source address, 30 per minute, counted only for policy GETs and for requests naming an unknown or
  expired ticket. Slices of a valid open upload are limited per ticket instead: 600 per minute.
- The body is read only after method, path, ticket state and declared size pass. **Unverified:** whether
  FXServer lets JS refuse before the body arrives; if not, Enhanced's 8 KiB cap bounds it and Legacy's does
  not.
- **Unverified:** what `req.address` holds when players connect through the Cfx proxy. A server that hides
  its IP behind the proxy cannot use v1, which needs Connect to reach `server_origin` over plain HTTP. The
  panel has a "public origin" setting (`scheme://host:port`) that goes into the pairing code; it is required
  before a case can be opened.
- A refused request is logged on the case when the ticket is known, otherwise as a counter. Nothing a client
  sends is written to the console verbatim.

### 7. The `httpHandlers` capability (its own PR, before the Kit)

`oss.schema.json` gets one optional property under `capabilities`, beside `registeredCommands`:

```json
"httpHandlers": { "type": "array", "items": { "type": "string" },
  "description": "paths under /<resource>/ that SetHttpHandler answers; a trailing * matches a prefix" }
```

Optional, so no existing `oss.json` changes. The scanner gains `undeclared-http-handler` (any `SetHttpHandler`
in a package whose list is empty or missing) and reports unused entries as `over-declared`. The Kit declares
`["policy/*", "report", "report/chunk", "upload", "upload/*"]`. Widening the list needs owner review: a
handler takes bytes from anyone on the network with no player session, and the scanner sees that a handler
exists, not what it does with the body. Schema, scanner rule and tests are maintainer-owned (hard rule 7).

### 8. What staff see

- A fixed line on every case: "This shows what was uploaded with this case's code. Whoever uploads controls
  that PC and can change the report. It does not show that the PC is clean."
- Facts: who opened the case and when, the ticket state, when the upload arrived, the uploader's address and
  the player's connect address as two separate facts (never compared), the policy and collector list, and the
  findings as `Found`, `NotFound` or `Unmeasured` with reasons.
- Self-asserted fields are labelled "the report says": `official_build`, `producer`, `rongroi_version`,
  `issued_at`, `expires_at`.
- `visual_hash` is shown large, with the fact whether the server's recomputation equals the record's value.
  A mismatch is a fact, never a verdict.
- A declined answer (ADR 0089) gives the case state "declined", shown as a fact.
- No score, no colour for the case as a whole, no "verified" or "clean" state, no ban button. The NUI sets
  every report field with `textContent`.

### 9. Gate on machine requirements

- A gate is a list of rules with `strength: posture`. The Kit learns a rule's strength from the record's
  view if the view carries it, otherwise from the rule data bundled with the Kit for that `rongroi_version`.
  **Unverified** which of the two applies; settled in lane 2b. The panel refuses any other rule, and the
  validator refuses a rule pack that puts one in a gate.
- Rules tagged `defender` are warning-only even with the gate on, until a rongroi release carries ADR 0090's
  collector (owner question Q21). A validator test covers it.
- At connect, deferrals show the pairing code and wait (S6 has not run; **unverified**). A requirement is
  unmet only when its rule is `Found`. `Unmeasured` is shown and does not refuse.
- Outputs are only `refused`, `would_refuse` (shadow) and `not_refused`, never "passed" or "ok". A declined
  answer is its own result, `declined`, and staff settings decide whether it refuses. A report from a saved
  file (section 12) never satisfies a gate.
- A new gate runs in shadow mode for 7 days and staff switch it on by hand. Per-player exceptions carry who,
  why and an optional end date (Kit proposal).
- The README says a gate can be bypassed by forging a report or by declining. Refusal at deferrals for an
  unmet requirement is the only block the Kit makes.

### 10. Public Lua API, events and net events

`exports.nakara_rongroi:api(1)` returns a table; `api(1)` keeps working for at least one major version.
Functions: `openCase`, `getCase`, `listCases`, `deleteCase`, `deletePlayerData`, `getPairingCode`,
`addException`, `removeException`, `listExceptions`, `getGateStatus`. Resource-local server events:
`nakara_rongroi:caseOpened`, `:reportReceived`, `:caseDeclined`, `:caseExpired`, `:caseDeleted`,
`:gateResult` (with `shadow`). Nothing returns the private key or the envelope, and no field is a verdict.

Net events for `oss.json`. Every server handler calls a rate-limit helper and checks the ACE first, except
the player's own pairing-code request, which checks that the player has an open case:

| Direction | Event | Check |
|---|---|---|
| client → server | `nakara_rongroi:requestCode` | player has an open case |
| client → server | `nakara_rongroi:panel:open`, `:panel:case`, `:panel:openCase` | staff ACE |
| client → server | `nakara_rongroi:settings:save`, `:exception:set` | staff ACE |
| client → server | `nakara_rongroi:case:delete`, `:player:delete` | staff ACE |
| server → client | `nakara_rongroi:showCode`, `:panel:data`, `:settings:data` | sent to the checked player only |

The validator caps JSON depth at 32, any string at 8 KiB and any array at 10,000 items before it builds
anything from a record.

### 11. Settings, frameworks and UI

- Settings live in the in-game panel and KVP. The Kit reads no convar.
- Staff permission is the ACE `nakara_rongroi.staff` via `IsPlayerAceAllowed`.
- External resources the Kit may touch, each only when `GetResourceState` says it is started: `qbx_core`,
  `qb-core`, `es_extended` (names and identifiers), `ox_lib` (callbacks, rate limit), `oxmysql` (storage).
  The owner extended hard rule 5 for them on 2026-11-01: `qb-core` and `es_extended` are read only (names and
  identifiers), `oxmysql` is used for this Kit's own storage, and none of the three is a dependency in
  `fxmanifest.lua`.
- The 4 UI levels (accepted): (1) texts and language, (2) CSS variables, (3) a server's own NUI page on a
  documented message format, (4) no Kit UI, the server's own on `api(1)`.

### 12. Saved-file upload page

Off by default and enabled per server in the panel, until the Kit can be reached over HTTPS. Over plain HTTP
the page's own code has no integrity: an attacker on the path can inject script and read the saved report
before it is encrypted. The page says so at the top in plain words.

When enabled, staff open a case and give its code; the page fetches the policy, encrypts the file in the
ADR 0089 envelope and uploads through `report` or `report/chunk`. Plain HTTP is not a secure context, so
`crypto.subtle` is unavailable (browser behaviour, not tested here); the page carries unminified X25519, HKDF
and AES-GCM code in `web/upload/vendor/`, pinned by version and hash. **Unverified:** that the safety scanner
accepts those files.

The Kit accepts schema 1 or 2 on this path and does no binding or nonce check. The case is labelled "uploaded
from a saved file", never satisfies a gate, and no screen says "scan" or "live" about it. The Connect path
requires schema 2 with a binding.

### 13. Out of scope

Hub and any hosted service · WASM plug-ins · exe or DLL plug-ins · auto-ban, ban buttons, or any action on a
cheat-trace finding · any score or verdict · HTTPS through `users.cfx.re` · persistent Connect mode.

## Consequences

- Every server that installs the Kit gains one unauthenticated HTTP surface. Section 6 bounds memory and
  rates, but anyone who can reach the port can use them.
- Anyone holding the code can upload, and a player can forge or decline. A gate raises the cost of entry
  without a matching machine; it does not prove one.
- File reports on Enhanced are emptied, not removed, until FiveM offers a delete call or the server uses
  oxmysql.
- The private key in KVP can be read by anyone with access to the server's files: the server's own boundary.
- Servers behind the Cfx proxy cannot use v1.
- KVP use is not a declared capability in `oss.schema.json`; this ADR does not add one.

## Order of work

Lane 2b, core (W2 to W3):

1. Probe on both editions with the shared test vectors; W2 exit gate (section 2).
2. `httpHandlers` in the schema and `undeclared-http-handler` in the scanner (section 7).
3. Key pair and ticket store with ADR 0089's states (section 3).
4. Envelope decrypt and `visual_hash` recomputation against the test vectors.
5. Direct and chunked receive with section 6's limits.
6. Storage per edition, index pages, retention and deletion (sections 4 and 5).
7. Schema-2 validator with section 10's caps, the same source the npm validator publishes in W4.

Lane 3b, screens (W3 to W4):

1. In-game pairing code for a case, and the public-origin setting.
2. Staff case view with `visual_hash`, the fixed line and no verdict (section 8).
3. In-game settings panel (section 11).
4. Case policy editor with ADR 0089's profiles.
5. Machine-requirement gate: `strength: posture`, `defender` warning-only, 7-day shadow, exceptions.
6. Saved-file upload page, off by default, with chunking (section 12).
7. Deferrals flow, after S6 runs on both editions.
