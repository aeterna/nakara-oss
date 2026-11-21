# Releasing Nakara Tickets

ADR 0003 decision 11. Workflow: `.github/workflows/tickets-release.yml`.

One release tag `nakara-tickets@<version>` covers both parts:

- the container image `ghcr.io/aeterna/nakara-tickets:<version>` (linux/amd64), with a build-provenance attestation
  pushed to the registry;
- the resource zip `nakara_tickets-<version>.zip` and `SHA256SUMS` on the GitHub release, each with a build-provenance
  attestation.

The resource `packages/tickets` is not released on its own through `release.yml`: its tag would be
`nakara_tickets@<version>` and it would ship without the matching image.

## Before the release (maintainer, in a PR to `dev`)

1. The three versions agree: `version` in `packages/tickets/fxmanifest.lua`, `version` in
   `tickets/apps/server/package.json`, and a `## <version>` section in `packages/tickets/CHANGELOG.md` (move the
   `## Unreleased` lines under it). The build job refuses when they differ or when the tag already exists.
2. The base image in `tickets/Dockerfile` is pinned by digest (`node:22-bookworm-slim@sha256:…`). Refresh the digest in
   the same PR when it is older than a month.
3. The change reaches `main` through the usual promotion PR. The workflow refuses to run from any other branch.

## Release (owner only)

1. GitHub → Actions → `tickets-release` → Run workflow (branch `main`).
2. The `build` job runs the tickets tests, type checks and builds, the resource specs, `fivem-devkit check` and
   `safety`, and builds the zip. Read its log.
3. Approve the `publish` job (environment `release`). It pushes the image, attests it, attests the zip, then creates
   the tag and the GitHub release. The release notes start with the image tag and its digest.
4. First release only: GitHub → the org → Packages → `nakara-tickets` → Package settings → change visibility to
   **Public** and link it to `aeterna/nakara-oss`. A package pushed by Actions in an org starts private.

## Check a release

```bash
gh attestation verify nakara_tickets-<version>.zip --repo aeterna/nakara-oss \
  --signer-workflow aeterna/nakara-oss/.github/workflows/tickets-release.yml
gh attestation verify oci://ghcr.io/aeterna/nakara-tickets:<version> --repo aeterna/nakara-oss
```

## If it fails

- `build` failed: nothing was published. Fix in a PR and run again.
- `publish` failed after the image push but before the release: the image tag exists without a release. Run the
  workflow again on the same commit; the push of the same tag replaces it and the release step creates the tag.
- The tag is immutable (`tags: no update or delete` ruleset). A wrong release is fixed with a new patch version.
