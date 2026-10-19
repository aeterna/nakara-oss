# O-02 · T10 · Q2 repo checks for nakara-oss

**Repo:** nakara-oss · **Branch:** `feat/o-02-q2-checks` · **Route:** opencode:A → claude:A · **Gate:** G1 Pik 2026-10-19 (Phase 2 go) · D5 (≤ 100 lines, no release)

## Goal (requirements only)
`aeterna-delegate` runs `<repo>/.aeterna/checks.toml` (read from base) after every write run, on a clean copy of base
and on base + patch, and reports `q2 <name>: pass|new-failure|pre-existing|…`. nakara-oss has no checks file, so Q2
says `not-configured`. Add one that mirrors this repo's local CI (`AGENTS.md` → Commands) as far as it runs offline.
1. `.aeterna/checks.toml` with one `[[checks]]` per local gate: devkit unit tests, `fivem-devkit check`,
   `fivem-devkit safety` (includes oss.json schema validation), busted Lua specs. Each has `name`, `cmd`, `timeout`
   (seconds, realistic + margin) and `deps` (the config, harness and fixture globs that check reads).
2. Environment the commands run in (facts, not choices): macOS seatbelt, **no network**; the copy is a `git archive`
   of the commit, so **no `node_modules/`** (and no `.git`); writes only inside the copy and a scratch dir;
   `HOME` = that scratch dir; `PATH` is the caller's (`node`, `npm`, `busted` exist); `$USER` is set; the real
   `/Users/$USER/.npm` cache is readable, not writable; anything under `~/freelance` is unreadable.
3. A check that needs npm packages must get them without network, and must fail (non-zero) — never pass silently —
   when they cannot be installed. Install scripts never run.
4. Every command exits 0 on today's `main` under the conditions in 2, and non-zero when its gate fails.
5. Comment the file the way `org-standards/.aeterna/checks.toml` is commented (what Q2 does, how to skip once).
6. No other change.

## Acceptance (the Orchestrator runs these; the file is config, so there is no test-first run)
- **(a1)** each check, run as `/bin/sh -c "<cmd>"` in a fresh `git archive` of base under a seatbelt matching 2 ⇒ exit 0.
- **(a2)** control: a copy with one devkit test made to fail / a spec made to fail / `os.execute` added to
  `templates/resource/client/main.lua` ⇒ that check exits non-zero.
- **(a3)** a copy with `npm` unable to reach any cache (`/Users/$USER/.npm` renamed in a throwaway HOME) ⇒ the npm
  checks exit non-zero.
- **(a4)** `python3 -c "import tomllib; tomllib.load(open('.aeterna/checks.toml','rb'))"` parses; names match `A-Za-z0-9_.-`.

## Scope
`.aeterna/checks.toml`

## Out of scope
CI workflows (`.github/**`) · `package.json` scripts · devkit code · `org-standards` · the git-dependent scripts in
`.github/scripts/` (no `.git` in the copy).

Shell: you may run only `node`, `npm`, `busted`, `ls`, `cat`. Scratch in `$TMPDIR` only. Do not run git, mktemp or `npm install` in the worktree.
