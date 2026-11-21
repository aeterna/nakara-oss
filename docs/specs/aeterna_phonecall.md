# aeterna_phonecall

- Package: `packages/phonecall` · resource `aeterna_phonecall` · version 0.1.0 · wave W2 of Starter Kit 0.2 · status spec
- Depends on: `aeterna_core` (validation, rate limit, ACE, locale, keys, self-tests), `aeterna_uikit` (panel
  spec format), `aeterna_phonekit` (App API, contacts, ring screen); `pma-voice` optional, detected at run time —
  [ADR 0005](../adr/0005-starter-kit-0-2.md) decisions 2, 3, 4 and 6

## Purpose and limits

Phone numbers, text messages and voice calls as two apps inside the phone: **Phone** (dialer, recent calls, in-call
screen) and **Messages** (threads and compose). Both are drawn through phonekit's App API; this package ships no phone
shell of its own.

- Numbers and messages are server data the player must not edit, so they live in **server-side resource KVP** of this
  resource, keyed by character (ADR 0005 decision 3). No database tables (`db.ddl = false`).
- Calls need `pma-voice`. When it is not started, messages and numbers still work, the dialer shows "Calls are not
  available on this server", and the call self-tests report SKIP. `pma-voice` is never in `dependencies`.

Not in 0.1: group calls, voicemail, pictures in messages, calling services by short code, call recording, a phone
book of other players, message search.

## Install

```cfg
ensure aeterna_core
ensure aeterna_uikit
ensure aeterna_notify
ensure aeterna_phonekit
ensure pma-voice           # optional, for calls
ensure aeterna_phonecall
add_ace group.admin aeterna.phonecall.admin allow
```

## Configuration

`config.lua` (shipped):

| Key | Default | Meaning |
| --- | --- | --- |
| `Config.number.format` | `'555-####'` | `#` = a random digit, any other character is literal. At least 4 `#`; at most 20 characters |
| `Config.number.reserved` | `{ '555-0000', '555-0911' }` | Never assigned |
| `Config.number.assign` | `'first_open'` | `first_open`: a character gets a number the first time it opens either app · `on_load`: when the character loads |
| `Config.sms.maxLen` | `160` | Visible characters (`AeternaCore.text.len`), 1–300 |
| `Config.sms.keep` | `100` | Messages kept per character, incoming and outgoing together; the oldest leave first. 10–100 |
| `Config.call.ringSeconds` | `30` | Ringing without an answer becomes `missed` |
| `Config.call.maxMinutes` | `60` | An active call ends with reason `limit` |
| `Config.call.channelBase` | `20000` | First `pma-voice` call channel this package uses; it uses `channelBase + 1` … `channelBase + 9999` |
| `Config.recentCalls` | `30` | Call log entries kept per character |

## Identity

- **Character key** = `cid:<citizenid>` from `qbx_core` when it is started, otherwise `lic:<license identifier>`
  (`GetPlayerIdentifierByType(src, 'license')`). Read on the server only; the client never sends it.
- With `qbx_core`, a character switch (qbx logout / load) drops the player's in-memory session (open screens, the
  names map, any call, which ends with reason `dropped`) and starts a new one for the new character.

## Phone numbers

- A number is drawn by replacing each `#` with a random digit, skipping reserved numbers and numbers already taken,
  up to 50 tries. Fifty failures log one `error` ("number pool exhausted") and the app shows `phonecall.number.none`.
- Uniqueness and lookup use two KVP keys per number (§ Storage). Numbers compare by their digits only, so `5550142`
  and `555-0142` are the same number.
- A number stays with its character for good. Admins change it with `aeterna_phonecall_setnumber`; the old number is
  freed at once.
- The number is shown in both apps' headers and is available to other resources through `getNumber`.

## Messages

- Send from Messages (compose screen or a thread) or from a contact in phonekit's Contacts app (§ Contacts).
- `body` is cleaned with `AeternaCore.text.clean(body, Config.sms.maxLen)`; an empty body is refused. Control
  characters (including newlines) are removed, so a message is one line.
- Delivery: the server writes one copy into the sender's list and one into the recipient's list, whether the recipient
  is online or not. An unknown number returns `phonecall.sms.unknown` to the sender and stores nothing.
- Each list keeps the last `Config.sms.keep` messages. Message record:
  `{ id: string ≤ 12, peer: string ≤ 20 (digits), dir: 'in'|'out', body: string, ts: integer, read: boolean }`.
- Online recipient: phonekit `notifyApp(src, 'messages', { title = <contact name or number>, body = <first 60> })`
  and the badge goes up. On load the badge is set to the unread count.
- Limits per sender: 1 message / 2000 ms and 15 / 60 s; per sender → recipient pair, 6 / 60 s. A refused send shows
  `phonecall.sms.slow`.
- Threads: grouped by `peer`, newest first, at most 50 threads listed; a thread shows its last 50 messages. Opening a
  thread marks its messages read.

## Calls

Calls exist only while `GetResourceState('pma-voice') == 'started'`, checked when a call is placed and on
`onResourceStart` / `onResourceStop` of `pma-voice`. If `pma-voice` stops during a call, the call ends with reason
`voice_off`.

### States

| State | Caller sees | Callee sees | Leaves to |
| --- | --- | --- | --- |
| `dialing` | "Calling …" with a hang-up button | — (the callee is `ringing`) | `active`, `ended` |
| `ringing` | — | Incoming call: caller's contact name or number, answer and decline (§ Ring) | `active`, `ended` |
| `active` | In-call screen: peer, timer, hang-up | Same | `ended` |
| `ended` | Reason line for 3 s, then the Phone app home | Same | — |

`busy` is not a state of the call: a call to a player who is already `dialing`, `ringing` or `active` ends at once with
reason `busy`. End reasons: `hangup`, `declined`, `missed`, `busy`, `unavailable` (number unknown or not online, the
callee's phone cannot call, or the callee is the caller), `dropped` (a player left or switched character), `limit`,
`voice_off`.

### Voice (`pma-voice` exports used)

Server exports only, so the server decides who is in a call:

| Moment | Call |
| --- | --- |
| Call becomes `active` | `exports['pma-voice']:setPlayerCall(src, channel)` for both players, `channel = Config.call.channelBase + n` with `n` the lowest free slot |
| Call ends from `active` | `exports['pma-voice']:setPlayerCall(src, 0)` for each player still connected; the channel is freed |

No other `pma-voice` export is used. The export name and arguments are checked against the `pma-voice` version the
README lists as tested; **behaviour on FXServer Enhanced is not verified yet** (the W0 spike on the kit-test server).

### Ring

The callee's phone shows the incoming call through phonekit 0.2's ring screen (§ Uses from aeterna_phonekit 0.2): on the cover
screen when a fold model is closed, on the lock screen when locked, as a full incoming card when the phone is open,
and as a toast with answer and decline hints when the phone is put away. Answer and decline also work through the key
mappings below, so a player can answer without opening the phone.

## Contacts

phonekit's Contacts app stays the only contact list (client KVP of `aeterna_phonekit`). This package:

- reads it through phonekit's client export, and sends the server a names map
  `{ [digits] = name }` when either app opens and when phonekit reports a change; the server keeps it in memory for
  that player's session only and uses it to label threads, recents and the callee's ring screen;
- registers itself as the handler for "Call" and "Message" on a contact, so those buttons in Contacts open the dialer
  or a thread with that number;
- offers "Save contact" on an unknown number, which calls phonekit's client export to add it.

## Uses from aeterna_phonekit 0.2

All through phonekit's exports and local events (a hard edge), as named in
[aeterna_phonekit § Hooks for add-ons](aeterna_phonekit.md#hooks-for-add-ons) and § Battery. If that spec renames one,
it wins and this section follows it.

| # | Use | phonekit contract |
| --- | --- | --- |
| N1 | Read contacts | client export `getContacts()`; client-local event `aeterna_phonekit:contactsChanged` |
| N2 | Save a contact | client export `addContact({ name, number })` |
| N3 | Call / Message from Contacts | `addTile` field `handles = { 'tel' }` (Phone) and `{ 'sms' }` (Messages); `aeterna_phonekit:app` carries `intent = { kind, number }` |
| N4 | Incoming call | server exports `ring(src, 'phone', { title, body })` → `ringId` and `stopRing(src, ringId)`; Answer / Decline arrive as `aeterna_phonekit:action` with `action = '__answer'` / `'__decline'` and `screenId = ringId`. A `ring` error (`dead`, `nodevice`, `noapp`, `novoice`, `busy`) ends the call `unavailable` (or `busy`) |
| N5 | Can this phone call | server export `canCall(src)`, checked for both players before dialing and before ringing |
| — | Hide Phone on models without calls | `addTile` field `needs = 'voice'` on the Phone tile (Messages stays) |
| — | Status bar pill | server export `live(src, { id = 'call', text = <timer> })` while `active`, `live(src, nil)` on end |
| — | Battery drain while connected | server export `activity(src, 'call', true)` on `active`, `false` on end |
| — | Dead battery or device lost | server-local `aeterna_phonekit:power` → `(src, { on = false })` ends the player's call with reason `dropped` |

The ring card ends by itself after 60 s on phonekit's side; this package calls `stopRing` first, at
`Config.call.ringSeconds`, so the call ends `missed`.

## Exports (server)

| Export | Returns | Notes |
| --- | --- | --- |
| `getNumber(src)` | string or nil | The current character's number (assigns one when `Config.number.assign = 'on_load'`) |
| `findByNumber(number)` | src or nil | Online player holding that number |
| `sendSms(fromLabel, toNumber, body)` | `true` or `false, err` | Message from a service (a bank, a job). `fromLabel` ≤ 24, shown with a service mark and no reply box. Counts against a limit of 30 / 60 s per calling resource |
| `endCall(src, reason?)` | boolean | Ends the player's call; `reason` defaults to `hangup` |
| `callState(src)` | `{ state, peerNumber, since }` or nil | |

Server-local events for other resources (no functions cross resources):

| Event | Payload |
| --- | --- |
| `aeterna_phonecall:sms` | `(fromNumber or fromLabel, toNumber, { id, ts })` — the body is not included |
| `aeterna_phonecall:call` | `(callId, state, { from = number, to = number, reason? })` |

## Events (network)

Taps and form submissions inside both apps arrive through phonekit's `aeterna_phonekit:action` (already validated and
rate limited by phonekit against the spec on screen). This package adds only:

| Event | Direction | Schema | Rate limit |
| --- | --- | --- | --- |
| `aeterna_phonecall:sv:names` | client → server | `{ names: table ≤ 100 keys, key = digits ≤ 20, value = string ≤ 40 }` | 1 / 5000 ms |
| `aeterna_phonecall:sv:answer` | client → server | none | 2 / 1000 ms |
| `aeterna_phonecall:sv:hangup` | client → server | none | 2 / 1000 ms |
| `aeterna_phonecall:cl:state` | server → client | `{ callId: string ≤ 12, state: enum, peer: string ≤ 40, reason?: enum }` | — |
| `aeterna_phonecall:cl:askNames` | server → client | none | — |

Inside `aeterna_phonekit:action` handlers this package applies its own limits on top: dial 1 / 3000 ms and 10 / 60 s;
send message as in § Messages. Every value is re-validated with these schemas:

```lua
dial = { type = 'table', fields = { number = { type = 'string', maxLen = 20, pattern = '^[%d%-%s%+%(%)]+$' } } }
send = { type = 'table', fields = {
  number = { type = 'string', maxLen = 20, pattern = '^[%d%-%s%+%(%)]+$' },
  body   = { type = 'string', maxLen = 300 } } }   -- then cut to Config.sms.maxLen visible characters
```

`cl:state` lets the client run the key mappings and hold the phone to the ear during `active`; it does not draw any
screen (phonekit does).

## NUI messages

None. This package has no `ui_page`; every screen is a phonekit panel spec.

## Commands and keys

Permanent names:

- `+aeterna_phonecall_answer` / `-aeterna_phonecall_answer` — answer a ringing call (key mapping, no default key)
- `+aeterna_phonecall_hangup` / `-aeterna_phonecall_hangup` — decline a ringing call or end the current call (key
  mapping, no default key)
- `aeterna_phonecall_number <serverId>` — console or ACE `aeterna.phonecall.admin`: prints that player's number
- `aeterna_phonecall_setnumber <serverId> <number>` — console or ACE `aeterna.phonecall.admin`: sets the number if it
  matches `Config.number.format` and is free; the player's open screens refresh

## Storage

Server-side resource KVP of `aeterna_phonecall` (`SetResourceKvp` / `GetResourceKvpString` on the server), values in
JSON:

| Key | Value |
| --- | --- |
| `aeterna_phonecall:number:v1:<who>` | `{ number }` |
| `aeterna_phonecall:owner:v1:<digits>` | `<who>` (number → holder index; keyed by number, not by player) |
| `aeterna_phonecall:sms:v1:<who>` | array of message records, ≤ `Config.sms.keep` |
| `aeterna_phonecall:calls:v1:<who>` | array of `{ peer, dir, result, ts, seconds }`, ≤ `Config.recentCalls` |

`<who>` is the character key: `cid:<character id>` or `lic:<license identifier>` (specs README § Names, server
resource KVP keys).

Nothing in client KVP. Message bodies stay on the server and are sent only to their two parties. The largest value
(100 messages of 160 Thai characters) is about 60 KB of JSON; **the server KVP value limit is not measured yet** (W0
spike). If a write fails, the oldest messages are dropped until it fits and one `warn` is logged.

## Locale keys

`phonecall.app.phone`, `phonecall.app.messages`, `phonecall.key.answer`, `phonecall.key.hangup`,
`phonecall.number.mine`, `phonecall.number.none`, `phonecall.dial.title`, `phonecall.dial.call`,
`phonecall.recent.title`, `phonecall.recent.empty`, `phonecall.call.dialing`, `phonecall.call.incoming`,
`phonecall.call.active`, `phonecall.call.answer`, `phonecall.call.decline`, `phonecall.call.hangup`,
`phonecall.call.unavailable_server`, `phonecall.end.hangup`, `phonecall.end.declined`, `phonecall.end.missed`,
`phonecall.end.busy`, `phonecall.end.unavailable`, `phonecall.end.dropped`, `phonecall.end.limit`,
`phonecall.end.voice_off`, `phonecall.sms.title`, `phonecall.sms.compose`, `phonecall.sms.send`,
`phonecall.sms.empty`, `phonecall.sms.unknown`, `phonecall.sms.slow`, `phonecall.sms.service`,
`phonecall.contact.save`, `phonecall.admin.usage`, `phonecall.admin.taken`, `phonecall.admin.format`.

## `oss.json` capabilities

```json
{ "http": [], "commands": [],
  "registeredCommands": ["+aeterna_phonecall_answer", "-aeterna_phonecall_answer", "+aeterna_phonecall_hangup",
                         "-aeterna_phonecall_hangup", "aeterna_phonecall_number", "aeterna_phonecall_setnumber"],
  "convars": { "read": [], "write": [] },
  "netEvents": { "server": ["aeterna_phonecall:sv:names", "aeterna_phonecall:sv:answer",
                            "aeterna_phonecall:sv:hangup"],
                 "client": ["aeterna_phonecall:cl:state", "aeterna_phonecall:cl:askNames"] },
  "nui": false, "db": { "tables": [], "ddl": false }, "files": { "write": [] } }
```

No HTTP hosts, no convars, no `SaveResourceFile`. `nui` is `false`: there is no page and no `SetNuiFocus` call;
focus stays with phonekit. The `pma-voice` and `qbx_core` exports are reached only after `GetResourceState` says they
are started.

## Tests

busted (pure logic in `shared/logic/`):

1. Number format: `555-####` makes `555-` + 4 digits; reserved and taken numbers skipped; fewer than 4 `#` refused at
   start; 50 failures → nil; digits-only comparison.
2. Message store: cap at `Config.sms.keep` drops the oldest; both copies written; unknown number stores nothing;
   empty and over-long bodies; control characters removed.
3. Threads: grouping, order, 50-thread and 50-message caps, mark-read.
4. Rate limits: 1 / 2 s, 15 / 60 s, pair 6 / 60 s, `sendSms` 30 / 60 s per resource.
5. Call state machine: dialing → ringing → active → ended for each end reason; a call to a busy player ends `busy`;
   self-call ends `unavailable`; ring timeout ends `missed`; channel slots allocated lowest-free and released.
6. Voice gate: with `pma-voice` not started, dial ends `unavailable` with `phonecall.call.unavailable_server` and no
   `setPlayerCall` call is made (fake exports table).
7. Names map: over 100 keys or long values refused; labels fall back to the number.

Smoke (kit-test server, two clients A and B):

1. First open assigns a number; reconnect keeps it; `aeterna_phonecall_setnumber` changes it and frees the old one.
2. A texts B (online and offline); B's badge and toast; threads and read state survive a reconnect.
3. With `pma-voice`: A calls B, B answers from the fold cover screen, both hear each other at a distance, A hangs up.
   B declines; B does not answer (missed); A calls B while B is in a call (busy).
4. Stop `pma-voice` during a call: it ends `voice_off`; the dialer shows the unavailable line.
5. Save an unknown number as a contact; the thread shows the name; Call from Contacts opens the dialer.
6. Screenshots of dialer, in-call, incoming, threads in all three presets for the owner's visual gate.

## Self-tests (0.2)

| name | kind | players | destructive | expect (eye) | skip-when |
| --- | --- | --- | --- | --- | --- |
| `aeterna_phonecall.number_format` | headless | 1 | n | — | — |
| `aeterna_phonecall.number_unique` | mock | 1 | n | — | — |
| `aeterna_phonecall.sms_store_cap` | mock | 1 | n | — | — |
| `aeterna_phonecall.sms_rate_limit` | headless | 1 | n | — | — |
| `aeterna_phonecall.voice_detect` | headless | 1 | n | — | — |
| `aeterna_phonecall.my_number` | eye | 1 | n | Open the Phone app: your number is shown in the header in the server's format | — |
| `aeterna_phonecall.sms_ab` | eye | 2 | y | B's phone shows a toast "Self-test" from A's number (or A's contact name) and the Messages tile gets a badge of 1 | — |
| `aeterna_phonecall.call_ab` | eye | 2 | n | B sees an incoming call from A (on the cover screen if B holds a closed fold); after B answers, both see a running timer and can hear each other; after A hangs up both see "Call ended" | `pma-voice` not started |
| `aeterna_phonecall.call_busy` | ped | 2 | n | — | `pma-voice` not started |

Mock tests use the fake keys `test:a` and `test:b` in place of `<who>`, and delete every KVP key they wrote before they report,
so the result is MOCK with the state restored. `sms_ab` writes one real message into A's and B's stored lists (body "Self-test"),
so it is destructive (ADR 0005 decision 7) and reports SKIP while `aeterna_core_allow_destructive` is closed. Two-player tests report GAP when
no second player is on the server.

## Done when

All busted cases pass, `fivem-devkit safety` reports 0 errors and 0 over-declared items, `check-kit-graph` accepts the
edges and the runtime-detected `pma-voice`, the phonekit 0.2 contracts in § Uses from aeterna_phonekit 0.2 exist under those names, the smoke
steps pass on the kit-test server, the self-tests report PASS, SKIP or MOCK, and the owner has passed the screenshots.
