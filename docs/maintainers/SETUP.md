# Creating the GitHub repo — one-time setup (owner)

Do these **before** the first public push. A repo that is public before its gates exist has a
window with no gates.

1. Create `aeterna/nakara-oss` as **private** first, push `main`.
2. Settings → General
   - Merge button: allow **squash** only · "Automatically delete head branches" on
   - Releases: **Enable release immutability** on
3. Settings → Actions → General
   - Actions permissions: allow only actions pinned to a full SHA and created by GitHub or
     verified creators, plus `leafo/*`, `rhysd/actionlint`, `zizmorcore/*`
   - **Fork pull request workflows from outside collaborators: "Require approval for all external contributors"**
   - Workflow permissions: **Read repository contents** (default token read-only) ·
     "Allow GitHub Actions to create and approve pull requests" **off**
4. Settings → Environments → new `release`
   - Required reviewers: owner · "Prevent self-review" **off** (single maintainer) ·
     Deployment branches: `main` only
5. Rulesets (from this folder):
   ```bash
   for f in .github/rulesets/*.json; do gh api repos/aeterna/nakara-oss/rulesets --method POST --input "$f"; done
   ```
   `release-tags` blocks moving or deleting any tag (GitHub refuses the Actions app as a ruleset
   bypass actor, so tag *creation* cannot be limited to the workflow; only people with write access —
   the owner — can create tags, and immutable releases lock a released tag). `main-gates` has no bypass (CI must pass for everyone, owner included). `main-review` lets the
   owner merge their own PRs without a second reviewer (there is no second maintainer yet) —
   every outside PR still needs owner approval of the latest push.
6. Settings → Code security: **Secret scanning + push protection** on · **Private vulnerability reporting** on ·
   Dependabot alerts + security updates on
7. npm (org `aeterna_game` exists since 2026-10-11). npm cannot attach a trusted publisher to a package
   that has never been published, so the first version is a hand-published stub:
   1. `npm login --auth-type=web` (browser login — not a token; a 2FA-bypassing token makes `npm trust`
      fail with E401)
   2. publish the empty `0.0.0` stub under the `bootstrap` dist-tag (`--provenance=false`; `latest` stays
      unset until CI publishes the real release)
   3. package settings → **Trusted publisher**: GitHub Actions · `aeterna/nakara-oss` · workflow
      `release.yml` · environment `release`; then **Require two-factor authentication and disallow tokens**
   4. run the `release` workflow for `devkit` within the same day — an unused trusted-publisher config
      expires (npm, Oct 2026)
   5. revoke any npm token created while setting this up. No npm token is ever stored in GitHub.
8. Push once more, open a test PR from a fork account, confirm: CI waits for approval · DCO job
   fails on an unsigned commit · merge is blocked until approval.
9. Flip visibility to **public**, then **immediately** set what GitHub only allows on public repos
   (checked 2026-10-10 on the Team plan — the API refuses these while private):
   ```bash
   R=aeterna/nakara-oss
   gh api -X PUT repos/$R/actions/permissions/fork-pr-contributor-approval -f approval_policy=all_external_contributors
   gh api -X PUT repos/$R/private-vulnerability-reporting
   gh api -X PUT repos/$R/environments/release --input - <<JSON
   {"reviewers":[{"type":"User","id":$(gh api users/tanakon8529 -q .id)}],"prevent_self_review":false,
    "deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
   JSON
   ```
   Until then the `release` environment has **no approval step** — only the branch policy (`main`).
   That is acceptable while private because only the owner can dispatch a workflow.

## Releasing

Actions → release → Run workflow → `package` = `cargen-fix` (or `devkit`). The build job tests and
bundles; the publish job waits for your approval in the `release` environment, then attests,
tags `<resource>@<version>`, and creates the GitHub release (and npm publish for devkit).
Version + notes come from the package's `fxmanifest.lua`/`package.json` and its CHANGELOG — bump
those in a normal PR first.
