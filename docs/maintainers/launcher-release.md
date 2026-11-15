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

   The command prints one line: the **public key**, 64 hex characters. It writes the private key to the file
   (mode 600) and never prints it.
2. Save the file's contents in your password manager.
3. GitHub → `aeterna/nakara-oss` → Settings → Environments:
   - create `launcher-release`;
   - under Required reviewers, add yourself;
   - turn on "Prevent self-review" only if someone else will approve;
   - restrict Deployment branches to `main`;
   - add an environment secret `LAUNCHER_SIGNING_KEY` whose value is the file's contents.
4. Delete the key file:

   ```bash
   rm ~/aeterna-launcher-signing.key
   ```

5. Send the **public** key (only that line) to the agent, or open a PR yourself that adds it to
   `launcher/profiles/aeterna/server.toml`:

   ```toml
   update_keys = ["<the 64 hex characters>"]
   ```

   A build made before this PR has no key and never installs updates.

To check which key the environment holds without seeing it, look at the sign step of any run. It prints the
public key that signed.

## Each release (owner)

1. Rongroi Connect must have a public release whose assets include a `*-win32-x64.zip` and its `SHA256SUMS` (K5, K7).
   The workflow checks the zip against those sums before it unpacks anything. Until Connect is public, the
   download step fails.
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
- **Key exposed:**
  1. Create a new key (step 1 above) and replace the secret.
  2. Add the new public key next to the old one in `update_keys` and release.
  3. In the next release, remove the old key.

  Builds that only know the old key need one release signed with the old key that carries the new list. If the old
  key itself is untrusted, players must download the new zip by hand.
- **Connect inside the zip:** Connect is GPL-3.0-or-later. The release notes link to the matching Connect release,
  where its source is published.
