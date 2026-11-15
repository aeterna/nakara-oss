# Releasing the launcher

ADR 0002 decisions 7, 8 and 11. The workflow is `.github/workflows/launcher-release.yml`.

A launcher release is a draft GitHub release named `launcher-v<version>` that holds these assets:

- `aeterna-launcher-<version>-windows-x64.zip`: `aeterna-launcher.exe`, the `rongroi-connect/` folder (the bundled
  Rongroi Connect) and `LICENSE-launcher.txt`.
- `aeterna-launcher.exe`: the same exe, which the launcher's self-update downloads.
- `manifest.json`: version, channel, expiry, and SHA-256 and size for each file.
- `manifest.json.sig`: a raw 64-byte ed25519 signature over the exact bytes of `manifest.json`.
- `SHA256SUMS`: covers every asset. Every asset also carries a build-provenance attestation.

The launcher installs an update only when the signature verifies against a key listed in its profile's
`server.update_keys`, the version is newer than its own, and the manifest has not expired (`launcher-update`).
The launcher's screen does not check for updates yet; that is wired in a later change.

## Once: create the signing key (owner only)

Only the owner holds the private key. It lives in the owner's password manager and in one GitHub
Environment secret, and nowhere else. No agent ever sees it.

1. On your own machine, from a checkout of this repository:

   ```bash
   cd launcher
   cargo run --release -p launcher-sign -- keygen --out ~/aeterna-launcher-signing.key
   ```

   The command prints one line: the **public key**, 64 hex characters. It writes the private key to the file and
   never prints it. On macOS and Linux the file is created with mode 600. On Windows it inherits your profile
   folder's permissions.
2. Save the file's contents in your password manager.
3. GitHub → `aeterna/nakara-oss` → Settings → Environments:
   - create `launcher-release`;
   - under Required reviewers, add yourself;
   - turn on "Prevent self-review" only if someone else will approve;
   - restrict Deployment branches to `main`;
   - add the environment secret from the file, without printing it to the terminal:

     ```bash
     gh secret set LAUNCHER_SIGNING_KEY --env launcher-release --repo aeterna/nakara-oss < ~/aeterna-launcher-signing.key
     ```
4. Delete the key file:

   ```bash
   rm ~/aeterna-launcher-signing.key
   ```

   `rm` removes the file name; it does not overwrite the disk. With FileVault on, that is enough.

5. Send the **public** key (only that line) to the agent, or open a PR yourself that adds it to
   `launcher/profiles/aeterna/server.toml`:

   ```toml
   update_keys = ["<the 64 hex characters>"]
   ```

   A build made before this PR has no key and never installs updates.

The sign step prints the public key that signs (`signing key (public): …`), and it fails unless that key is in
`launcher/profiles/aeterna/server.toml` `update_keys`. A wrong or replaced secret therefore stops the release
instead of producing one that no build accepts. The manifest's product name is `aeterna-launcher`. The update check
must pass the same name when it is wired.

## Each release (owner)

1. Rongroi Connect must have a public release with a `rongroi-connect-<version>-windows-x64.zip`, its `SHA256SUMS`, and a build-provenance
   attestation from `aeterna/aeterna-rongroi-connect` (K5, K7). The workflow checks all three, then unpacks entry by
   entry and refuses any path that leaves the folder. Until Connect is public, the download step fails.
2. Bump `version` in `launcher/crates/launcher-ui/Cargo.toml` through a normal PR.
3. Actions → launcher-release → Run workflow on `main`, with:
   - `connect_tag`: the Connect release tag;
   - `channel`: `stable` or `beta`;
   - `expires_days`: how long the manifest stays valid. The default is 90; release again before it runs out.
4. Approve the `launcher-release` deployment when GitHub asks.
5. Download the draft's zip and run it on Windows: the Home screen loads, and the Connect button finds the bundled
   Connect. Then publish the draft.

## When something goes wrong

- **Bad release:** do not delete the release, since its tag is protected. Publish a newer version. The launcher
  installs only a version newer than its own, so the newer release takes over, and the bad manifest expires on its own.
- **Retiring or rotating a key.** The profile, and with it `update_keys`, is compiled into the exe, so a new key
  list reaches players through a release signed with a key they already trust. Do it in this order:
  1. Create the new key (step 1, with a new file name) and keep it out of GitHub for now.
  2. Release, signed with the **old** key, with `update_keys = ["<old>", "<new>"]`.
  3. Replace the secret with the new key (`gh secret set …`, as in step 3).
  4. Release, signed with the **new** key, with `update_keys = ["<new>"]`.
- **Key exposed and possibly used by someone else:** the steps above cannot repair this. Whoever holds the old key
  can sign updates that old builds accept. Create a new key, release a build that trusts only the new key, and tell
  players to download the new zip by hand.
- **Connect inside the zip:** Connect is GPL-3.0-or-later. The release notes link to the matching Connect release,
  where its source is published.
