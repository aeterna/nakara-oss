# nakara-oss

Open-source FiveM resources and developer tooling from the **Nakara City** dev team. MIT licensed.

Everything here is built so that you can **check what you install before it runs on your server**:
every resource declares its capabilities in `oss.json`, every PR is scanned for dangerous code, and
every release is built in CI with a provenance attestation.

## Packages

| Package | What it is | Install |
|---|---|---|
| [`cargen-fix`](packages/cargen-fix) · resource `nakara_cargen_fix` | Stops the `CNetworkCarGenWorldStateData Pool Full` client crash | [Releases](https://github.com/aeterna/nakara-oss/releases?q=nakara_cargen_fix) → drop into `resources/` → `ensure nakara_cargen_fix` |
| [`devkit`](packages/devkit) · npm `@aeterna/fivem-devkit` | Static checks for FiveM Lua/JS, a code-safety scanner, a busted test harness | `npx @aeterna/fivem-devkit check` |

Download a **release asset**, not the repository ZIP — the repo contains tests and tooling you do
not need on a server.

## Verify before you install

```bash
gh attestation verify nakara_cargen_fix-1.0.0.zip --repo aeterna/nakara-oss   # built by our CI from a tagged commit
sha256sum -c SHA256SUMS                                                    # file not altered
npx @aeterna/fivem-devkit safety ./nakara_cargen_fix                       # scan it yourself
```

Then read the package's **Capabilities** table (from `oss.json`): it lists every HTTP host,
command, convar, net event, database table and file a resource may touch. If the code does
anything not listed there, our CI fails — and so will your own `safety` run.

## Contributing

PRs welcome — read [CONTRIBUTING.md](CONTRIBUTING.md) (DCO sign-off, what gets reviewed how).
Security issues: [SECURITY.md](SECURITY.md), never a public issue.

## License

[MIT](LICENSE)
