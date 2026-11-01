# `fivem-devkit safety` — code-safety scanner

FiveM has no sandbox. A server-side Lua or JS resource can do anything the FXServer process can:
make outbound HTTP requests, read every convar (including the rcon password and the database
connection string), run console commands as the server (including `add_ace` / `add_principal`),
write files into other resources, and run code it downloads. Installing a resource is handing its
author the server.

`fivem-devkit safety` is the automated gate in front of that. It runs:

- on every pull request to this repository (blocking),
- in downstream projects that vendor our releases, before each bump,
- by anyone, on any resource folder: `fivem-devkit safety path/to/resources`.

```sh
fivem-devkit safety                         # every resource under config "roots"
fivem-devkit safety resources/[local]       # a resource, or a folder of resources ([category] folders work)
fivem-devkit safety --format json …         # machine-readable; --format github for PR annotations
```

Exit code 1 when there is at least one error. Warnings never fail the run.

## Threat model

### What it catches

| Attack | Rules |
|---|---|
| Download-and-run backdoor (`PerformHttpRequest` + `load(body)()`) | `dynamic-load`, `undeclared-http` |
| Hiding the above from a reviewer: `_G['lo' .. 'ad']`, `local l = load`, `pcall(load, x)`, byte-escaped names, `string.char(...)` lists, base64 blobs, code off-screen on a 5000-char line | `dynamic-load`, `env-tamper`, `obfuscation` |
| Server takeover through the console: `add_ace`, `add_principal`, `exec`, `set`, `ensure`, a command name built at runtime, `;` injection | `ace-command`, `command-injection` |
| Credential theft: `rcon_password`, `sv_licenseKey`, `steam_webApiKey`, `mysql_connection_string`, `*token*`, `*secret*`, `*password*`, `*apikey*`, `*webhook*`; environment variables | `secret-convar`, `host-access` |
| Running host commands or touching host files: `os.execute`, `io.popen`, `io.open(…, 'w')`, `child_process`, `vm`, `fs` | `host-exec`, `host-access` |
| Calling a native by hash to dodge name-based rules (`Citizen.InvokeNative`, `_in`) on the server | `invoke-native` |
| Shipping what nobody can review: DLLs, archives, Lua bytecode, minified bundles, streamed assets | `opaque-file` |
| Quietly widening what a package does: new HTTP destinations, HTTP handlers, commands, net events, convars, tables, file writes, NUI | `undeclared-*`, `over-declared`, `capabilityDiff` |
| Exploit surface: net events with no rate limit; player text rendered as HTML in NUI | `net-event-rate-limit`, `nui-html-injection` |

### What it can NOT catch — human review stays required

The scanner proves that code only uses the capabilities it declares. It cannot judge whether the
code uses them honestly.

- **Logic bombs inside allowed APIs.** A package with `db.tables: ["players"]` can delete every
  player row on a date. A package allowed to call `https://api.example.com/` can send it anything.
- **Abuse through other resources' exports.** `exports.some_admin_resource:giveAdmin(src)` is a
  normal export call; the scanner does not know what other resources expose.
- **Trusting the client.** A server net event that gives items to whoever asks is declared, rate
  limited and still an exploit. Argument validation is a review item.
- **Data-dependent behaviour.** A URL, command or convar name assembled from data at runtime is
  reported as "built at runtime" — it is not traced. Values passed through function parameters,
  table fields or other files (beyond literal `Config.x = '…'` constants) are not followed.
- **Native calls by name the scanner does not list**, client-side natives called by hash, and any
  capability FiveM adds after this scanner was written.
- **TypeScript/JSX/Vue/Svelte sources.** Reported as `unscanned`. Scan their build output, built in
  CI from reviewed source.
- **Code that is not in the scanned folder**: `node_modules/` (skipped), other resources,
  `@other_resource/file.lua` manifest imports.

A green scan means "nothing automated objects", not "safe". Every PR still gets a human review,
and every `oss.json` change gets a review from the owner of capabilities.

## How it reads code

- **Lua** is read with a purpose-built CfxLua lexer (`src/safety/lualex.js`): short strings with
  every escape, long brackets at any level, nested comments, backtick hashes, `<const>`/`<close>`,
  compound assignment and `?.`. Rules match token sequences, so text in comments and strings never
  looks like code, and code can never hide inside something mistaken for a comment. A light
  analysis on top (`luascan.js`) tracks block scopes (a local named `load` is not the global),
  local aliases (`local o = os; o.execute` is `os.execute`), member chains with literal keys
  (`exports['ox' .. 'mysql']:query`), `pcall(F, …)`, string concatenation and `:format()`, and
  constants assigned once — including `Config.x = '…'` and `Config = { x = '…' }` from another file
  of the same resource.
- **JS** is parsed with acorn (latest ECMAScript, module first, script as fallback) and walked
  with acorn-walk. `window.x`, `globalThis.x`, `require('m').x`, imports and destructuring are
  resolved. Inline `<script>` blocks in `.html` files are scanned as NUI code.
- **Which side a file runs on** comes from `fxmanifest.lua` (`client_scripts`, `server_scripts`,
  `shared_scripts`, globs included). Shared files count as both sides. A Lua file in no list is
  treated as both (it might be loaded some other way). JS/HTML in no list is NUI.
- `node_modules/` and `.git/` are skipped. **`dist/` is scanned on purpose**: committed build output
  is where a payload would hide.

## Rules

Every finding has `check: "safety/<rule-id>"`. Errors fail the run; warnings do not.

### Hard deny

| Rule | Severity | Catches | Why |
|---|---|---|---|
| `dynamic-load` | error | Lua `load`, `loadstring`, `dofile`, `loadfile`, `package.loadlib` — any reference, not only calls; JS `require(<runtime value>)`, `import(<runtime value>)`, imports from `http(s)://`; `<script src="https://…">` in NUI HTML | Nearly every FiveM backdoor in the wild is `PerformHttpRequest` + `load(body)()`. Code fetched at runtime was never reviewed. |
| `host-exec` | error | `os.execute`, `io.popen`, `os.remove`, `os.rename`, `os.exit`, `os.tmpname`, `io.open` with a write/append/`+` mode or a runtime mode, `io.output(file)`, the `os`/`io` table escaping as a value; JS `child_process`, `vm`, `worker_threads`, `process.binding`/`dlopen`/`exit`/`kill` | Runs commands or changes files on the machine hosting the server — outside anything a capability can describe. |
| `host-access` | error | `os.getenv`; JS `fs`, `net`, `dgram`, `tls`, `cluster`, `module`, `inspector`, `v8`, `process.env` | `fs` writes bypass `SaveResourceFile` + `files.write`; raw sockets bypass `http`; environment variables are where hosts keep database passwords and API keys. |
| `code-eval` | error | JS `eval`, `Function` / `new Function`, `x.constructor(...)`, `setTimeout`/`setInterval` with a string | The JS equivalent of `load`. |
| `env-tamper` | error | `debug.*`, `getfenv`, `setfenv`, `string.dump`, `_G`/`_ENV` used as a value (`rawget(_G, …)`, `local g = _G`), `_G[<computed>]`, `_G[<anything but one string literal>]`, `local _ENV`; JS `globalThis[x]` / `window[x]` | These reach any global by a computed name, which defeats every name-based rule. `debug.*` rewrites other code's locals and upvalues. Literal access (`_G.Config`, `_G['Config']`) is fine and is checked like a plain reference. |
| `invoke-native` | error | `Citizen.InvokeNative`, `_in` in server/shared/unlisted files | Natives called by hash skip every capability check (`ExecuteCommand`, `GetConvar` and `SaveResourceFile` all have hashes). Client files are exempt: client code reaches undocumented game natives this way and cannot touch the server. |
| `secret-convar` | error, **not allowlistable** | `GetConvar*` of `rcon_password`, `sv_licenseKey`, `steam_webApiKey`, `mysql_connection_string`, or any name matching `/(token\|secret\|password\|apikey\|api_key\|webhook)/i` — also through aliases, `pcall`, concatenation and constants | Whoever receives these owns the server. |
| `ace-command` | error, **not allowlistable** | `ExecuteCommand` whose command (first word of each `;`/newline-separated command) is `add_ace`, `add_principal`, `remove_ace`, `remove_principal`, `exec`, `set`, `sets`, `setr`, `seta`, `rcon`, `quit`, `restart`, `stop`, `start`, `ensure`, `refresh`, …, or that contains `add_ace`/`add_principal`/`remove_*`/`rcon` anywhere; on the server, a command whose name is built at runtime; `ExecuteCommand` escaping as a value | `ExecuteCommand` runs as the server console, which holds every permission. |
| `command-injection` | error | Server-side `ExecuteCommand` with a literal command name but runtime arguments | The console splits on `;`: `'say ' .. msg` with `msg = "hi; add_ace …"` runs a second command. Validate the value and allow the file with a reason, or avoid `ExecuteCommand`. |
| `obfuscation` | error | A run of ≥ 8 consecutive `\xNN` / `\ddd` / `\u{…}` escapes in one string; a base64-looking literal ≥ 200 chars; `string.char`/`utf8.char`/`String.fromCharCode` with ≥ 8 numeric arguments, `unpack(...)`, a spread or `.apply`; a table of ≥ 32 numbers in a file that calls `string.char`; any line > 1000 chars in `.lua`/`.js` | Obfuscation exists to get code past a reviewer. Honest code can always spell its strings out. |
| `opaque-file` | error | `.dll .exe .so .dylib .zip .rar .7z .jar .luac .bin .node .wasm .gz .tar .tgz`; Lua bytecode under any name; binary content in a source file; `*.min.js` or JS with average line length > 300; streamed assets `.ycd .ytd .yft .ydr .ydd .ybn .ymap .ytyp .rpf` unless `safety.allowAssets` | A reviewer can only approve what they can read. Bundles are built in CI from reviewed source. Minified files are not scanned further. |

**Why exactly two rules cannot be allowlisted.** `secret-convar` and `ace-command` are the two
capabilities that hand *someone else's* server to the code's author: one leaks the keys, the other
grants permissions or swaps the code that runs. Every other rule protects against something a
server owner can reason about and accept for a specific file. These two have no safe exception: a
package that needs a credential reads it from its own convar whose name does not look like a
secret (`mypkg_endpoint`), set by the owner, so the owner decides what it gets; a package that needs
a console command declares a specific one in `commands`. The engine refuses `safety.allow` entries
for them (`invalid-allow`).

### Must declare (checked against `oss.json`)

| Rule | Code | Must appear in |
|---|---|---|
| `missing-manifest` | no `oss.json` next to `fxmanifest.lua`, or an invalid one | — |
| `undeclared-http` | `PerformHttpRequest`, `fetch`, `http(s).request/get`, `axios*`, `node-fetch`, `undici`, `WebSocket`, `EventSource`, `navigator.sendBeacon`, remote `ui_page`/`loadscreen`; `XMLHttpRequest` and `PerformHttpRequestInternal*` are always reported (destination not checkable) | `capabilities.http` (URL prefix) |
| `undeclared-http-handler` | `SetHttpHandler` (any call, Lua or JS) | `capabilities.httpHandlers` (non-empty) |
| `undeclared-command` | `ExecuteCommand` (each command's first word) | `capabilities.commands` |
| `undeclared-registered-command` | `RegisterCommand`, `lib.addCommand` (string or list) | `capabilities.registeredCommands` |
| `undeclared-convar` | `GetConvar`, `GetConvarInt`, `GetConvarBool`, `GetConvarFloat` / `SetConvar`, `SetConvarReplicated`, `SetConvarServerInfo` | `capabilities.convars.read` / `.write` |
| `undeclared-net-event` | `RegisterNetEvent`, `RegisterServerEvent`, `onNet`, `lib.callback.register` | `capabilities.netEvents.server` (server files) / `.client` (client files); shared and unlisted files need both |
| `undeclared-nui` | `ui_page`, `SetNuiFocus*`, `RegisterNUICallback`, `RegisterNuiCallbackType`, `SendNUIMessage`, `__cfx_nui:` handlers | `capabilities.nui: true` |
| `undeclared-file-write` | `SaveResourceFile` — and writing into any resource but `GetCurrentResourceName()` is always an error | `capabilities.files.write` |
| `undeclared-db` | table names after `FROM`/`INTO`/`UPDATE`/`JOIN`/`TABLE` in SQL string literals of server-side code and `.sql` files (best effort; CTE names, `ON DUPLICATE KEY UPDATE`, `FROM JSON_TABLE(…)` excluded); `CREATE`/`ALTER`/`DROP`/`TRUNCATE`/`RENAME`; SQL with a table appended at runtime is a warning | `capabilities.db.tables`, `capabilities.db.ddl: true` |

Values must be literal or resolvable: a string literal, concatenation of literals, `('…%s'):format()`
with the variable parts treated as unknown, an identifier or `Config.x` assigned exactly once from a
literal (in the same file, or for `Config.x`-style dotted keys anywhere in the resource). A name or
URL built from anything else is reported as "built at runtime" / "dynamic URL". Referencing one of
these APIs as a value (`local t = { send = PerformHttpRequest }`) is reported because its uses
cannot be checked; plain aliases (`local P = PerformHttpRequest`) are followed instead.

**NUI callbacks are not HTTP.** `fetch('https://' + GetParentResourceName() + '/close')`,
`fetch('https://<this resource>/cb')` and relative URLs (`./data.json`) are local. A browser-dev
fallback such as `inGame ? GetParentResourceName() : 'dev'` is accepted only when the fallback
cannot be a host (no `.`, `:` or `/`, not `localhost`).

### Quality rules that are security rules

| Rule | Severity | Catches | Why |
|---|---|---|---|
| `net-event-rate-limit` | warn | A server-side handler (`RegisterNetEvent`/`RegisterServerEvent`/`onNet`/`lib.callback.register` with a handler, or `AddEventHandler`/`on` for an event registered as a net event in the resource) whose body calls nothing matching `safety.rateLimitFns` | Any client can fire a net event thousands of times a second. Matching is by call path: exact, a member of it, or a method with that name (`exports.lib:rateLimit` matches `rateLimit`). Named handlers (`RegisterNetEvent('x', onX)`) are resolved within the file. |
| `nui-html-injection` | error | `innerHTML`/`outerHTML` assigned anything but a static string; `insertAdjacentHTML`, `document.write(ln)`, jQuery `$(…).html(x)` with a non-literal | NUI is Chromium with access to the resource's NUI callbacks; player text rendered as HTML runs script in every viewer's client. Use `textContent`. |
| `over-declared` | warn | A capability in `oss.json` the code never uses | A manifest that over-declares lets a later change start using the capability without the capability diff showing anything. |

### Meta

| Rule | Severity | Meaning |
|---|---|---|
| `parse-error` | error | A Lua file failed to lex or a JS file failed to parse. Lua that fails to lex also fails to load. |
| `invalid-allow` | error | A `safety.allow` entry is malformed, has no reason, names an unknown rule, uses a catch-all path, or targets `secret-convar`/`ace-command`. Rejected entries are not applied. |
| `no-resources` | error | No `fxmanifest.lua` under a scanned path. A scan of nothing is not a pass. |
| `unscanned` | warn | `.ts .tsx .mts .cts .jsx .vue .svelte` files were not analysed. |

## Configuration

`.fivem-devkit.json` at the project root:

```json
{
  "roots": ["resources"],
  "safety": {
    "requireManifest": true,
    "allowAssets": false,
    "rateLimitFns": ["NakaraCore.rateLimit", "lib.callback", "rateLimit"],
    "allow": {
      "dynamic-load": [
        { "path": "resources/my_pkg/server/catalog.lua", "reason": "loads catalog.lua shipped in this resource into an empty env" }
      ],
      "opaque-file": [
        { "path": "resources/**/web/dist/**", "reason": "built in CI from web/src at the attested release commit" }
      ]
    }
  }
}
```

| Key | Default | Meaning |
|---|---|---|
| `requireManifest` | `true` | `true`: a resource without `oss.json` gets `missing-manifest` and every capability use is reported. `false`: resources without `oss.json` are scanned for hard-deny and quality rules only — use this to scan third-party resources. |
| `allowAssets` | `false` | Accept streamed GTA assets. |
| `rateLimitFns` | `["NakaraCore.rateLimit", "lib.callback", "rateLimit"]` | Calls that count as a rate limit in a server net-event handler. |
| `allow` | `{}` | Per-rule exceptions: `{ "<rule-id>": [{ "path": "<glob or prefix>", "reason": "<why>" }] }`. `path` is matched against the file path relative to the project root **or** to the resource directory; `**` crosses directories, `*` does not, a path without `*`/`?` is a file or directory prefix. Every entry needs a reason. Catch-alls (`*`, `**`, `.`) are rejected. `secret-convar` and `ace-command` cannot be allowlisted. |

## Writing `oss.json`

Every package ships `oss.json` next to `fxmanifest.lua` (schema: `oss.schema.json` at the repo
root). It is the package's permission list, shown to server owners in the README and diffed on every
release.

```json
{
  "$schema": "../../oss.schema.json",
  "name": "metrics",
  "resource": "nakara_metrics",
  "capabilities": {
    "http": ["127.0.0.1:${netPort}/perf/"],
    "commands": [],
    "registeredCommands": ["perf"],
    "convars": { "read": ["nakara_metrics_*", "netPort"], "write": [] },
    "netEvents": { "server": ["nakara_metrics:fpsWindow"], "client": [] },
    "nui": false,
    "db": { "tables": ["perf_tick", "perf_fps"], "ddl": true },
    "files": { "write": [] }
  }
}
```

- **`http`** — URL prefixes; the scheme is optional and ignored. An entry that is only a host
  (`api.example.com`) matches that host exactly, not `api.example.com.evil.invalid`. `${name}`
  placeholders match the value of `GetConvar('name', …)` used in the same expression, or literal
  text without `.`, `/`, `:` (a port, a path segment). In the host position a placeholder never
  matches a hard-coded host or an arbitrary variable — build the URL from the convar itself:
  `'https://' .. GetConvar('mypkg_api_host', '') .. '/v1/'`. In a port or path position it also
  accepts any runtime value.
- **`commands`, `registeredCommands`, `convars.*`, `netEvents.*`, `db.tables`, `files.write`** —
  exact names, or globs with `*` (`nakara_metrics_*`, `nakara_metrics:*`).
- **`httpHandlers`** — paths under `/<resource>/` answered by `SetHttpHandler`; a trailing `*`
  matches a prefix. Optional. The scanner sees only that a handler exists, so any `SetHttpHandler`
  makes every declared entry used; entries with no `SetHttpHandler` in the package are
  `over-declared`.
- **`nui`**, **`db.ddl`** — booleans.
- Declare exactly what the code uses: unused entries are `over-declared` warnings.

Widening any list (or turning a boolean on) is a capability change. CI calls
`capabilityDiff(oldJson, newJson)` (exported from `src/safety/capabilities.js` and re-exported by
`src/safety/index.js`) and labels the PR when `added` is non-empty:

```js
import { capabilityDiff } from './packages/devkit/src/safety/capabilities.js';
capabilityDiff(before, after); // oss.json objects, their JSON text, or null for a new package
// → { added: ['http: api.example.com/', 'nui: true (was false)'], removed: ['commands: refresh_cache'] }
```

## For server owners: running it on what you install

1. Run the scanner on every release you install, not on the repository's `main`:
   ```sh
   fivem-devkit safety path/to/resources/[oss]
   ```
   Errors mean the release does something it did not declare, or something no release should do.
2. Read each package's `oss.json` before installing. Ask: does a HUD need `http`? Does a fishing
   script need `db.tables: ["users"]`?
3. On every update, diff the manifests (`capabilityDiff`) and look hard at anything in `added`.
4. Scanning third-party resources that have no `oss.json`: set `"safety": { "requireManifest": false }`
   to get the hard-deny and quality findings without one capability error per call.
5. If a release ships built NUI (`dist/`), it will show as `opaque-file`. Allow it only if you trust
   the build (attested CI release), with a reason.
6. The scanner is one layer. Keep reviewing diffs; it cannot see logic bombs inside capabilities a
   package legitimately has.
