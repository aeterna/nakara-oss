# O-03 · T13 · golden tasks for nakara-oss

**Repo:** nakara-oss · **Branch:** `feat/o-03-golden` · **Route:** opencode:A → claude:A · **Gate:** G1 Pik 2026-10-19 (Phase 2 go) · D5

## Goal (requirements only)
`aeterna-delegate qualify -E <engine>` measures an engine on `<repo>/.aeterna/golden/<id>/`: `task.md` is the prompt,
the engine may change only `fixture/`, then `meta.toml`'s `check` (with `timeout`) runs from the task directory in a
no-network sandbox, with `check/` and `meta.toml` taken from base. A check passes only when it exits 0 **and prints the
value of `AETERNA_GOLDEN_NONCE`**, which it must print only after the fixture's code ran — in a child process started
**without** that variable — and every expectation held. Add two tasks that look like this repo's real work.
1. `.aeterna/golden/lua-rate-limit/`: a natives-free Lua module in `fixture/` (shaped like
   `packages/cargen-fix/client/logic.lua`: `local L = {} … return L`) in which the engine implements a per-source
   sliding-window rate limit for server net events: allow at most `max` calls per source within `windowMs` of the
   caller-supplied clock; separate sources are independent; invalid `max`/`windowMs` are rejected; state lives in a
   table the caller passes, never in globals. `task.md` states the exact function name, signature and rules.
2. `.aeterna/golden/oss-undeclared/`: an ES module in `fixture/` (Node 22, `node:` built-ins only) in which the
   engine implements: given the net events a resource uses (name + `server`/`client` side) and its parsed `oss.json`
   object, return the sorted, de-duplicated names not declared in `capabilities.netEvents[side]`; a manifest whose
   `capabilities.netEvents.server` or `.client` is missing or not an array of strings throws a `TypeError`.
   `task.md` states the exact export, signature and rules.
3. Each `fixture/` ships only a stub (function present, body unimplemented) so the check **fails on base**. Never
   include a working implementation anywhere.
4. Each check: run from the task directory; no nonce in the environment ⇒ exit 2 with a hint; otherwise start a child
   without the nonce that loads the fixture and checks ≥ 6 expectations (incl. edge cases); print the nonce last and
   only when the child reported success and at least one expectation ran. A fixture that exits 0 or prints nothing
   while being loaded is never a pass. The Lua check runs with stock `lua` (5.4) only; the JS check with `node` only.
   Comment each check the way the header of a check explains its parent/child design.
5. `meta.toml`: a one-line comment, `check = "<cmd>"`, `timeout = 60`. `task.md` ends with
   "Only edit files under `fixture/`. Do not touch `check/`."
6. Nothing outside `.aeterna/golden/` changes; the repo's CI and devkit scans must not pick these files up.

## Acceptance (the Orchestrator runs these)
- **(g1)** each check, from its task dir, without `AETERNA_GOLDEN_NONCE` ⇒ exit 2, nonce not printed.
- **(g2)** with a nonce, on the stub fixture ⇒ exit ≠ 0, nonce not printed.
- **(g3)** with a nonce, fixture replaced by one that only `os.exit(0)` / `process.exit(0)` at load ⇒ exit ≠ 0.
- **(g4)** `qualify -E claude` passes both (baseline), proving a correct fixture can pass.
- **(g5)** `npm run ci`-equivalent gates (devkit tests, check, safety, busted) unchanged on the result.

## Scope
`.aeterna/golden/**`

## Out of scope
`.aeterna/checks.toml` · `.aeterna/engineer.md` · `.github/**` · devkit · packages · org-standards.

Shell: you may run only `lua`, `node`, `ls`, `cat`. Scratch in `$TMPDIR` only. No git, mktemp or package installs.
