# aeterna_notify

- Package: `packages/notify` · resource `aeterna_notify` · wave W2 · status released in 0.1.0 · spec 0.2.0
  ([0.2 additions](#02-additions) at the end, [ADR 0005](../adr/0005-starter-kit-0-2.md))
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

---

## 0.2 additions

- Version: 0.2.0 ([ADR 0005](../adr/0005-starter-kit-0-2.md) decision 1) · edges unchanged: `aeterna_core`;
  `aeterna_layout` optional, local events only
- Written by: Claude Code - Claude Opus 5.5 (helper)

Everything above stays valid; a 0.1 call shows the same toast in 0.2. Already in 0.1, so not new here: the four
toast types, replace-by-`id`, the announcement queue, the MOTD, and the `toasts` / `announce` layout elements.

| What | New in 0.2 |
| --- | --- |
| Toasts | up to 2 action buttons; a lifetime bar; identical toasts merge into one with `×n`; optional sound |
| Announcements | a countdown announcement with reminders |
| History | a client export that returns recent notifications, so `aeterna_phonekit` can pull them |

Direction stays one way: `aeterna_phonekit` depends on notify and calls its exports; notify never calls, lists or
names phonekit (ADR 0005 decision 2: no edge from notify to phonekit).

### Configuration (0.2)

| Key | Default | Meaning |
| --- | --- | --- |
| `Config.toast.lifetimeBar` | `true` | Draw the lifetime bar on timed toasts |
| `Config.toast.merge` | `true` | Merge identical toasts into one with a count |
| `Config.toast.actionDuration` | `8000` | Default `duration` of a toast with actions, ms (1000–15000) |
| `Config.sound.enabled` | `false` | The server owner allows sounds at all. `false` = no sound for anyone |
| `Config.sound.playerDefault` | `false` | Whether a player who has not chosen hears sounds when the owner allows them |
| `Config.sound.byType` | see below | Base-game frontend sound per toast type: `{ info = { name, set }, … }` |
| `Config.countdown.marks` | `{ 600, 300, 60, 30, 10 }` | Seconds left at which a countdown shows its banner again |
| `Config.history.max` | `50` | Entries kept in the history, 0–50; `0` turns history off |

`Config.sound.byType` ships with base-game frontend sound names for `info`, `success`, `warning`, `error`, played
with `PlaySoundFrontend(-1, name, set, true)`. The shipped names are **not verified yet** on FXServer Enhanced; the
`sound_plays` self-test checks them, and a name that plays nothing is replaced before release. No sound files ship.

### Toast fields (0.2)

`opts` gains four optional fields. The 0.1 fields and limits are unchanged.

```lua
{ title = 'Mind sent a location', description = 'Elysian docks · 1.2 km', type = 'info',
  actions = { { id = 'pin', label = 'Pin it', variant = 'primary' }, { id = 'skip', label = 'Ignore' } },
  sound = true,        -- false = never play a sound for this toast
  history = true,      -- false = keep it out of the history
  merge = true }       -- false = never merge this toast
```

| Field | Rule |
| --- | --- |
| `actions` | 1–2 entries. `id` ≤ 32 matching `^[%w_%-]+$`, unique in the toast; `label` ≤ 20; `variant` `primary` or `secondary` (default `secondary`). A third entry, a bad id or an over-long label makes the whole toast fall back to no actions, with one `warn`. |
| `sound` | boolean, default `true`; only plays when both the owner and the player allow sound. **Changed in 0.2:** only `false` turns it off; any other value (for example the string `'bell'`, which 0.1 ignored with the other extra `lib.notify` keys) reads as `true` and is not rejected. Reason: the field is a switch, not a sound name; the sound per toast type comes from `Config.sound.byType`. Upgrade note: a caller that passed a non-boolean `sound` now allows the sound when the owner and the player allow it; pass `sound = false` to keep it silent. |
| `history`, `merge` | boolean, default `true`. |

### Action buttons

Toasts still never take focus and never block input (0.1 rule). So an action is pressed in one of two ways:

1. **Key mappings** `+aeterna_notify_action1` and `+aeterna_notify_action2` (default keys `Y` and `U`, ADR 0004 decision 10 amended 2026-11-22)
   press the first or second action of the newest toast that has actions. The button shows the player's binding
   (`GetControlInstructionalButton`); unbound shows locale `notify.action.unbound`.
2. **Mouse**, only when the cursor is already free because another resource holds focus.

Pressing an action closes the toast. A toast that times out fires nothing; the owner treats silence as "not
pressed". Toasts with actions are never merged.

Where the press goes depends on who created the toast:

| Created by | Press is delivered as |
| --- | --- |
| client export `notify(opts)` | client-local event `aeterna_notify:action` → `({ owner, toastId, action })`. `owner` is the resource that called the export (`GetInvokingResource()`, which is reliable for exports). The owner filters on `owner == GetCurrentResourceName()`. |
| server export `notify(src, opts)` | the client sends `aeterna_notify:sv:action { toastId, action }`; the server checks that it sent that `toastId` to that player, that `action` is one of its ids, and that the toast is not older than its `duration` + 2000 ms; then fires the server-local event `aeterna_notify:action` → `(src, { owner, toastId, action })`. Each `toastId` answers at most once. |

`toastId` is the toast's `id` when given. Otherwise it is generated: `c` + a base-36 counter for a toast made by the
client export, `s` + a base-36 counter for one made by the server export (≤ 24), so a client toast and a server toast on
screen together never share an id. History uses the same id. A toast with `actions` and an `id` longer than 24
characters is refused (`id: maxLen 24 with actions`), because a press carries the `toastId` in at most 24 characters.

**Changed in 0.2 — the client export's return value.** `notify(opts)` returns the `toastId` instead of `true`; the
server export keeps its return shape (`true, nil, clean` or `false, err`) and `clean.toastId` holds the id. Reason: the
caller needs the id to match the later `aeterna_notify:action`. Upgrade note: a 0.1 caller that tests the result for
truthiness still works (a string is truthy); one that compares it with `== true` must change.

The server keeps its record of open action toasts per player, keyed by owner resource + `toastId`, so one resource
never replaces or evicts another's. At most 8 per player per owner; a ninth replaces that owner's oldest, whose press is
then refused. Sending the same `id` again without `actions` drops that owner's record. No function crosses resources.

### Lifetime bar

A 2 px bar along the bottom of a timed toast shrinks from full to empty over its `duration`, in `--text-3` (`--warn`
for `warning`, `--bad` for `error`). It restarts when the toast is replaced by `id` or merged. Under
`prefers-reduced-motion: reduce` the bar is not drawn, because a shrinking bar is movement.

### Merging identical toasts

- **Duplicate key** = owner resource + `type` + `title` + `description` after cleaning (`AeternaCore.text.clean`),
  compared exactly. `icon` and `duration` are not part of it.
- A toast is merged only when it has no `id`, no `actions`, `merge ~= false`, and a toast with the same key is still
  on screen. Then no new toast is added: the one on screen shows `×n` (n counts every copy, `×2` first; above 99 it
  shows `×99+`), keeps its place in the stack and restarts its timer and lifetime bar.
- A toast with an `id` keeps the 0.1 rule (replace in place) and is never merged.
- **Changed in 0.2:** merging is on by default (`Config.toast.merge = true`), so a server that sends the same toast
  several times now sees one toast with `×n` instead of a stack. Reason: a stack of copies hides other toasts.
  Upgrade note: set `Config.toast.merge = false` for the 0.1 behaviour; `merge = false` on one toast exempts it.
  The lifetime bar is also on by default (`Config.toast.lifetimeBar = false` removes it).
- A merged copy plays its sound only if the toast's last sound started more than 1000 ms ago (`L.SOUND_THROTTLE_MS`), so a
  burst of copies makes one sound.

### MOTD while paused

When another resource takes focus through `aeterna_core`'s focus overlay (core 0.2, [aeterna_core.md](aeterna_core.md) §
Focus), the MOTD card stays on screen and ignores input until focus comes back. A real focus loss closes it as
"Continue", as in 0.1.

### Sound

Plays only when `Config.sound.enabled = true` **and** the player's own setting is on **and** the toast's
`sound ~= false`. The player's setting is the command `aeterna_notify_sound` (toggles, then shows a toast with the
new state; notify has no settings card and no uikit edge). It is stored in client KVP
`aeterna_notify:settings:v1 = { sound = boolean }`; with no saved value, `Config.sound.playerDefault` applies.
Announcements and the MOTD make no sound.

### Countdown announcements

| Export / command | Notes |
| --- | --- |
| `announceCountdown(opts)` (server export) | `opts = { title, body?, seconds, by?, marks? }`. `title` ≤ 80, `body` ≤ 200, `by` ≤ 32, `seconds` 10–3600, `marks` up to 8 integers below `seconds` (default `Config.countdown.marks`). Returns `countdownId` or `nil, err`. |
| `cancelCountdown(countdownId)` (server export) | Hides it for everyone and fires `aeterna_notify:countdownEnd` with `cancelled = true`. Only the resource that started the countdown can cancel it; another resource's call returns false and changes nothing. |
| `aeterna_announce_countdown <minutes> <text>` (command) | Same ACE as `aeterna_announce` (`aeterna.notify.announce`; console always allowed). `minutes` 1–60. `title` = locale `notify.countdown.title`. |

- One countdown at a time; a second `announceCountdown` returns `nil, 'busy'`.
- The banner shows the time left as `mm:ss` in tabular figures, counted down by each client from the
  `remainingMs` the server sends; the server is the clock that ends it.
- Each showing of the banner stays up for 8 seconds, then hides. A showing with 16 seconds or less left stays until zero.
  At each mark the server sends the banner again with a fresh `remainingMs`, so a player who joined late sees it from
  the next mark on. A countdown banner goes ahead of the normal announcement queue and does not count against it.
- At zero the server fires the server-local event `aeterna_notify:countdownEnd` → `({ countdownId, cancelled =
  false })`. If the resource that started the countdown stops, or notify stops, the countdown ends at once with
  `cancelled = true`. notify does nothing else at zero; a restart or a kick is the owner's own resource's job.

### History

| Export (client) | Returns |
| --- | --- |
| `history(limit?)` | The newest entries first, at most `limit` (1–50, default 50): `{ id, owner, kind = 'toast' | 'announce' | 'countdown', type, title, description, icon, count, at }` |
| `clearHistory()` | nil |

- An entry is added when a toast or a banner is shown. A merged toast updates `count` and `at` of its entry instead
  of adding one. `at` is `AeternaCore.time.now()` (seconds).
- Actions are not kept: history is for reading, never for pressing a button later.
- Memory only. History is not written to KVP and is empty after a reconnect.
- notify also fires the client-local event `aeterna_notify:added` → `(entry)` for every new or updated entry, so a
  reader can refresh without polling. notify never knows who listens.
- Toasts with `history = false` and the MOTD never enter the history.

### Events (0.2)

| Event | Direction | Schema | Rate limit |
| --- | --- | --- | --- |
| `aeterna_notify:sv:action` | client → server | `{ toastId: string ≤ 24, action: string ≤ 32 }` | 5 / 1000 ms |
| `aeterna_notify:cl:countdown` | server → all clients | `{ countdownId, title, body?, by?, remainingMs }` or `{ countdownId, hide = true }` | — |
| `aeterna_notify:action` | client-local and server-local | `{ owner, toastId, action }` (server-local adds `src` first) | — |
| `aeterna_notify:countdownEnd` | server-local | `{ countdownId, cancelled }` | — |
| `aeterna_notify:added` | client-local | history entry | — |

**Changed in 0.2 — "There is no client → server event."** 0.2 adds `aeterna_notify:sv:action`, rate limited with
`AeternaCore.rateLimit`, because a server-created toast's action has to reach the server. Announcements still come
only from the server export or the ACE-checked commands. Upgrade note: none for callers.

### NUI messages (0.2)

Lua → NUI adds `toast:merge {id, count}`, `countdown:show`, `countdown:hide`, `settings {sound}`; `toast:add`
carries `actions`, `toastId` and `lifetime`.
NUI → Lua adds `toastAction {toastId, action}`, validated against the toast on screen before it is forwarded.

### Type tokens

0.1 sets pixel sizes in `style.css`. 0.2 uses the theme type tokens (ADR 0005 decision 9; `--fs-1` smallest …
`--fs-5` largest, line height `--lh`):

| Text | Token |
| --- | --- |
| `×n` count, `by` line, MOTD eyebrow, action key hint | `--fs-1` |
| Toast description, banner body, MOTD lines | `--fs-2` |
| Toast title, action buttons | `--fs-3` |
| Banner title, countdown `mm:ss` | `--fs-4` |
| MOTD title | `--fs-5` |

### Commands and keys (0.2)

`aeterna_notify_sound`, `aeterna_announce_countdown`, `+aeterna_notify_action1` / `-aeterna_notify_action1`,
`+aeterna_notify_action2` / `-aeterna_notify_action2`, all registered with literal names, default keys `Y` and `U`.

### Storage (0.2)

KVP `aeterna_notify:settings:v1` = `{ sound = boolean }` (client). `aeterna_notify:motd_seen:v1` is unchanged.

### Locale keys (0.2)

`notify.action.unbound`, `notify.sound.on`, `notify.sound.off`, `notify.sound.disabled` (owner turned sound off),
`notify.countdown.title`, `notify.countdown.usage`, `notify.countdown.busy`, `notify.key.action1`,
`notify.key.action2`.

### `oss.json` capabilities (0.2)

```json
{ "http": [], "commands": [],
  "registeredCommands": ["aeterna_announce", "aeterna_announce_countdown", "aeterna_notify_sound",
                         "+aeterna_notify_action1", "-aeterna_notify_action1",
                         "+aeterna_notify_action2", "-aeterna_notify_action2"],
  "convars": { "read": [], "write": [] },
  "netEvents": { "server": ["aeterna_notify:sv:action"],
                 "client": ["aeterna_notify:cl:toast", "aeterna_notify:cl:announce", "aeterna_notify:cl:countdown",
                            "QBCore:Client:OnPlayerLoaded"] },
  "nui": true, "db": { "tables": [], "ddl": false }, "files": { "write": [] } }
```

### Tests (0.2, busted)

1. Actions: three actions, a bad id or a 21-char label fall back to no actions with one `warn`; a client press for
   an unknown `toastId`, an action id not in the toast, a second press, or a press after `duration` + 2000 ms is
   dropped; a good press fires `aeterna_notify:action` once with the right `owner`.
2. Merge: same key on screen → `×2` and timer restart, no new toast; different `description` → new toast; a toast
   with `id`, with `actions` or with `merge = false` is never merged; `×100` shows `×99+`.
3. Sound gate: plays only when owner, player and toast all allow it; a burst of five merged copies plays once.
4. Countdown: `seconds` 9 and 3601 fail; a second countdown returns `busy`; marks above `seconds` are dropped; the
   end event fires once with `cancelled = false`, and `cancelCountdown` fires it with `cancelled = true`.
5. History: newest first; `limit` clamps to 1–50; a merge updates `count` instead of adding; `history = false` and
   the MOTD stay out; `Config.history.max = 0` keeps nothing.
6. Settings KVP round trip; no saved value uses `Config.sound.playerDefault`.

### Self-tests (0.2)

Registered as `aeterna_notify.<name>`. "Skip when" is the only reason the test may report SKIP; a ped or eye test
with no person to run it reports GAP (ADR 0005 decision 7). A headless test needs no player and is listed as 1.

Kind `headless (client)` / `mock (client)` = `side = 'client'`: the test runs on the presser's client and is GAP
when there is no presser (ADR 0005 decision 7, W0 fix D3). Plain `headless` / `mock` run on the server.

| Name | Kind | Players | Destructive | Expect (what a person should see) | Skip when |
| --- | --- | --- | --- | --- | --- |
| `toast_opts` | headless | 1 | n | — | never |
| `merge_key` | headless | 1 | n | — | never |
| `action_forged` | headless | 1 | n | — | never |
| `countdown_clock` | headless | 1 | n | — | never |
| `toast_types` | eye | 1 | n | Four toasts, one per type, in the configured corner, each with a lifetime bar that empties in time | — |
| `stack_merge` | eye | 1 | n | Six identical toasts show as one toast reading `×6`, which does not jump | — |
| `action_press` | ped | 1 | n | A toast with two buttons; pressing the key bound to action 1 closes it and the test receives the first action's id (a presser with no key bound presses "Skip" on the card: GAP) | — |
| `sound_plays` | eye | 1 | n | Each toast type plays its sound once; with the player's setting off, none plays | `Config.sound.enabled = false` |
| `countdown_banner` | eye | 1 | n | A 30-second countdown banner counts down in `mm:ss` and disappears at zero | — |
| `history_pull` | headless (client) | 1 | n | — | `Config.history.max = 0` |
| `motion_reduced` | eye | 1 | n | The test turns reduced motion on for itself (it forces the page's reduced-motion rules for the run, since the Windows setting cannot be switched): toasts appear and disappear with no slide and no lifetime bar | — |

### Done when (0.2)

The 0.1 conditions, plus: the busted cases above pass, every self-test above is registered and passes on the
kit-test server (SKIP only for its listed reason), the shipped sound names are confirmed, and the owner has passed
screenshots of a toast with actions, a merged toast and a countdown banner in all three theme presets.
