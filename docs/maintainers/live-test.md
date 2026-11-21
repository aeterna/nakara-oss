# Live test loop — edit, reload and test a resource on a real FXServer (maintainers)

Unit specs run on plain Node or plain Lua. They cannot tell you how FXServer resolves `require()`, which
globals exist in server JS, or what type an export expects. Run every resource on a real FXServer before a
release, and use the loop below to fix what it finds without restarting the server or kicking the tester.

Written after the Nakara Tickets W3 test (2026-11-20). That run found six bugs that every spec had passed.

## What the loop needs

| Piece | Why | Notes |
|---|---|---|
| A clean test FXServer in a container, private (`sv_master1 ""`), its own port | a server you may restart, unrelated to any live city | `--restart no`; the same framework versions as the target server |
| The resource under test copied into it, plus any backend it talks to on the same Docker network | the resource reaches the backend by container name (`http://<container>:8080`) | no public port for the backend |
| A console you can type into | pairing and reload commands must come from the server console (`source == 0`) | see "Console" below |
| A small test-only diagnostics resource | to ask the running server what exists and what it returns | never in the repo or a release zip |
| A tester in game, and you watching the logs | the person presses buttons; you read the server and backend logs live | the tester gets a button menu, not typed commands |

## The loop

1. **Find the failure in the live logs**, not in the dashboard. Read the FXServer log since the test step
   (`docker logs --since 2m <server>`) and the backend log. Filter out the licence key before printing.
2. **Measure, do not guess.** Before you write a fix, prove the cause on the running server with the
   diagnostics resource (below). One probe, one fact: "this global is undefined", "this export returns
   `[false, "invalid_inventory"]` for a string id".
3. **Fix with a test that fails first.** The test emulates the FXServer behaviour you just measured (for
   example, delete `globalThis.GetPlayers` and stub `getPlayers`). Run it against the old code and see it
   fail, then against the fix. Run `fivem-devkit safety` and `check`; both must stay at 0.
4. **Copy only the resource files** into the test server (keep its test `config.json`), then reload the one
   resource from the console: `stop <resource>` and then `start <resource>`. Do not restart the server: the
   tester stays in game. `restart <resource>` did not reload on FXServer Enhanced in our run; `stop` + `start`
   did.
5. **Wait for `Started resource <name>`** in the log, then have the tester (or the dashboard) repeat the
   step. Record each step's result with its time.

## Console

The container has no stdin, and a command in `server.cfg` runs before resources start, so a resource's
own command does not exist yet at that point ("Command not found"). Use a temporary rcon:

- Write a random `rcon_password` into a separate cfg (`exec rcon.cfg` at the end of `server.cfg`) without
  printing it. Keep the password in a file readable only by you.
- Send commands as a UDP packet `\xff\xff\xff\xffrcon <password> <command>` from a container on the same
  Docker network (a ten-line Node `dgram` script). Do not publish rcon on a host port beyond the test port.
- Remove the `exec rcon.cfg` line and the file when the test ends.

## Diagnostics resource

A throwaway resource (JS + Lua) with console-only commands (`RegisterCommand(name, fn, true)`) that print
facts, never values that identify a person:

- which globals exist in server JS: `typeof globalThis.<name> === 'function'` for every native the resource
  calls (extract the list with `grep -ohE '\b[A-Z][A-Za-z0-9]+\(' server/js/*.js`). Names that are methods
  of `exports.<resource>` will show as missing; that is expected.
- player counts from each API, and identifier **types** only (`license`, `discord`, …), not identifier values
- the raw return of an export call, including its JavaScript type (`Array.isArray`)

## FXServer server JS: facts measured on Enhanced

| Fact | Consequence |
|---|---|
| A relative `require('./x.js')` resolves from the **resource root**, not from the requiring file | use a literal fallback: try `'./x.js'`, on `MODULE_NOT_FOUND` load `'./server/js/x.js'` (`packages/rongroi/server/js/pairing.js`). A computed path (`path.join`, `GetResourcePath`) fails `safety/dynamic-load` |
| `GetPlayers()` and `GetPlayerIdentifiers()` are Lua helpers and are **undefined** in JS | JS has `getPlayers()` (lowercase) or `GetNumPlayerIndices` + `GetPlayerFromIndex`, and `GetNumPlayerIdentifiers` + `GetPlayerIdentifier` |
| Player ids from the player list are **strings** | Lua exports (`ox_inventory`, `qbx_medical`, `qbx_core`) look players up by **number**; pass `Number(id)`. `AddItem('1', …)` returns `[false, "invalid_inventory"]` |
| A Lua export that returns several values arrives in JS as an **array** | normalise: `const ok = Array.isArray(r) ? r[0] : r` |
| A command handler is called as `(source, args, rawCommand)` | never give the handler a third parameter with another meaning; wrap it |
| Every `fetch` that sends a request body logs `Uncaught TypeError: Invalid state: Reader released` (string, `Buffer`, `Uint8Array`, `Blob`, stream with `duplex: 'half'`, `new Request()`, `keepalive` all do; `GET` and a `POST` with no body do not). Measured 2026-11-21 on Node v26.3.0 inside FXServer | the response still arrives and is read normally; the line is console noise from the runtime, not the resource. Do not chase it in resource code; to tell it apart from a real failure, check that the request's result arrived |

## Before you call the resource tested

- every step the tester ran has a result line with its time, and the failing ones have a cause and a fix
  commit
- the fix commits carry their failing-first tests, and `safety` and `check` are at 0
- rcon is removed, the diagnostics resource is deleted, and the test server is stopped or reset
