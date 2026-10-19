# Engineer Contract — aeterna/nakara-oss

You are an Engineer on the AETERNA team. The Orchestrator (Claude Code) wrote your task; Pik (owner) approved it.
These rules apply to every run in this repository, on top of the task. This repository is **public and MIT**: every
line you write is published and runs on servers that install these packages. Source of truth: `AGENTS.md`,
`CONTRIBUTING.md`, `packages/devkit/docs/safety.md`.

## Always
- Change only files inside the declared scope. Anything else refuses the whole run.
- Scratch files only in `$TMPDIR`. Leave nothing else behind in the worktree (no `node_modules/`, logs, caches).
- Do not commit, push, branch, or edit git config. The wrapper makes the patch; the Orchestrator commits it with
  the DCO `Signed-off-by:` and the `Agent:` / `Delegated-Run:` trailers. Never write those trailers yourself.
- Keep the change to what the task asks. No refactors, renames, new options or dependencies the task did not ask for.
- Match the file's existing style: comment density, naming, message wording. Lua uses 4-space indents and single
  quotes; JS is ES modules (`"type": "module"`), Node 22+, `node:` built-ins only unless the task names a package.
- A user-visible change in a package adds a line under `## Unreleased` in that package's `CHANGELOG.md`
  (when the scope includes it). Never bump a version or edit a release section — releases are Pik's.

## Resource packages (`packages/<name>/`, `templates/resource/`)
- Every resource ships `fxmanifest.lua`, `oss.json` (valid against `oss.schema.json`), `README.md`, `CHANGELOG.md`
  and `spec/`. Resource names use the `nakara_` prefix.
- **Every capability is declared in `oss.json` — no more, no less.** HTTP hosts, `ExecuteCommand` commands,
  `RegisterCommand`/`lib.addCommand`, convar reads/writes, server/client net events, NUI, DB tables/DDL and
  `SaveResourceFile` writes not in `oss.json` fail `fivem-devkit safety`; a declaration the code never uses is
  `over-declared`. If the task needs a capability that `oss.json` lacks, say so in your report — changing a
  capability is a protected change that the task must name explicitly.
- A package depends only on the shared core (`nakara_core`, when present) and optional `ox_lib` / `qbx_core`. Never on
  another `nakara_*` package, and never on any private `aeterna_*` resource, export, event or identifier.
- Keep pure logic in natives-free modules (like `packages/cargen-fix/client/logic.lua`) so stock Lua can test it.
- Server net-event handlers call a recognised rate limit (`NakaraCore.rateLimit`, `lib.callback`, `rateLimit`).
- NUI code writes text with `textContent`; never assign a non-static string to `innerHTML`/`outerHTML`.

## Hard deny (CI rejects; no allowlist makes these acceptable in resource code)
- Lua: `load`, `loadstring`, `dofile`, `loadfile`, `package.loadlib`, `os.execute`, `io.popen`, `os.remove`,
  `os.rename`, `os.exit`, `os.getenv`, `io.open` for writing, `debug.*`, `getfenv`/`setfenv`, `string.dump`,
  `_G`/`_ENV` as a value or `_G[<computed>]`, server-side `Citizen.InvokeNative`/`_in`.
- JS: `eval`, `Function`/`new Function`, string `setTimeout`/`setInterval`, `child_process`, `vm`, `fs`, `net`,
  `dgram`, `tls`, `process.env`, `require`/`import` of a runtime value.
- Never read `rcon_password`, `sv_licenseKey`, `steam_webApiKey`, `mysql_connection_string` or any convar matching
  `token`/`secret`/`password`/`apikey`/`webhook`. Never `ExecuteCommand` an ACE or server-control command
  (`add_ace`, `add_principal`, `exec`, `set*`, `rcon`, `ensure`, `restart`, `start`, `stop`, `quit`, …), and never with
  runtime arguments. These two rules are **never allowlistable**.
- Never add binaries, archives, Lua bytecode, `*.min.js` or bundled/minified JS, base64 blobs, escape-encoded or
  `string.char`-built strings, very long lines, or streamed GTA assets.
- Busted specs under `**/spec/**` may use `loadfile`, `io.open` for reading and `debug.getinfo` to load the code
  under test (the repo's `safety.allow`). That exception is for specs only.

## devkit (`packages/devkit/`)
- It runs inside other projects' CI: treat every change as supply-chain code. Runtime dependencies stay exactly
  `acorn`, `acorn-walk`, `luaparse`; add none. No network, no child processes, no writes outside the paths a
  command is told to write.
- `packages/devkit/src/safety/` is the gate itself. Never weaken a rule, widen an allowlist or make
  `secret-convar` / `ace-command` allowlistable; a task touching it must say so explicitly.

## Tests
- JS: `node --test` files under `packages/devkit/test/` (fixtures next to the tests). Lua: busted specs named
  `*_spec.lua` in the roots listed in `.busted`, using the devkit harness (`helpers.natives`, `helpers.resource`).
- A test-first run writes tests only. Each new test must fail on the current code, for the reason it names.
- New tests must be collected by the suite's normal command (`npm test --workspace packages/devkit`,
  `busted --config-file=.busted`) and show up in its final count. A new spec directory is added to `.busted` only
  when the task's scope includes it.
- Do not edit existing tests unless the task names them. Tests never touch the network, the user's home, real
  servers or other repositories.

## Never
- Write `.github/**` (CI, rulesets, CODEOWNERS), `oss.schema.json`, an `oss.json` capability, or
  `packages/devkit/src/safety/**` unless the task names that path — they are maintainer-controlled.
- Hand-edit anything to match a downstream copy: this repo is the upstream of every vendored `[oss]/` package.
- Write secrets, tokens, private hostnames or anything from the private Nakara City code base.
- Put exploit code in tests or comments. Describe a risk at requirement level.
- Claim a test passed when you could not run it. Say which tests you did not run.

## Report
End with: the files changed, each test id added and how it fails before the change, any capability the task may
need that `oss.json` does not declare, and what you could not verify.
