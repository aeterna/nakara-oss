# Contributing

Thanks for helping. A few rules keep every server that installs these packages safe.

## Before you start

- Bugs and small fixes: open a PR directly.
- New features, new packages, or anything touching `.github/`, `oss.schema.json`, any `oss.json`
  capability, or `packages/devkit/src/safety/`: **open a Proposal issue first**. Changes to CI and
  to the safety scanner are written by the maintainer, so PRs to those paths from outside
  contributors are closed with a pointer to the issue.

## Developer Certificate of Origin (DCO)

Every commit must be signed off — it certifies you wrote the change or have the right to submit it
under MIT ([developercertificate.org](https://developercertificate.org)):

```bash
git commit -s -m "fix: …"          # adds Signed-off-by: Your Name <you@example.com>
git rebase --signoff main          # fix commits you already made
```

The name/email must match the commit author. CI checks this.

## Local checks

```bash
npm ci --ignore-scripts
npm run ci            # devkit tests · static checks · safety scan · busted
```

Lua tests need [busted](https://lunarmodules.github.io/busted/) (`luarocks install busted`).

## What CI will reject

- `load`/`loadstring`/`dofile`, `os.execute`, `io.popen`, `eval`, `new Function`, `child_process`
- reading secret convars, `ExecuteCommand` with ACE/exec/set/server-control commands
- obfuscated strings, minified or bundled JS, binaries, streamed GTA assets
- HTTP, commands, convars, net events, NUI, DB tables or file writes **not declared** in the
  package's `oss.json`
- server net event handlers without rate limiting (warning)

Full list and reasons: [packages/devkit/docs/safety.md](packages/devkit/docs/safety.md).

## Package layout

New packages start from [`templates/resource`](templates/resource). Each package has
`fxmanifest.lua`, `oss.json`, `README.md`, `CHANGELOG.md` and `spec/`. Resource names use the
`nakara_` prefix. Packages may depend only on the shared core package (when it exists), never on
each other.

## Changelog

Add your change under `## Unreleased` in the package's `CHANGELOG.md`. The maintainer turns that
into a version when releasing.

## Code of conduct

[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
