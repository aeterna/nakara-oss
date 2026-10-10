# nakara_example

<!-- Template: copy templates/resource/ to packages/<name>/, then replace every `nakara_example` and
     `example` (oss.json "name"), fill in each section and delete this comment. Keep all section headings:
     CI and reviewers look for them. -->

One paragraph: the problem this resource solves for a server owner, in their words.

## What it does

- What runs on the client, what runs on the server.
- What it changes in the game, and what it deliberately does not touch.

## Install

1. Download `nakara_example-<version>.zip` from the
   [Releases](https://github.com/aeterna/nakara-oss/releases) page and verify it (see below).
2. Extract it into your `resources/` folder so you have `resources/nakara_example/fxmanifest.lua`.
3. Add to `server.cfg`:

   ```
   ensure nakara_example
   ```

Dependencies and ensure-order requirements, if any, go here.

## Config

`config.lua`:

| Key | Default | Meaning |
|---|---|---|
| `Config.Greeting` | `'hello'` | text returned by the `getGreeting` export |

## Capabilities

What this resource is allowed to do to your server, from [`oss.json`](oss.json). Keep this table in sync
with `oss.json`; widening a capability needs maintainer review.

| Capability | Declared |
|---|---|
| HTTP requests | none |
| `ExecuteCommand` | none |
| Registered commands | none |
| Convars read | none |
| Convars written | none |
| Server net events (accepted from clients) | none |
| Client net events (accepted from the server) | none |
| NUI | no |
| Database tables | none (no DDL) |
| Files written | none |

## Verify before you install

Every release zip is built in CI and carries a build-provenance attestation. Check both the attestation
and the checksum before you put it on your server:

```sh
gh attestation verify nakara_example-<version>.zip --repo aeterna/nakara-oss --signer-workflow aeterna/nakara-oss/.github/workflows/release.yml
sha256sum -c SHA256SUMS --ignore-missing
```

Then read the capability table above (or `oss.json` inside the zip).

## License

MIT. See [LICENSE](../../LICENSE).
