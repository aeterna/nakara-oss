# Security policy

## Reporting a vulnerability

Use **[private vulnerability reporting](https://github.com/aeterna/nakara-oss/security/advisories/new)**.
Do not open a public issue or PR for a vulnerability. Expect a first reply within 7 days.

In scope: any package in this repo, the release pipeline, and bypasses of the safety scanner
(`packages/devkit/src/safety`) — a way to get dangerous code past it counts as a vulnerability.

## How this repo protects servers that install it

| Layer | What it does |
|---|---|
| Repository rules | `main` changes only through PRs; CI must pass for everyone; outside PRs need the owner's approval of their **latest** push; workflows from forks need approval before they run and never receive secrets or a write token |
| Safety scanner | blocks dynamic code loading, OS command execution, reading secret convars (`rcon_password`, `sv_licenseKey`, tokens…), granting ACE permissions via `ExecuteCommand`, obfuscated code, and committed binaries/minified bundles; anything else powerful (HTTP, commands, convars, net events, NUI, DB, file writes) must be declared in `oss.json` |
| Owner-only paths | `.github/`, every `oss.json`, the schema, and the whole devkit can only change with owner review (`CODEOWNERS`) |
| Releases | built and tagged only by the `release` workflow after owner approval; immutable; each asset has a build-provenance attestation and a SHA-256 sum |
| Dependencies | actions pinned to commit SHAs; npm installs with `--ignore-scripts`; updates wait 14 days after upstream release |

What it can **not** guarantee: the scanner finds dangerous *APIs*, not dangerous *logic* inside
allowed APIs. It scans **resources** only — the devkit itself is Node tooling that legitimately uses
the filesystem and is protected by owner review alone; if you run it in CI, pin it through your
lockfile (`npm ci`, never a floating `npx` version) and run it in a job without secrets. Human review stays required, and you should still read the capability table and
test a release on a non-production server first.

## Supported versions

Only the latest release of each package receives fixes.
