# What the launcher sends, and to whom

ADR 0002 decision 10. This page is the long form of the notice the launcher shows once, the first time it opens
(`crates/launcher-ui/src/privacy.rs`). If the two ever disagree, the code is right and this page is a bug.

## No telemetry

The launcher has no telemetry, usage statistics, crash reports, accounts, or advertising. It sends nothing about
the player, the PC or the games on it. Its network code accepts only HTTPS, on port 443, to the hosts listed below
(`crates/launcher-net/src/policy.rs`). Any other host is refused before a connection is opened.

## The requests it makes

| When | Request | Who sees it | What they see |
|---|---|---|---|
| Every start, if the profile sets `server.feed` | `GET` the feed URL (news, opening hours, player count) | The server's feed host | IP address, the User-Agent `<server id>-launcher/<version>`, the time |
| Every start, if the profile sets `server.release_repo` **and** `server.update_keys` | `GET https://api.github.com/repos/<release_repo>/releases?per_page=100`, then the `manifest.json` and `manifest.json.sig` of up to five newer `launcher-v*` releases. GitHub may redirect those downloads to `objects.githubusercontent.com` or `release-assets.githubusercontent.com` | GitHub | IP address, the same User-Agent, the time, which repository is checked |

That is the whole list. The launcher never logs in to GitHub and sends no token or cookie. Without `release_repo` or
`update_keys` the update check is turned off and makes no request at all.

## Things the player starts, which are not launcher requests

- **Join**: the launcher hands the server address to the game client (FiveM or Roblox). From then on it is the
  game's own connection.
- **Invite link and release page**: open in the player's default browser. The browser makes that request, not the
  launcher.
- **Rongroi Connect** (the PC-check button): starts the bundled Connect program. Connect asks for consent again
  before it sends anything, and shows where the result goes. Its own privacy terms apply: see
  `aeterna/aeterna-rongroi-connect`.

## What it keeps on the PC

One file, `%APPDATA%\<server id>-launcher\privacy-notice-seen`, which records that the notice was read. It holds
no personal data. Deleting it shows the notice again on the next start.

## For server owners

A build is the profile's owner's build. The owner runs the feed host and chooses the release repository, so the
owner (not this project) receives the requests in the first table. When you publish your launcher, tell your
players who runs those hosts. Your `operator` and `contact_email` are shown in the launcher's footer for that
reason (decision 9).
