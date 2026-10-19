# O-03 · T13 · golden tasks for nakara-oss

**Repo:** nakara-oss · **Branch:** `feat/o-03-golden` · **Route:** opencode:A → claude:A · **Gate:** G1 Pik 2026-10-19 (Phase 2 go) · D5 · Q0 ✅ Claude Sonnet helper (agy/opencode quota; 5 majors folded in)

## Goal (requirements only)
`aeterna-delegate qualify -E <engine>` measures an engine on `<repo>/.aeterna/golden/<id>/`: `task.md` is the prompt,
the engine may change only `fixture/`, then `meta.toml`'s `check` (with `timeout`) runs from the task directory in a
no-network sandbox, with `check/` and `meta.toml` taken from base. A check passes only when it exits 0 **and prints the
value of `AETERNA_GOLDEN_NONCE`**, which it must print only after the fixture's code ran — in a child process started
**without** that variable — and every expectation held. Add two tasks that look like this repo's real work.
1. `.aeterna/golden/lua-rate-limit/`: a natives-free Lua module in `fixture/` (shaped like
   `packages/cargen-fix/client/logic.lua`: `local L = {} … return L`) in which the engine implements a per-source
   sliding-window rate limit for server net events: allow at most `max` calls per source within `windowMs` of the
   caller-supplied clock; separate sources are independent; state lives in a table the caller passes, never in
   globals. Rules to state in `task.md`: an earlier allowed call at time `t` counts while `now - t < windowMs`; a
   rejected call does not count; `max` must be a positive integer and `windowMs` a positive number, otherwise the
   function raises an error; the caller's clock never goes backwards. `task.md` states the exact name and signature.
2. `.aeterna/golden/oss-undeclared/`: an ES module in `fixture/` (Node 22, `node:` built-ins only) in which the
   engine implements `undeclaredNetEvents(used, manifest)` in `fixture/undeclared.mjs`: `used` is an array of
   `{ name, side }` with `side` = `'server'` or `'client'`, `manifest` is a parsed `oss.json` object; return the sorted, de-duplicated names not declared in `capabilities.netEvents[side]`; a manifest whose
   `capabilities.netEvents.server` or `.client` is missing or not an array of strings throws a `TypeError`.
   `task.md` states the exact export, signature and rules.
3. Each `fixture/` ships only a stub (function present; the Lua one returns `nil`, the JS one throws "not
   implemented") so the check **fails on base**. Never include a working implementation anywhere.
4. Each check: run from the task directory; no nonce in the environment ⇒ exit 2 with a hint; otherwise start a child
   with the nonce removed from its environment (e.g. a `bash` parent using `env -u`, or a `node` parent passing an
   env without it) that loads the fixture and checks ≥ 6 expectations (incl. the edge cases above); the parent never
   loads the fixture itself. Print the nonce last, and only when the child's output is exactly its success line and
   it ran every expectation. A fixture that exits 0, errors, or prints nothing while loaded is never a pass. Lua runs
   with stock `lua` (5.4); JS with `node` (child loads the fixture with `import()` of a file URL). Each check opens
   with a comment explaining this parent/child design and why the nonce never reaches fixture code.
5. `meta.toml`: a one-line comment, `check = "<cmd>"`, `timeout = 60`. `task.md` ends with
   "Only edit files under `fixture/`. Do not touch `check/`."
6. Nothing outside `.aeterna/golden/` changes; the repo's CI and devkit scans must not pick these files up.

## Acceptance (the Orchestrator runs these)
- **(g1)** each check, from its task dir, without `AETERNA_GOLDEN_NONCE` ⇒ exit 2, nonce not printed.
- **(g2)** with a nonce, on the stub fixture ⇒ exit ≠ 0, nonce not printed.
- **(g3)** with a nonce, fixture replaced by one that only `os.exit(0)` / `process.exit(0)` at load, or one whose
  function is correct for the first expectation only ⇒ exit ≠ 0, nonce not printed.
- **(g3b)** Q4: the Orchestrator reads every fixture — stub only, no working code.
- **(g4)** `qualify -E claude` passes both (baseline), proving a correct fixture can pass.
- **(g5)** Q2 (devkit tests, check, safety, busted) unchanged on the result: same counts, no file under `.aeterna/`
  in any scan output.

## Scope
`.aeterna/golden/**`

## Out of scope
`.aeterna/checks.toml` · `.aeterna/engineer.md` · `.github/**` · devkit · packages · org-standards.

Shell (if your engine has one): only `lua`, `node`, `bash`, `env`, `ls`, `cat`. Scratch in `$TMPDIR` only. No git, mktemp or installs.
