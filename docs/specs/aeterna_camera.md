# aeterna_camera

- Package: `packages/camera` · resource `aeterna_camera` · version 0.1.0 · wave W2 of Starter Kit 0.2 · status spec
- Depends on: `aeterna_core` (focus, validation, rate limit, ACE, locale, keys, self-tests), `aeterna_uikit` (panel
  spec format), `aeterna_phonekit` (App API tiles), `aeterna_notify` (saved / refused toasts);
  `screenshot-basic` optional, detected at run time — [ADR 0005](../adr/0005-starter-kit-0-2.md) decisions 2, 3, 4
  and 6

## Purpose and limits

Two apps inside the phone: **Camera** (a viewfinder with selfie and back camera, and a shutter) and **Gallery** (the
character's photos, view and delete). Photos are taken with `screenshot-basic` when it is started, saved on the
server's disk inside this resource's own folder, and served by this resource's HTTP handler under an id nobody can
guess.

The kit never uploads a photo anywhere and never reads a secret-named convar (`secret-convar` in
`packages/devkit/docs/safety.md`). A server owner who wants photos elsewhere writes their own resource that listens
to `aeterna_camera:saved` and forwards the file (§ Hook).

Without `screenshot-basic` the viewfinder still works, the shutter shows "Photos are not available on this server",
and the photo self-tests report SKIP. `screenshot-basic` is never in `dependencies`.

Not in 0.1: video, filters, sending photos in messages, a shared or public gallery, zoom beyond the base game's phone
camera, photo upload to other hosts.

## Install

```cfg
ensure aeterna_core
ensure aeterna_uikit
ensure aeterna_notify
ensure aeterna_phonekit
ensure screenshot-basic    # optional, for photos
ensure aeterna_camera
add_ace group.admin aeterna.camera.admin allow
```

Photos are files under `aeterna_camera/photos/`. The package ships `photos/README.txt` so the folder exists, because
`SaveResourceFile` does not create folders. **Replacing the resource folder on upgrade deletes them**: the
README tells owners to keep `photos/` (and the server KVP database, which FXServer keeps outside resource folders)
when they upgrade.

## Configuration

`config.lua` (shipped):

| Key | Default | Meaning |
| --- | --- | --- |
| `Config.perCharacter` | `60` | Photos per character, 1–500; at the cap the shutter refuses with `camera.full` |
| `Config.maxBytes` | `900000` | Largest accepted photo after decoding, 100 000 – 3 000 000 bytes |
| `Config.maxTotalMB` | `1024` | All photos together; at the cap every shutter refuses with `camera.disk_full` and one `warn` per hour |
| `Config.quality` | `0.8` | JPEG quality passed to `screenshot-basic`, 0.5–0.95 |
| `Config.cooldownMs` | `3000` | Minimum time between two shots of one player |

## Identity

Character key as in [aeterna_phonecall § Identity](aeterna_phonecall.md#identity): `cid:<citizenid>` from `qbx_core`
when started, else `lic:<license identifier>`, read on the server only.

## Viewfinder

- Opening the Camera tile: the server fires the app event, checks the player's tile `ace` (if any), and sends
  `aeterna_camera:cl:viewfinder`. The client takes focus with `AeternaCore.requestFocus({ cursor = false, keyboard =
  true, keepGameInput = true })`; phonekit loses focus and closes the phone (the 0.1 focus rule). Losing focus later
  closes the viewfinder. While another resource holds focus in core's overlay mode
  ([aeterna_core § Focus](aeterna_core.md#focus)) the viewfinder is paused: shutter and switch are ignored and it
  resumes when focus returns.
- The base-game phone camera is used: `CreateMobilePhone`, `CellCamActivate`, and the selfie mode native for the
  front camera. The player aims with the normal look controls. The exact native names and control ids are constants in
  `client/viewfinder.lua`; **which ones work on FXServer Enhanced is not verified yet** (first W2 smoke step).
- This package's own NUI draws only a thin overlay: shutter hint, switch hint, close hint (uikit `keyHints` style, read
  from the player's bindings), and a counter `12 / 60`.
- Controls, keyboard and gamepad through the base game's cellphone controls: select = shutter, the selfie control =
  switch camera, cancel or ESC = close. The bound keys of `+aeterna_camera_shutter` and `+aeterna_camera_switch` (no default) also
  work.
- Closing releases focus and returns the player to the game; the phone opens again with the player's own key, so
  phonekit's opening gate (`Config.ask`, devices) always applies.
- While the viewfinder is up the client calls phonekit's client export `activity('media', true)` (battery drain,
  [aeterna_phonekit § Battery](aeterna_phonekit.md#battery)) and `activity('media', false)` on close. The server-local
  `aeterna_phonekit:power` → `(src, { on = false })` (dead battery, device lost) closes the viewfinder and the
  gallery.

## Taking a photo

The server decides whether a photo may be taken and hands out a single-use ticket; the client captures its own
screen and sends the image back with that ticket. This is the ticket model of the private phone the kit is based on,
with a different transport (see "Why this transport" below).

1. The client checks its own cooldown and sends `aeterna_camera:sv:shoot { mode = 'back'|'selfie' }`.
2. The server rate limits and checks that the player has the viewfinder open (it sent `cl:viewfinder` and has not
   seen a close), `Config.cooldownMs`, `Config.perCharacter`, `Config.maxTotalMB`, and that
   `GetResourceState('screenshot-basic') == 'started'`. A refusal sends `cl:shot { ok = false, reason }`.
3. The server draws a ticket (32 lowercase hex, same generator as photo ids), bound to the player's source and
   character key, valid 30 s, one per player (a new ticket replaces the old one), and sends `cl:capture { ticket }`.
4. The client hides the overlay, `DisplayHud(false)`, `DisplayRadar(false)`, waits two frames, and calls the
   **client** export `exports['screenshot-basic']:requestScreenshot({ encoding = 'jpg', quality = Config.quality },
   cb)`. `cb(data)` receives a `data:image/jpeg;base64,` URI on the client; nothing goes over the network yet.
5. The client sends `TriggerLatentServerEvent('aeterna_camera:sv:upload', 200000, { ticket, data })`.
6. The server takes the ticket first (single use: it is gone whatever happens next), and drops the upload when the
   ticket is unknown, expired, or bound to another source or character. Then: `data` longer than
   `ceil(Config.maxBytes * 4 / 3) + 32` is refused before decoding; the prefix must be `data:image/jpeg;base64,`; the
   server decodes it (pure Lua base64 in `shared/logic/`), checks the JPEG start bytes `FF D8 FF`, end bytes `FF D9`
   and `Config.maxBytes`. Anything else is refused with `camera.failed` and a `warn` with the reason (never the data).
7. The server draws a photo id (below), writes `photos/<id>.jpg` with `SaveResourceFile(GetCurrentResourceName(),
   'photos/' .. id .. '.jpg', bytes, #bytes)`, updates the index (§ Storage), sends `cl:shot { ok = true, id }`, a
   toast through `aeterna_notify` ("Photo saved"), and fires `aeterna_camera:saved`.
8. The client restores the HUD and overlay on `cl:shot` or after 10 s, whichever comes first.

### Why this transport (W0 spike, kit-test server on Enhanced, 2026-11-21)

| Path | Result |
| --- | --- |
| Server export `requestClientScreenshot` | No answer, 4 of 4 tries: the client builds its upload URL as `http://` + `GetCurrentServerEndpoint()`, and on Enhanced that call returned `https://127.0.0.1:30150/`, so the URL is malformed |
| Client export `requestScreenshotUpload` to this resource's own `SetHttpHandler` (the private phone's path), with the URL forms `https://<endpoint>`, `http://<host>` and `http://` + raw endpoint | No request reached the server in any form, 2 × 3 tries (10 s each) |
| Client export `requestScreenshot` + `TriggerLatentServerEvent` | **Works**, 2 of 2: capture 78–106 ms, 118 619 and 320 959 characters, valid JPEG (88 945 and 240 702 bytes, 1920 × 1080) |
| `SaveResourceFile` then `LoadResourceFile` of the JPEG | Byte-identical, both times. Writing into a folder that does not exist returns `false` |

Not measured: whether the capture includes NUI frames (the overlay is hidden before every capture either way).

`screenshot-basic` from its repository is a builder resource (yarn + webpack at server start), which Enhanced
refuses. The README tells owners to use a pre-built `dist/` and names the upstream commit tested (5e89d4a).

### Photo id

32 lowercase hex characters (128 bits) from the server's Lua 5.4 `math.random`, mixed with `os.time()` and
`GetGameTimer()` at start, re-drawn on the rare collision. Ids are never sequential and never derived from the
character. They are unguessable to players, not a secret: anyone holding a photo's URL can open it, like an unlisted
link. The README says this.

## Serving (HTTP handler)

`SetHttpHandler` answers under `/aeterna_camera/`:

| Request | Answer |
| --- | --- |
| `GET /aeterna_camera/p/<id>.jpg`, `id` matching `^[0-9a-f]{32}$` and present in the index | `200`, `Content-Type: image/jpeg`, `Cache-Control: private, max-age=86400`, `X-Content-Type-Options: nosniff`, the file's bytes |
| Any other path, method, an id not in the index, a removed photo | `404`, empty body |
| More than 60 requests in 10 s from one remote address | `429`, empty body |

There is no listing, upload or delete endpoint. The handler never builds a file path from anything but a validated
id.

## Gallery

- Opening the Gallery tile closes the phone the same way as Camera and opens this package's own NUI panel, placed
  where the phone was, because a uikit panel spec has no image block. Close or ESC returns to the game.
- The server sends `cl:gallery { items = { {id, ts, mode, bytes}, … } }`, newest first, for the current character.
- Thumbnails and the full view load from `http://<host>/aeterna_camera/p/<id>.jpg`. `<host>` is
  `GetCurrentServerEndpoint()` on the client with any `scheme://` and trailing `/` removed. Measured in the W0 spike:
  the endpoint came back as `https://127.0.0.1:30150/`; the `http://` image loaded inside NUI (1920 × 1080, 36 ms) and
  the `https://` one failed. **Not verified:** a join through the server list or a `cfx.re` link rather than a direct
  connect, which may return a different endpoint form; the smoke covers it when such a server exists.
- Delete: a button in the full view opens a confirm row inside the gallery page itself (Delete / Cancel; ESC =
  Cancel), so no other resource takes focus; on Delete the client sends `sv:delete { id }`.
- The gallery takes focus through `aeterna_core` like the viewfinder. Under core's overlay mode it is paused, not
  closed: it stays on screen, ignores input, and resumes when focus returns (ADR 0005 decision 7).

There is no server → client image transfer. (The spike's attempt to send a photo back over a latent client event
stopped the spike server with exit 139; whether the event or the spike's own encoder caused it was not isolated.)

## Delete

The server checks that the id belongs to the player's current character, then overwrites `photos/<id>.jpg` with an
empty file (`SaveResourceFile` with length 0: the safety rules forbid `os.remove`), removes the id from the index,
frees its bytes from the total, and fires `aeterna_camera:removed`. The handler answers 404 at once. Empty files stay
on disk; the README tells owners they can delete zero-byte files under `photos/` while the server is stopped.

## Hook — forwarding photos elsewhere

The kit itself never calls another host. A server owner's own resource can:

```lua
AddEventHandler('aeterna_camera:saved', function(src, photo)
  -- photo = { id, who, ts, mode, bytes, path = 'photos/<id>.jpg', urlPath = '/aeterna_camera/p/<id>.jpg' }
  local data = LoadResourceFile('aeterna_camera', photo.path)
  -- forward `data` with the owner's own code and capabilities
end)
```

`aeterna_camera:saved` is a server-local event, so only server code on the same server sees it. What the owner's
resource does with the file is outside the kit and outside its `oss.json`.

## Exports (server)

| Export | Returns | Notes |
| --- | --- | --- |
| `getPhoto(id)` | `{ id, who, ts, mode, bytes, path, urlPath }` or nil | |
| `listPhotos(who)` | array of the same, newest first | |
| `removePhoto(id, reason?)` | boolean | For moderation; `reason` ≤ 64 goes into the `removed` event and the log |
| `available()` | boolean | `screenshot-basic` started |

Server-local events: `aeterna_camera:saved` → `(src, photo)` and `aeterna_camera:removed` → `(id, reason)` with
reason `owner` (the player deleted it), `admin`, or the `removePhoto` reason.

## Events (network)

| Event | Direction | Schema | Rate limit |
| --- | --- | --- | --- |
| `aeterna_camera:sv:shoot` | client → server | `{ mode: 'back'|'selfie' }` | 1 / 1000 ms (plus `Config.cooldownMs`) |
| `aeterna_camera:sv:close` | client → server | none | 4 / 1000 ms |
| `aeterna_camera:sv:delete` | client → server | `{ id: string = 32, pattern ^[0-9a-f]+$ }` | 3 / 1000 ms |
| `aeterna_camera:sv:upload` | client → server (latent) | `{ ticket: string = 32, pattern ^[0-9a-f]+$; data: string ≤ ceil(Config.maxBytes × 4 / 3) + 32 }` | 1 / 1000 ms |
| `aeterna_camera:cl:viewfinder` | server → client | `{ count, cap }` | — |
| `aeterna_camera:cl:capture` | server → client | `{ ticket: string = 32 }` | — |
| `aeterna_camera:cl:shot` | server → client | `{ ok: boolean, id?: string, reason?: string ≤ 32 }` | — |
| `aeterna_camera:cl:gallery` | server → client | `{ items: array ≤ 500 }` | — |
| `aeterna_camera:saved` | server-local | see § Hook | — |
| `aeterna_camera:removed` | server-local | `(id, reason)` | — |

The Camera and Gallery tiles open through phonekit's `aeterna_phonekit:app` server-local event.

## NUI messages

Lua → NUI: `aeterna:theme`, `locale`, `vf:show {count, cap, mode}`, `vf:hide`, `vf:mode {mode}`,
`gallery:show {items, base}`, `gallery:removed {id}`, `gallery:hide`.
NUI → Lua callbacks: `close {}`, `open {id}`, `delete {id}`, `escape {}`. Each is validated; `id` must match
`^[0-9a-f]{32}$` and be in the list last sent. Images are set through `img.src` only; text through `textContent`.

## Commands and keys

Permanent names:

- `+aeterna_camera_shutter` / `-aeterna_camera_shutter` — take a photo while the viewfinder is open (key mapping, no
  default key)
- `+aeterna_camera_switch` / `-aeterna_camera_switch` — switch selfie and back camera (key mapping, no default key)
- `aeterna_camera_remove <id>` — console or ACE `aeterna.camera.admin`: removes a photo by id (reason `admin`)

## Storage

Files: `photos/<id>.jpg` in this resource's folder, written only with `SaveResourceFile` on the server.

Server-side resource KVP of `aeterna_camera`, values in JSON:

| Key | Value |
| --- | --- |
| `aeterna_camera:photo:v1:<id>` | `{ who, ts, mode, bytes }` (keyed by photo id, not by player) |
| `aeterna_camera:photos:v1:<who>` | array of ids, newest first, ≤ `Config.perCharacter` |
| `aeterna_camera:total:v1` | integer bytes of all photos |

`<who>` is the character key: `cid:<character id>` or `lic:<license identifier>` (specs README § Names, server
resource KVP keys).

At start the server checks that `total` matches the sum over `photo:v1:*` (via `StartFindKvp`) and corrects it with
one `warn` when it does not. Nothing in client KVP.

## Locale keys

`camera.app.camera`, `camera.app.gallery`, `camera.key.shutter`, `camera.key.switch`, `camera.hint.shutter`,
`camera.hint.switch`, `camera.hint.close`, `camera.saved`, `camera.failed`, `camera.full`, `camera.disk_full`,
`camera.slow`, `camera.unavailable`, `camera.gallery.empty`, `camera.gallery.delete`, `camera.gallery.delete_confirm`,
`camera.admin.usage`, `camera.admin.removed`, `camera.admin.unknown`.

## `oss.json` capabilities

```json
{ "http": [], "commands": [],
  "registeredCommands": ["+aeterna_camera_shutter", "-aeterna_camera_shutter", "+aeterna_camera_switch",
                         "-aeterna_camera_switch", "aeterna_camera_remove"],
  "httpHandlers": ["p/*"],
  "convars": { "read": [], "write": [] },
  "netEvents": { "server": ["aeterna_camera:sv:shoot", "aeterna_camera:sv:close", "aeterna_camera:sv:delete",
                            "aeterna_camera:sv:upload"],
                 "client": ["aeterna_camera:cl:viewfinder", "aeterna_camera:cl:capture", "aeterna_camera:cl:shot",
                            "aeterna_camera:cl:gallery"] },
  "nui": true, "db": { "tables": [], "ddl": false }, "files": { "write": ["photos/*"] } }
```

No HTTP hosts and no convars. `screenshot-basic` and `qbx_core` exports are reached only after `GetResourceState`
says they are started.

### Scanner requirement (W0, plan row #4)

`undeclared-file-write` accepts only a literal `SaveResourceFile` path today
(`packages/devkit/src/safety/rules/undeclared-file-write.js`: "built at runtime — use a literal path"). A photo path
contains a runtime id, so before this package lands the scanner must accept a concatenation whose **first part is a
literal prefix** (`'photos/' .. id .. '.jpg'`) when that prefix matches a declared glob ending in `*` (`photos/*`), and
keep refusing a path whose first part is not literal. The package's own guard (id matches `^[0-9a-f]{32}$`, so no `/`
or `..`) is checked by busted case 2. The change comes with scanner tests for both cases.

## Tests

busted (pure logic in `shared/logic/`):

1. Base64 decode: known vectors, padding, invalid characters refused; JPEG start/end checks; size cap.
2. Id and path guard: generated ids match `^[0-9a-f]{32}$`; the handler router answers 404 for `../`, upper-case hex,
   31 or 33 characters, other extensions, and ids not in the index; 429 after 60 requests in 10 s.
3. Index: add, per-character cap, total cap, delete frees bytes, `total` repair at start.
4. Ownership: delete of another character's id is dropped.
5. Shoot gate: no viewfinder open, cooldown, cap, `screenshot-basic` not started → refused with the right reason and
   no ticket issued.
6. Tickets: single use (a second upload with the same ticket is dropped); expired after 30 s; bound to source and
   character (another source or a switched character is dropped); a new shoot replaces the old ticket; an upload
   over the length cap is refused before decoding.
7. Hook: a successful save fires exactly one `aeterna_camera:saved` with every field.

Smoke (kit-test server):

1. Viewfinder natives on Enhanced: back and selfie, switch, close returns to the game; gamepad and keyboard; a dead
   battery (phonekit `setBattery(src, 0)`) closes the viewfinder.
2. With `screenshot-basic`: take a photo; no overlay, HUD or radar in the image; toast; the counter goes up.
3. Restart the resource and reconnect: the gallery still lists the photo; the file is under `photos/`.
4. Gallery: thumbnails and the full view load over `http://<host>`.
5. Delete: the photo leaves the gallery and its URL answers 404; `aeterna_camera_remove` from the console.
6. A test listener on `aeterna_camera:saved` logs the id and reads the file with `LoadResourceFile`.
7. Stop `screenshot-basic`: the shutter shows the unavailable line; the gallery still works.
8. Screenshots of viewfinder overlay and gallery in all three presets for the owner's visual gate.

## Self-tests (0.2)

| name | kind | players | destructive | expect (eye) | skip-when |
| --- | --- | --- | --- | --- | --- |
| `aeterna_camera.id_and_path_guard` | headless | 1 | n | — | — |
| `aeterna_camera.http_router` | headless | 1 | n | — | — |
| `aeterna_camera.store_roundtrip` | mock | 1 | n | — | — |
| `aeterna_camera.caps` | mock | 1 | n | — | — |
| `aeterna_camera.saved_hook` | mock | 1 | n | — | — |
| `aeterna_camera.screenshot_detect` | headless | 1 | n | — | — |
| `aeterna_camera.viewfinder` | eye | 1 | n | The phone closes and the game camera moves to the phone's view; switching shows your character's face; close returns you to the game with the phone put away | — |
| `aeterna_camera.shoot_and_view` | eye | 1 | y | After the shutter a "Photo saved" toast shows; Gallery lists the new photo first, and it shows the scene without the overlay, HUD or radar | `screenshot-basic` not started |

`http_router` calls the handler's request function with fake request and response objects (the server has no HTTP
capability to call itself). `store_roundtrip`, `caps` and `saved_hook` write a small JPEG generated at run time under
the fake key `test:camera` in place of `<who>`, then remove it with `removePhoto` and restore the index and total before they
report, so the result is MOCK. `shoot_and_view` writes a real photo file and the presser's stored index, so it is destructive (ADR 0005 decision
7) and reports SKIP while `aeterna_core_allow_destructive` is closed; the presser can delete the photo afterwards.

## Done when

All busted cases pass, the scanner change above is merged, `fivem-devkit safety` reports 0 errors and 0 over-declared
items, `check-kit-graph` accepts the edges and the runtime-detected `screenshot-basic`, the smoke steps pass on the
kit-test server, the self-tests report PASS, SKIP or MOCK, and the owner has
passed the screenshots.
