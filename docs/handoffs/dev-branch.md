# Handoff — `dev` + `main` branches (2026-11-17)

Owner ordered `main` + `dev` like `aeterna-rongroi` (2026-11-17). Session: nakara-oss branch cleanup ·
Claude Code - Claude Opus 5.5.

## Status now

| Item | State | Evidence |
|---|---|---|
| `dev` created from `main` | ✅ live | `af8c31f` · `git ls-remote origin refs/heads/dev` |
| default branch = `dev` · merge commits allowed | ✅ live | `gh api repos/aeterna/nakara-oss --jq .default_branch` |
| ruleset `dev: gates (no bypass)` (id 27434856) | ✅ live | `.github/rulesets/dev-gates.json` |
| ruleset `main: gates` (24836644) scoped to `refs/heads/main`, merge commits only | ✅ live | `.github/rulesets/main-gates.json` |
| ruleset owner review (24836645) on `dev` + `main` | ✅ live | `.github/rulesets/owner-review.json` |
| CI / org-checks / tickets on push to `dev` · Dependabot → `dev` · docs | ✅ merged | #61 `4eb4a87` |
| org table row (`org-standards` AGENTS) | ✅ merged | org-standards#152 `26b356c` |
| branch cleanup: 28 merged branches + 19 worktrees removed | ✅ | `fivem/backups/branch-cleanup-2026-11-17/manifest.txt` (+ dirty-worktree patches) |

## Short rules for other sessions

- New work: `git fetch origin && git worktree add -b <type>/<slug> .claude/worktrees/<slug> origin/dev` · PR into `dev` (squash).
- `main` moves only by a promotion PR `dev` → `main` (merge commit, owner merges). Releases, `launcher-release` and Pages run from `main` only (environment branch policies unchanged).
- A release PR opened straight into `main` (e.g. #60) needs `main` merged back into `dev` afterwards, or the next promotion conflicts.
- Rulesets live in `.github/rulesets/`; change the file and apply it with `gh api repos/aeterna/nakara-oss/rulesets/<id> --method PUT --input <file>` in the same PR.

## Owner's pending items

1. Next promotion PR `dev` → `main` (merge commit): carries #61 to `main`; #60/#62 are already on both sides.
2. Dependabot #21 #29 (now base `dev`, checks green) wait owner review.
3. Promotion fast gate (org AGENTS §11.2) not added — CI is ~1 min, not needed yet.

## Rollback

`gh api repos/aeterna/nakara-oss --method PATCH -f default_branch=main -F allow_merge_commit=false` ·
re-PUT the old ruleset JSON from `git show af8c31f:.github/rulesets/main-gates.json` / `main-review.json` (conditions `~DEFAULT_BRANCH`) ·
`gh api repos/aeterna/nakara-oss/rulesets/27434856 --method DELETE` · delete `dev` only after its commits are on `main`.
Deleted branches: recreate from the sha in the manifest.

## Log

1. Branch cleanup: proved each branch merged (tip commit in a merged PR, or delegate ledger `applied`), wrote manifest + patches of uncommitted engine drafts, removed 16 worktrees (incl. the 2026-11-13 "unproven" backup folder on WD1TB) and 25 branches.
2. Asked the Starter Kit session about its branches: it cleaned `delegate/kspike-*` itself, keeps #54 #58 `spike/kit-s1-s2`, retargeted #54 to `dev`.
3. Owner: "สร้าง dev" → created `dev`, applied rulesets + default branch, opened #61 (files) and org-standards#152 (table row).
4. Owner: "merge เลย" → merged #61 (`4eb4a87`) and org-standards#152 (`26b356c`) with the owner's-own-PR bypass; closed out both branches.
5. Owner: "ทำเลย" → deleted `delegate/task-20261117-*` ×3 (tips in `dev` / #57 commits, ledger `applied`; engine drafts saved as patches, manifest updated). #60 went to `main` and #62 brought it into `dev`. Dependabot retargeted #21 #29 to `dev` by itself.
