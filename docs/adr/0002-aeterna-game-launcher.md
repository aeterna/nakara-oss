# ADR 0002 — The launcher (`launcher/`): a data-only server profile, Rust and iced

- Status: accepted — owner, 2026-11-13 (Q1–Q16 and K-1…K-4 answered as recommended; Q10 decided from spike S)
- Date: 2026-11-13
- Related: aeterna-rongroi-connect ADR 0002 (the handoff contract, proposed); ADR 0001 (Server Kit); this repo's
  `AGENTS.md` hard rules 1, 2, 4 and 8; Cfx.re Creator Platform License Agreement of 10 Sept 2026 (§2.3, §3.1, §5)
- Written by: Claude Code - Claude Opus 5.5

## Context

A Windows launcher opens a game server's client and shows that server's status, hours and news. AETERNA Game uses it
for Nakara City, but it must also serve any FiveM server owner, who should be able to rebrand it without writing code
and to fork it when they do write code. Ideas (not code or assets) come from the MIT-licensed Horizon launcher: a game
list on the left, one large title, one row of actions with the play button first, a patch log.

Spike S (branch `spike/launcher-toolkits`, CI run 43418034275, GitHub `windows-latest`) drew the same window in GPUI
(`gpui-fast` 0.1.15) and iced 0.14.0:

| | GPUI | iced |
|---|---|---|
| Thai text with no U+200B in a 360 px box | wraps, by grapheme (can split a word) | overflows the box |
| Thai text through `launcher-thai` | correct word breaks | correct word breaks |
| Tone marks and vowels (Anuphan) | correct | correct |
| Release exe (msvc) | 13.98 MB | 13.51 MB |
| CI release build | 299 s | 202 s |
| Build on the maintainer's Mac | no: Metal shaders need the Metal Toolchain; the Windows build needs a Windows host | yes, native and `x86_64-pc-windows-gnu` |

Neither toolkit finds Thai word boundaries itself: GPUI uses `LineSegmenter::new_for_non_complex_scripts`,
cosmic-text (iced) only `unicode-linebreak`.

## Decision

1. **Rust and iced 0.14.** Owner, 2026-11-13, on the spike numbers: the Mac builds and cross-compiles it, so every
   change can be checked without waiting for a Windows runner. No WebView.
2. **Every string shown goes through `launcher-thai`.** One helper inserts U+200B between Thai words (ICU4X
   `icu_segmenter`). Strings from `lang/`, the profile and the feed all pass through it before they reach a widget; a
   test fails if a widget receives text that did not.
3. **One profile, data only.** A build embeds `server.toml` and `assets/` at compile time
   (`launcher/schema/server.schema.json`). It holds names, hosts, theme tokens and feature flags. It never holds
   HTML, scripts, plugins or executables, and nothing at run time adds to it.
4. **The feed is data only** (`launcher/schema/feed.schema.json`): status, hours, news and patch notes as JSON from the
   profile's `feed` URL. Nakara serves it at `/api/launcher/v1` and reads `ops.game_hours` through the existing
   `/api/game-hours`.
5. **Network.** The launcher connects only to: the profile's `feed` host, the host of its own GitHub release
   repository and GitHub's release-download hosts (for updates), and the Connect release host when
   `rongroi_connect` is on. HTTPS only; no redirects for the feed; private and loopback addresses refused unless the
   profile sets `allow_local_feed`. Images come only from the feed host and are capped by bytes and by decoded pixels.
   Links (`invite_url`, news links) must be `https:` and open in the browser. A server a player adds by hand
   (`allow_user_servers`, off in the AETERNA build) gets a connect button and nothing fetched.
6. **Joining.** FiveM: `fivem://connect/<host:port>` after a strict host:port check (community-documented only; the
   Enhanced client is measured before use). Roblox: `https://www.roblox.com/games/start?placeId=…` in the browser,
   never the `roblox-player:` handler. The launcher never reads or changes a game's files.
7. **Updates.** Each release carries an ed25519-signed manifest (version, channel, expiry, SHA-256 of each file). The
   launcher refuses a manifest whose signature fails, whose version is older than its own or that has expired; the
   build embeds a list of public keys so a key can rotate. The new exe replaces the old by rename, and the previous
   exe is kept to roll back. Each fork signs with its own key; AETERNA's private key is created by the owner and held
   in a GitHub Environment that needs the owner's approval for every release.
8. **Rongroi Connect stays a separate app.** The launcher starts it with `--from-launcher` and writes the pairing code
   to its stdin (Connect ADR 0002), then shows its exit code. Connect's consent and destination screens are unchanged.
9. **What the Creator PLA requires of every build.** The profile must name an `operator` and a `contact_email`; the
   launcher shows both and the line "<server name> IS NOT APPROVED, SPONSORED, OR ENDORSED BY ROCKSTAR GAMES." in its
   footer (§2.3). No Rockstar, GTA or FiveM marks in the launcher's own name or branding. No ads or sponsor slots
   (§3.1(7)).
10. **No telemetry.** The launcher sends nothing about the player. The feed host and GitHub see the request's IP
    address and user agent, and the docs say so.
11. **Where.** `launcher/` in this repo, MIT, its own Cargo workspace, its own release workflow; a separate small
    template repository for owners who only edit a profile. `launcher/assets/**` may hold fonts and images up to
    5 MB in total, each with its license file next to it (owner, 2026-11-13; `AGENTS.md` rule 4 amended).

## Consequences

- Any FiveM server can ship its own launcher by editing one file; nothing it ships can run code on a player's PC
  through the launcher.
- Thai text depends on one helper; a string that bypasses it overflows its box. The test in decision 2 is the gate.
- A forked build is that owner's responsibility and is signed by them; nothing here vouches for a build.
- Rockstar may later name tools it does not allow (PLA §5); the launcher would then have to change or stop.
