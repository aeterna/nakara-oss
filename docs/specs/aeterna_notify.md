# aeterna_notify

- Package: `packages/notify` · resource `aeterna_notify` · wave W2 · status draft
- Depends on: `aeterna_core` (its own NUI; it does not use `aeterna_uikit`)

## Purpose and limits

Three ways to tell players something: a **toast** for one player, an **announcement** banner for everyone, and a
**message of the day (MOTD)** card shown once after joining.

Not in v0.1: sound, phone notifications (that is `aeterna_phonekit`, which calls this package), Discord relays,
scheduled announcements.

## Install

```cfg
ensure aeterna_core
ensure aeterna_notify
add_ace group.admin aeterna.notify.announce allow
```

## Configuration

`config.lua` (shipped) and `config/motd.json` (edited by the server owner):

| Key | Default | Meaning |
| --- | --- | --- |
| `Config.toast.position` | `'top-left'` | `top-left` · `top-right` · `bottom-left` · `bottom-right` (screen corner, 24 px inset) |
| `Config.toast.max` | `4` | Visible toasts; older ones leave first |
| `Config.toast.defaultDuration` | `4000` | ms |
| `Config.announce.queue` | `5` | Announcements waiting behind the current one; more are dropped with a `warn` |
| `Config.motd.enabled` | `true` | |

`config/motd.json`:

```json
{ "version": "2026-11-17", "eyebrow": "Message of the day", "title": "Welcome",
  "lines": ["Bind your phone key in Settings → Key Bindings → FiveM"], "buttons": { "dismiss": true } }
```

`title` ≤ 80, `eyebrow` ≤ 60, up to 8 `lines` of ≤ 160. Strings here are the owner's own text and are shown as written
(cleaned, never as HTML). A file that fails validation disables the MOTD and logs one `warn` with the failing path.

## Toasts

| Export | Side | Notes |
| --- | --- | --- |
| `notify(opts)` | client | `opts = { id?, title, description?, type = 'info'|'success'|'warning'|'error', duration?, icon? }`. Same field names as `lib.notify` in ox_lib, so calls move over by changing the function name. |
| `notify(src, opts)` | server | Sends to one player (`src = -1` is refused; use `announce`). |
| `clear(id?)` | client | Removes one toast or all. |

Rules: `title` ≤ 60, `description` ≤ 160, `duration` 1000–15000 ms, `icon` from the uikit icon names (copied into this
package's own map). A toast with an `id` already on screen replaces it in place and restarts its timer. Toasts never
take focus and never block input.

## Announcements

| Export / command | Notes |
| --- | --- |
| `announce(opts)` (server export) | `opts = { title, body?, duration = 8000, by? }`; `title` ≤ 80, `body` ≤ 200, `duration` 3000–30000, `by` ≤ 32 (shown small). Sent to every player. |
| `aeterna_announce <text>` (command) | Players need ACE `aeterna.notify.announce`; console always allowed. The text (≤ 200) becomes `body`; `title` = locale `notify.announce.title`; `by` = the player's name, or `Console`. |

One banner at a time, top centre. Others wait in the queue (`Config.announce.queue`). A player who joins later does
not get old announcements.

## MOTD

- Shown once per `version` per player, after the player has spawned: on the base-game `playerSpawned` event, or on
  qbx `QBCore:Client:OnPlayerLoaded` when `qbx_core` is started. The export `showMotd()` (client) lets other
  frameworks trigger it.
- Buttons: "Don't show again" stores the version in KVP `aeterna_notify:motd_seen:v1`; "Continue" closes it only for
  this session. ESC = Continue.
- The MOTD takes focus through `aeterna_core` and gives it back when closed.

## Position and `aeterna_layout`

`Config.toast.position` is the default. When `aeterna_layout` is started, notify registers two elements through
layout's local events (ADR 0004 table: optional edge, local events only; owner, 2026-11-17):

| `id` | What moves | `hideable` |
| --- | --- | --- |
| `toasts` | The toast stack. New toasts grow away from the stack's anchor edge (anchor at the bottom → they stack upward) | `false` |
| `announce` | The announcement banner | `false` |

`w`/`h` are the stack's width and the height of four toasts at scale 1. Notify fires `aeterna_layout:add` on start and
on `aeterna_layout:hello`, and applies `aeterna_layout:apply` for its own ids. Without layout nothing changes. Notify
never lists layout in `dependencies`, never calls its exports and never loads its files. The MOTD card stays centred
and is not an element.

## Events

| Event | Direction | Schema | Rate limit |
| --- | --- | --- | --- |
| `aeterna_notify:cl:toast` | server → client | toast opts | — |
| `aeterna_notify:cl:announce` | server → all clients | announce opts + `id` | — |

There is no client → server event. Announcements come only from the server export or the ACE-checked command.

## NUI messages

Lua → NUI: `aeterna:theme`, `locale`, `toast:add`, `toast:clear`, `announce:show`, `motd:show`, `motd:hide`.
NUI → Lua callbacks: `motdClose {dismiss: boolean}`, `escape {}`.

## Storage

KVP `aeterna_notify:motd_seen:v1` = the last dismissed MOTD version (string ≤ 40).

## Locale keys

`notify.motd.dismiss`, `notify.motd.continue`, `notify.announce.title`, `notify.announce.by`, `notify.announce.console`,
`notify.announce.usage`, `notify.announce.denied`.

## `oss.json` capabilities

```json
{ "http": [], "commands": [], "registeredCommands": ["aeterna_announce"],
  "convars": { "read": [], "write": [] },
  "netEvents": { "server": [], "client": ["aeterna_notify:cl:toast", "aeterna_notify:cl:announce",
                                         "QBCore:Client:OnPlayerLoaded"] },
  "nui": true, "db": { "tables": [], "ddl": false }, "files": { "write": [] } }
```

(`QBCore:Client:OnPlayerLoaded` is listed because the client registers it as a net event when `qbx_core` is started.
`LoadResourceFile` of its own `config/motd.json` needs no capability.)

## Tests

busted:

1. Toast queue: a fifth toast pushes out the oldest; same `id` replaces in place and keeps the position.
2. Toast opts: over-long title is cut, unknown type falls back to `info`, duration clamps to 1000–15000.
3. Announce queue: one shown, five waiting, the seventh dropped with a `warn`.
4. MOTD: shown when `seen ≠ version`; not shown when equal; a bad `motd.json` disables it with one `warn`.
5. Command: player without ACE gets `notify.announce.denied`; empty text gets the usage line.

Smoke:

1. Toasts of all four types in each corner; a replacing toast does not jump.
2. `aeterna_announce` from console and from an admin: banner appears for two clients; a non-admin is refused.
3. MOTD after first spawn; "Don't show again" survives a reconnect; changing `version` shows it again.
4. Screenshots in Asphalt for the owner's visual gate; reduced-motion setting removes all movement.
5. With `aeterna_layout` started: drag the toast stack and the banner, Done, reconnect, both stay; anchor the stack
   at the bottom and new toasts grow upward. Stop `aeterna_layout`: toasts go back to `Config.toast.position`.

## Done when

All busted cases pass, `fivem-devkit safety` reports 0 errors and 0 over-declared items, the smoke steps pass, and
the owner has passed the screenshots.
