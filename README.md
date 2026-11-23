<div align="center">

**English** · [🇹🇭 ภาษาไทย](README.th.md)

# nakara-oss

### Free FiveM resources and tools you can check before they touch your server

[![npm](https://img.shields.io/npm/v/@aeterna_game/fivem-devkit?style=flat-square&label=fivem-devkit&color=1f6f5c)](https://www.npmjs.com/package/@aeterna_game/fivem-devkit)
[![Releases](https://img.shields.io/badge/Releases-CI--attested-0869b0?style=flat-square)](https://github.com/aeterna/nakara-oss/releases)
[![Capabilities](https://img.shields.io/badge/oss.json-checked_on_every_PR-6a4fe0?style=flat-square)](packages/devkit/docs/safety.md)
[![License](https://img.shields.io/badge/License-MIT-2b8a3e?style=flat-square)](LICENSE)

**[Website](https://aeterna.github.io/nakara-oss/en/) · [Scripts](#scripts-you-can-download) · [Scan a script](#scan-a-script-before-you-install-it) · [Trust Architecture](#️-trust-architecture) · [What the scanner cannot catch](#what-the-scanner-cannot-catch)**

</div>

Open-source FiveM resources and developer tooling from the **Nakara City** dev team. Every resource
declares in `oss.json` what it may touch, every PR is scanned for dangerous code, and every release is
built in CI with a provenance attestation, so you can re-check all of it yourself.

## Scripts you can download

Every script below is free (MIT), declares in `oss.json` what it may touch, and ships as a CI-built
release asset with a provenance attestation.

### FiveM resources

| Script | What it does | Latest release |
|---|---|---|
| [`nakara_tickets`](packages/tickets) + [server](tickets/deploy/README.md) | Self-hosted Discord ticket system: private-thread tickets, a Thai/English web dashboard, and staff actions in game (player info, teleport, revive, give item) over a bridge that opens no port | [`nakara-tickets@0.1.1`](https://github.com/aeterna/nakara-oss/releases/tag/nakara-tickets%400.1.1) · image `ghcr.io/aeterna/nakara-tickets:0.1.1` |
| [`nakara_cargen_fix`](packages/cargen-fix) | Guards against the `CNetworkCarGenWorldStateData Pool Full` client crash, and explains why the popular `GAMECONFIG_FILE` fix does nothing ([what is verified](packages/cargen-fix/README.md#what-we-have-verified)) | [`nakara_cargen_fix@1.0.0`](https://github.com/aeterna/nakara-oss/releases/tag/nakara_cargen_fix%401.0.0) |
| [`nakara_rongroi`](packages/rongroi) | Server side of [aeterna-rongroi](https://github.com/aeterna/aeterna-rongroi) | [`nakara_rongroi@0.2.0`](https://github.com/aeterna/nakara-oss/releases/tag/nakara_rongroi%400.2.0) |

### AETERNA Starter Kit · twelve base resources, five of them new in 0.2 ([guide](https://aeterna.github.io/nakara-oss/en/starter-kit/) · [theme playground](https://aeterna.github.io/nakara-oss/en/starter-kit/theme/))

| Script | What it does | Latest release |
|---|---|---|
| [`aeterna_core`](packages/core) | Shared foundation: logging, a local event bus, Thai-aware text helpers, locale lookup | [`0.2.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_core%400.2.0) |
| [`aeterna_uikit`](packages/uikit) | Server-owned UI panels, prompts (`confirm`, `input`, `progress`, `skillCheck`) and a shared menu | [`0.2.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_uikit%400.2.0) |
| [`aeterna_notify`](packages/notify) | Toasts, server-wide announcement banners, and a message-of-the-day card | [`0.2.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_notify%400.2.0) |
| [`aeterna_invkit`](packages/invkit) | Personal stashes and server-validated item use around `ox_inventory` | [`0.2.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_invkit%400.2.0) |
| [`aeterna_layout`](packages/layout) | HUD layout editor with layouts saved on the client | [`0.2.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_layout%400.2.0) |
| [`aeterna_phonekit`](packages/phonekit) | A modular phone shell with utility apps and an app API | [`0.2.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_phonekit%400.2.0) |
| [`aeterna_hudkit`](packages/hudkit) | Player HUD: status bars, vehicle cluster, street and compass, minimap | [`0.2.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_hudkit%400.2.0) |
| [`aeterna_radial`](packages/radial) | A radial menu other resources add slots to; picks that affect other players are re-checked on the server | [`0.1.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_radial%400.1.0) |
| [`aeterna_loading`](packages/loading) | A loading screen that shows the real loading stages, with your server's name, background and tips | [`0.1.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_loading%400.1.0) |
| [`aeterna_testkit`](packages/testkit) | One button that runs every kit self-test on your server and writes a report you can attach to an issue | [`0.1.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_testkit%400.1.0) |
| [`aeterna_phonecall`](docs/specs/aeterna_phonecall.md) | Phone numbers, text messages and voice calls as two apps inside the phone | [`0.1.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_phonecall%400.1.0) |
| [`aeterna_camera`](docs/specs/aeterna_camera.md) | Camera and gallery apps inside the phone; photos stay on your own server | [`0.1.0`](https://github.com/aeterna/nakara-oss/releases/tag/aeterna_camera%400.1.0) |

### Tools

| Tool | What it does | Latest release |
|---|---|---|
| [`fivem-devkit`](packages/devkit) · npm `@aeterna_game/fivem-devkit` | Finds dangerous code and silent bugs in anyone's FiveM Lua/JS, plus a busted test harness | [npm](https://www.npmjs.com/package/@aeterna_game/fivem-devkit) · `npx @aeterna_game/fivem-devkit check` |
| [AETERNA Game Launcher](docs/adr/0002-aeterna-game-launcher.md) | Your server's own game launcher, written in Rust · [install](launcher/docs/install.md) · [for server owners](launcher/docs/server-owners.md) | [`launcher-v0.2.0`](https://github.com/aeterna/nakara-oss/releases/tag/launcher-v0.2.0) |

Download a **release asset**, not the repository ZIP: the repo contains tests and tooling you do not
need on a server. All releases: [Releases](https://github.com/aeterna/nakara-oss/releases).

## Scan a script before you install it

```bash
npx @aeterna_game/fivem-devkit safety ./some_resource
```

A script from somewhere else has no `oss.json`. Put this in `.fivem-devkit.json` in the folder you
run from ([all options](packages/devkit/docs/safety.md)):

```json
{ "safety": { "requireManifest": false } }
```

Real output on a test resource:

```text
✗ [safety/dynamic-load] resources/some_script/server/main.lua:2
    load called — loads code at runtime that nobody reviewed
✗ [safety/host-exec] resources/some_script/server/main.lua:3
    os.execute — runs or changes things on the host machine
✗ [safety/secret-convar] resources/some_script/server/main.lua:4
    GetConvar('mysql_connection_string') reads a secret convar

safety: 3 error(s), 0 warning(s)
```

The output is a list of places to read, not a verdict.

## 🏗️ Trust Architecture

<img alt="Trust Architecture: source and oss.json go through the PR gate (devkit safety fails code that uses more than oss.json declares; oss.json changes need CODEOWNERS review), then a CI release with a provenance attestation and SHA256SUMS, then you re-check with the same tools before ensure. The scanner cannot catch logic bombs inside declared APIs, other resources' exports, or a server that trusts the client." src="docs/assets/trust-architecture-en.svg" width="960">

Verify a release before you install it:

```bash
gh attestation verify nakara_cargen_fix-1.0.0.zip --repo aeterna/nakara-oss --signer-workflow aeterna/nakara-oss/.github/workflows/release.yml
# ↑ proves the zip was built by our release workflow, not uploaded by hand
sha256sum -c SHA256SUMS                                        # file not altered
npx @aeterna_game/fivem-devkit safety ./nakara_cargen_fix      # scan it yourself
```

Then read the package's **Capabilities** table (from `oss.json`): it lists every HTTP host, command,
convar, net event, database table and file a resource may touch. If the code uses anything not listed
there, `fivem-devkit safety` fails in our CI, and so will your own run.

## What the scanner cannot catch

The scanner shows that code only uses what it declares. It cannot judge whether it uses that honestly:

- a logic bomb inside an API the resource is allowed to use;
- calls to other resources' exports;
- a server event that trusts the client;
- values built at runtime are reported but not traced.

A person still has to read the code. Details: [safety.md](packages/devkit/docs/safety.md#what-it-can-not-catch--human-review-stays-required).

## Contributing

PRs welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) (DCO sign-off, what gets reviewed how).
Security issues: [SECURITY.md](SECURITY.md), never a public issue.

## License

[MIT](LICENSE)
