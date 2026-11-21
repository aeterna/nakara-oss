# aeterna_camera

Camera and Gallery apps inside the AETERNA Starter Kit phone. The Camera is the base game's phone camera (back and selfie) with a thin overlay; photos are taken with `screenshot-basic` when it is started, saved on the server's disk inside this resource's folder, and served by this resource's own HTTP handler ([ADR 0005](../../docs/adr/0005-starter-kit-0-2.md) · [spec](../../docs/specs/aeterna_camera.md)).

แอปกล้องและแกลเลอรีในโทรศัพท์ของชุด AETERNA Starter Kit กล้องใช้กล้องโทรศัพท์ของตัวเกม (กล้องหลังและกล้องหน้า) รูปถ่ายด้วย `screenshot-basic` เมื่อเปิดใช้อยู่ เก็บบนดิสก์ของเซิร์ฟเวอร์ในโฟลเดอร์ของทรัพยากรนี้ และเปิดดูผ่าน HTTP handler ของทรัพยากรนี้เอง

---

## What it does / การทำงาน

- **Camera (กล้อง):** the Camera tile closes the phone and opens the viewfinder. Shutter, switch camera and close come from the base game's phone controls (keyboard and gamepad) and from two key mappings with no default key. The overlay shows key hints and a counter `12 / 60`. / แตะไอคอนกล้องแล้วโทรศัพท์ปิดและเปิดช่องมองภาพ
- **Photos (รูปถ่าย):** the server decides whether a photo may be taken and hands out a single-use ticket (30 s); the client captures its own screen (overlay, HUD and radar hidden) and sends it back as a latent net event. The server checks the ticket first, then the size, the `data:image/jpeg;base64,` prefix, the base64 and the JPEG start and end bytes, and writes `photos/<id>.jpg`. / เซิร์ฟเวอร์ออกตั๋วใช้ครั้งเดียว ผู้เล่นถ่ายหน้าจอตัวเองแล้วส่งกลับ เซิร์ฟเวอร์ตรวจแล้วจึงบันทึก
- **Gallery (แกลเลอรี):** the character's photos, newest first; a full view with Delete and a confirm row (Delete / Cancel, Esc = Cancel). / รูปของตัวละคร ใหม่สุดก่อน ดูเต็มจอและลบได้
- **Without `screenshot-basic` (ไม่มี screenshot-basic):** the viewfinder still works, the shutter shows "Photos are not available on this server", and the gallery still lists saved photos. `screenshot-basic` is detected at run time and is never a dependency. / ช่องมองภาพยังใช้ได้ แต่ถ่ายรูปไม่ได้
- **Deliberate limits (ขอบเขตที่จำกัดไว้):** no video, filters, sending photos in messages, shared or public gallery, extra zoom, or upload to other hosts. The kit never calls another host. / ไม่มีวิดีโอ ฟิลเตอร์ การส่งรูป แกลเลอรีสาธารณะ หรือการอัปโหลดไปที่อื่น

## Install / การติดตั้ง

1. Download `aeterna_camera-<version>.zip` from the [Releases](https://github.com/aeterna/nakara-oss/releases) page and verify it (see below).
2. Extract it into your `resources/` folder so you have `resources/aeterna_camera/fxmanifest.lua`.
3. Start it after its dependencies in `server.cfg`:

   ```cfg
   ensure aeterna_core
   ensure aeterna_uikit
   ensure aeterna_notify
   ensure aeterna_phonekit
   ensure screenshot-basic    # optional, for photos
   ensure aeterna_camera
   add_ace group.admin aeterna.camera.admin allow
   ```

4. `screenshot-basic` from its repository is a builder resource (yarn + webpack at server start), which FiveM Enhanced refuses. Use a pre-built `dist/` of it; the commit tested with this package is upstream `5e89d4a`. / ใช้ `screenshot-basic` ที่ build แล้ว (มีโฟลเดอร์ `dist/`)

**Keep your photos when you upgrade / เก็บรูปไว้เมื่ออัปเกรด:** photos are files under `aeterna_camera/photos/` and their index is in the server's KVP database (FXServer keeps it outside resource folders). Replacing the resource folder deletes the photos: copy `photos/` aside and put it back, and keep the KVP database. / การแทนที่โฟลเดอร์ทั้งหมดจะลบรูป ให้สำรอง `photos/` ไว้ก่อน

**Leftover files / ไฟล์ที่เหลือ:** every deleted photo leaves a zero-byte file under `photos/`, because the safety rules forbid deleting files from Lua. A player can delete at most one photo per `Config.cooldownMs`, so leftovers grow slowly; you may delete zero-byte files there while the server is stopped. / รูปที่ลบแล้วเหลือไฟล์ขนาด 0 ไบต์ทุกครั้ง (ลบได้ครั้งละหนึ่งรูปต่อ `Config.cooldownMs`) ลบไฟล์เหล่านี้ได้ขณะปิดเซิร์ฟเวอร์

## Config / การตั้งค่า

`config.lua` (a missing or out-of-range value falls back to its default with one `warn`):

| Key | Default | Meaning / ความหมาย |
|---|---|---|
| `Config.perCharacter` | `60` | Photos per character, 1–500; at the cap the shutter refuses / จำนวนรูปต่อตัวละคร |
| `Config.maxBytes` | `900000` | Largest accepted photo after decoding, 100 000 – 3 000 000 bytes / ขนาดรูปสูงสุด |
| `Config.maxTotalMB` | `1024` | All photos together; at the cap every shutter refuses and one `warn` is logged per hour / พื้นที่รวมของรูปทั้งหมด |
| `Config.quality` | `0.8` | JPEG quality passed to `screenshot-basic`, 0.5–0.95 / คุณภาพ JPEG |
| `Config.cooldownMs` | `3000` | Minimum time between two shots of one player / ระยะห่างขั้นต่ำระหว่างการถ่าย |

Shared convars read via `aeterna_core`: `aeterna_locale` (`en` or `th`), `aeterna_theme`, `aeterna_theme_preset` (all set with `setr`). This package reads no convar of its own.

## Photo links / ลิงก์รูป

Each photo is served at `http://<server>/aeterna_camera/p/<id>.jpg`, where `<id>` is 32 hex characters. Ids are hard to guess: they are never sequential, never derived from the character, and each draw mixes a seeded generator of its own (tickets and photo ids use separate ones) with `math.random`, a counter, the game timer and `os.clock`. They are not a secret and not cryptographic randomness: **anyone holding a photo's link can open it, like an unlisted link**. There is no listing, upload or delete endpoint. More than 60 requests in 10 s from one address get `429`.

รูปแต่ละรูปเปิดได้ที่ลิงก์ที่มีรหัสสุ่ม 32 ตัวอักษร เดาไม่ได้ แต่ไม่ใช่ความลับ ใครมีลิงก์ก็เปิดดูได้

The gallery loads images from `http://` + the client's `GetCurrentServerEndpoint()` with its scheme and trailing slash removed. A join through the server list or a `cfx.re` link, rather than a direct connect, has not been verified yet.

Thumbnails load the full JPEG of each photo (there are no smaller copies), so a full gallery means one GET per photo. With 60 photos on screen a player sits at the 60-requests-in-10-s limit, and further images in that window answer `429` and stay blank until the gallery is opened again. / รูปย่อโหลดไฟล์ JPEG เต็มขนาด แกลเลอรีที่มีรูปมากอาจชนขีดจำกัด 60 ครั้งใน 10 วินาที

**Gallery position / ตำแหน่งแกลเลอรี:** the gallery opens as a phone-sized panel at the bottom right of the screen. `aeterna_phonekit` exposes no export with the phone's current position, so the gallery does not follow a phone the player moved in the layout editor. / แกลเลอรีเปิดที่มุมขวาล่างเสมอ ไม่ตามตำแหน่งโทรศัพท์ที่ผู้เล่นย้าย

## Exports & Events / การเรียกใช้งาน

Server exports:

| Export | Returns | Notes |
|---|---|---|
| `getPhoto(id)` | `{ id, who, ts, mode, bytes, path, urlPath }` or `nil` | |
| `listPhotos(who)` | array of the same, newest first | `who` = `cid:<citizenid>` with `qbx_core`, else `lic:<license>` |
| `removePhoto(id, reason?)` | boolean | For moderation; `reason` ≤ 64 goes into the `removed` event (default `admin`) |
| `available()` | boolean | `screenshot-basic` is started |

Server-local events: `aeterna_camera:saved` → `(src, photo)` after a photo is saved, and `aeterna_camera:removed` → `(id, reason)` with reason `owner` (the player deleted it), `admin`, or the `removePhoto` reason.

**Forwarding photos elsewhere / ส่งรูปไปที่อื่น:** the kit itself never uploads anywhere. Your own resource can listen and forward the file with its own code and capabilities:

```lua
AddEventHandler('aeterna_camera:saved', function(src, photo)
  -- photo = { id, who, ts, mode, bytes, path = 'photos/<id>.jpg', urlPath = '/aeterna_camera/p/<id>.jpg' }
  local data = LoadResourceFile('aeterna_camera', photo.path)
end)
```

The self-tests `store_roundtrip`, `caps` and `saved_hook` save and remove small test photos under the fake character key `test:camera`, so a listener sees `saved` and `removed` for them; skip `photo.who == 'test:camera'` in a forwarder.

## Commands and keys / คำสั่งและปุ่มลัด

- `+aeterna_camera_shutter` / `-aeterna_camera_shutter` — take a photo while the viewfinder is open, **no default key**
- `+aeterna_camera_switch` / `-aeterna_camera_switch` — switch selfie and back camera, **no default key**
- `aeterna_camera_remove <id>` — console, or players with ACE `aeterna.camera.admin`: removes a photo (reason `admin`)

In the viewfinder the base game's phone controls also work: select = shutter, the selfie control = switch, cancel or Esc = close. / ในช่องมองภาพใช้ปุ่มโทรศัพท์ของตัวเกมได้ด้วย

## Self-tests / การทดสอบในเกม

Registered with `aeterna_core` (run from `aeterna_testkit`): `id_and_path_guard`, `http_router`, `screenshot_detect` (headless), `store_roundtrip`, `caps`, `saved_hook` (mock, test key `test:camera`, restored before they report), `viewfinder` (eye: the test opens the viewfinder, switches to selfie, closes it, then asks) and `shoot_and_view` (eye, destructive, skipped without `screenshot-basic`: the server opens the viewfinder for the presser, the test takes one real photo after core's write guard allows it, then opens the gallery and asks). `shoot_and_view` leaves that photo in the presser's gallery; they can delete it afterwards.

## Support scope / ขอบเขตการรองรับ

- **Tested on / ทดสอบบน:** busted specs only so far; the kit-test FXServer smoke steps in the spec have not been run yet. Which viewfinder natives work on FiveM Enhanced is not verified. / ยังทดสอบด้วย busted เท่านั้น
- **Supported / รองรับ:** FiveM servers running `aeterna_core`, `aeterna_uikit`, `aeterna_notify` and `aeterna_phonekit`; photos with a pre-built `screenshot-basic`; character keys from `qbx_core` when started; Thai and English.
- **Not supported / ไม่รองรับ:** photos without `screenshot-basic`; photo storage outside this resource's folder.

## Capabilities

What this resource is allowed to do to your server, from [`oss.json`](oss.json). Keep this table in sync with `oss.json`; widening a capability needs maintainer review.

| Capability | Declared |
|---|---|
| HTTP requests | none |
| HTTP handler | `p/*` (GET `/aeterna_camera/p/<id>.jpg` only) |
| `ExecuteCommand` | none |
| Registered commands | `+aeterna_camera_shutter`, `-aeterna_camera_shutter`, `+aeterna_camera_switch`, `-aeterna_camera_switch`, `aeterna_camera_remove` |
| Convars read | none |
| Convars written | none |
| Server net events (accepted from clients) | `aeterna_camera:sv:shoot`, `aeterna_camera:sv:close`, `aeterna_camera:sv:delete`, `aeterna_camera:sv:upload` |
| Client net events (accepted from the server) | `aeterna_camera:cl:viewfinder`, `aeterna_camera:cl:capture`, `aeterna_camera:cl:shot`, `aeterna_camera:cl:gallery` |
| NUI | yes |
| Database tables | none (no DDL) |
| Files written | `photos/*` (this resource only) |

## Verify before you install

Every release zip is built in CI and carries a build-provenance attestation. Check both the attestation and the checksum before you put it on your server:

```sh
gh attestation verify aeterna_camera-<version>.zip --repo aeterna/nakara-oss --signer-workflow aeterna/nakara-oss/.github/workflows/release.yml
sha256sum -c SHA256SUMS --ignore-missing
```

Then read the capability table above (or `oss.json` inside the zip).

## Tests

From the repository root:

```sh
busted --config-file=.busted packages/camera/spec
```

## License

MIT. See [LICENSE](../../LICENSE). Bundled Lucide icon SVGs are ISC-licensed and the IBM Plex Sans Thai font is OFL-1.1; see [NOTICE](NOTICE).
