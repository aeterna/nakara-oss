# Your own launcher, for your own server

ADR 0002. The launcher is MIT licensed. You can ship it for your own FiveM or Roblox server by editing one file,
`server.toml`. A profile is data only: it cannot run code on a player's PC, and the launcher refuses any host your
profile does not name.

If you only want to edit the profile, start from the [template repository](https://github.com/aeterna/aeterna-launcher-template): choose **Use this template**, edit
`server.toml`, and GitHub builds your Windows exe. To change the launcher itself, fork this repository and work in
`launcher/`.

## 1. Write your profile

Copy `launcher/profiles/example/` to `launcher/profiles/<your-id>/` and edit `server.toml`. Every field and its
limits: `launcher/schema/server.schema.json`.

| Field | What to put there |
|---|---|
| `server.id` | Lowercase id, 2–48 characters. It names the settings folder on players' PCs and the User-Agent |
| `server.name` | Your server's name as players know it |
| `server.game` | `fivem-legacy`, `fivem-enhanced` or `roblox` |
| `server.connect` | FiveM: `host:port`. Roblox: the numeric place id |
| `server.operator`, `server.contact_email` | Who runs the server and how to reach them. Required by Rockstar's Creator Platform License Agreement; shown in the footer |
| `server.feed` | Optional HTTPS URL of your feed (status, hours, players, news): `launcher/schema/feed.schema.json` |
| `server.invite_url` | Optional HTTPS link (your Discord, for example), opened in the browser |
| `server.release_repo`, `server.update_keys` | Optional: where your releases live and the public keys that sign them. See step 4 |
| `theme.accent`, `theme.template` | Your colour (`#rrggbb`) and the layout: `dusk` or `classic` |

Not allowed in your build, by the Creator PLA: Rockstar, GTA or FiveM marks in the launcher's own name or branding,
and ads or sponsor slots.

## 2. Check it

From `launcher/`:

```bash
cargo run -p launcher-core --bin profile-check -- profiles/<your-id>/server.toml --root .
```

`--root` is the folder your `assets/...` paths are relative to: `launcher/` in this repository. Errors make the
build fail and must be fixed. Warnings tell you which features are switched off (no news without a feed, no update
check without `release_repo` and `update_keys`). Exit code 0 means the profile builds.

## 3. Build

```bash
AETERNA_LAUNCHER_PROFILE=profiles/<your-id>/server.toml cargo build --release -p launcher-ui
```

The profile is compiled into the exe. Changing it means building and releasing again.

## 4. Updates (optional)

The launcher checks your GitHub releases at start and shows a link when a newer, signed release exists. It only
trusts keys listed in your own profile, so a build signed by anyone else (including this project) is never offered
to your players.

1. Create your own signing key: `cargo run --release -p launcher-sign -- keygen --out <file>`. It prints the public
   key. Keep the private file offline and in your repository's environment secret, nowhere else.
2. Put the public key in `update_keys` and your `owner/name` in `release_repo`.
3. Release with the workflow and steps in `docs/maintainers/launcher-release.md`, using your own environment and
   secret. The workflow checks the signing key against `profiles/aeterna/server.toml`; change that path to your
   profile in your fork.

## 5. Tell your players

- What the launcher sends and to whom: `launcher/docs/privacy.md`. You run the feed host and the release
  repository, so you receive those requests, not this project.
- Your build is yours. You sign it and you answer for it; nothing in this project vouches for a fork.
