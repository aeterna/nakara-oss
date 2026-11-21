# aeterna_loading

A loading screen that shows what is actually happening while a player joins: the map loading, the scripts starting (with a percentage), and the wait for their character. Part of the AETERNA Starter Kit 0.2 ([ADR 0005](../../docs/adr/0005-starter-kit-0-2.md) · [spec](../../docs/specs/aeterna_loading.md)).

หน้าจอโหลดที่บอกผู้เล่นว่ากำลังเกิดอะไรขึ้นจริงระหว่างเข้าเซิร์ฟเวอร์ ได้แก่ โหลดแผนที่ เริ่มสคริปต์ (พร้อมเปอร์เซ็นต์) และรอตัวละคร แสดงชื่อเซิร์ฟเวอร์ ภาพพื้นหลัง และเคล็ดลับที่หมุนเวียน ทั้งหมดตั้งค่าจากไฟล์ในโฟลเดอร์ของ resource นี้

---

## What it does / การทำงาน

- **Real stages (ขั้นตอนจริง):** Map (data file entries), Scripts (init functions, as a whole percentage; FiveM's `loadFraction` is used when it is higher) and Character (from this resource's client script once the game session starts). A finished stage gets a check mark; the current one shows its percentage as text and as a bar, so it reads without colour. A stage never goes back and a percentage never decreases. After 20 s with no message the page adds "Still loading" instead of a spinner that pretends progress.
- **Closing (การปิดหน้าจอ):** usually the framework's character screen closes the page. Otherwise the client script closes it on `playerSpawned`, or `shutdown.fallbackSeconds` after the session started, and only while the loading screen is still active, so it never interferes with a framework that already closed it.
- **Owner text (ข้อความของเจ้าของเซิร์ฟเวอร์):** server name, tagline, tips, language, preset, background and audio come from `html/config.json`. A bad field falls back to its default (the page never goes blank) and the server console shows one `warn` per bad field.
- **Audio (เสียง):** off unless `audio.src` is set. With `autoplay: false` (the default) nothing plays until the player presses the audio button; the button toggles mute either way. Audio fades out over 1 s when this resource closes the page.
- **Reduced motion:** `prefers-reduced-motion` stops the tip cross-fade and the bar animation. It does not affect audio.
- **Deliberate limits (ขอบเขตที่จำกัดไว้):** no video backgrounds, no remote images or music, no player count or queue position, no links that open a browser, no mini-game. The page never requests anything outside this resource.

## Install / การติดตั้ง

1. Download `aeterna_loading-<version>.zip` from the [Releases](https://github.com/aeterna/nakara-oss/releases) page and verify it (see below).
2. Extract it into your `resources/` folder so you have `resources/aeterna_loading/fxmanifest.lua`.
3. Add it to `server.cfg`. The order among other `ensure` lines does not matter, and it does not need `aeterna_core`:

   ```cfg
   ensure aeterna_loading
   ```

Only one resource on a server should declare `loadscreen`; remove or stop any other loading screen resource.
เซิร์ฟเวอร์หนึ่งควรมี resource ที่ประกาศ `loadscreen` เพียงตัวเดียว ให้ถอดหรือหยุดหน้าจอโหลดตัวอื่นออก

## Config / การตั้งค่า

The page runs before any client script, so it cannot read convars or other resources. Everything is set inside this resource's folder.
หน้าจอโหลดทำงานก่อนสคริปต์ฝั่งผู้เล่นทุกตัว จึงอ่าน convar หรือไฟล์ของ resource อื่นไม่ได้ การตั้งค่าทั้งหมดอยู่ในโฟลเดอร์ของ resource นี้

`html/config.json`:

| Key | Default | Limit | Meaning / ความหมาย |
|---|---|---|---|
| `serverName` | `My Server` | 1–40 characters | Large title / ชื่อเซิร์ฟเวอร์ตัวใหญ่ |
| `tagline` | empty | ≤ 80, may be empty | Line under the title / บรรทัดใต้ชื่อ |
| `lang` | `en` | `th` · `en` | Language of the page's own strings / ภาษาของข้อความบนหน้าจอ |
| `preset` | `asphalt` | `asphalt` · `paper` · `night-market` | Theme preset / ชุดสี |
| `background` | empty | ≤ 120, relative path inside `html/`, ends in `.jpg`, `.png` or `.webp` | Empty = the preset's colour with a soft gradient / ว่าง = สีพื้นของชุดสี |
| `tips` | one key-binding tip | ≤ 30 items, each 1–160 characters | Shown in order; an empty list hides the tip line / เคล็ดลับ แสดงตามลำดับ |
| `tipSeconds` | `8` | 4–30 | Seconds per tip / วินาทีต่อเคล็ดลับ |
| `audio.src` | empty | ≤ 120, relative path inside `html/`, ends in `.ogg` or `.mp3` | Empty = no audio / ว่าง = ไม่มีเสียง |
| `audio.autoplay` | `false` | boolean | `true` plays as soon as the page opens / `true` เล่นทันทีที่เปิดหน้า |
| `audio.volume` | `0.3` | 0–1 | |
| `shutdown.fallbackSeconds` | `30` | 10–120 | Close the page this long after the session started if nothing else did / ปิดหน้าจอเองหลังเซสชันเริ่มเมื่อไม่มีใครปิด |

A path that starts with `/`, contains `..`, `:` or `//`, or has another extension is refused.

### What you can customise / ปรับแต่งอะไรได้บ้าง

| Want | Do |
|---|---|
| Name, tagline, tips, language, preset, audio | Edit `html/config.json` |
| Background image | Put the image under `html/custom/` and set `background` to `custom/<file>` |
| Colours, fonts, spacing beyond the presets | Edit `html/custom.css` (loaded after `theme.css`), for example `:root, :root[data-preset] { --accent: #c2410c; }` (the second selector makes the override beat a preset) |
| A font | Put an OFL `.woff2` and its licence under `html/custom/` and add an `@font-face` in `custom.css` |
| Wording of the stages | Edit `html/locale.json` (`th` and `en` blocks) |

**Keep across upgrades / เก็บไว้ตอนอัปเกรด:** `html/config.json`, `html/custom.css` and `html/custom/`. Do not edit `html/theme.css`; it is the same file in every kit package and an upgrade replaces it.

## Exports & Events / การเรียกใช้งาน

None. Other resources do not talk to the loading screen, and nothing goes over the network. The client script sends only these messages to its own page with `SendLoadingScreenMessage`: `{ type: 'aeterna_loading:stage', stage: 'character' }` and `{ type: 'aeterna_loading:closing' }`.

## Commands and keys / คำสั่งและปุ่มลัด

None.

## Support scope / ขอบเขตการรองรับ

- **Tested on / ทดสอบบน:** busted and `node --test` only so far. The live smoke steps on FXServer Enhanced (which loadscreen messages arrive, closing with and without `qbx_core`) are not done yet.
- **Supported / รองรับ:** standalone servers and Qbox/QBCore/ESX servers, with or without `aeterna_core`, Thai and English page strings.
- **Not supported / ไม่รองรับ:** remote images, video or audio, theming through `aeterna_theme` (the page runs before convars can be read), more than one loading screen resource on a server.

## Capabilities

What this resource is allowed to do to your server, from [`oss.json`](oss.json). Keep this table in sync with `oss.json`; widening a capability needs maintainer review.

| Capability | Declared |
|---|---|
| HTTP requests | none |
| `ExecuteCommand` | none |
| Registered commands | none |
| Convars read | none |
| Convars written | none |
| Server net events (accepted from clients) | none |
| Client net events (accepted from the server) | none |
| NUI | yes (`loadscreen` page, `SendLoadingScreenMessage`, `ShutdownLoadingScreenNui`) |
| Database tables | none (no DDL) |
| Files written | none |

## Verify before you install

Every release zip is built in CI and carries a build-provenance attestation. Check both the attestation and the checksum before you put it on your server:

```sh
gh attestation verify aeterna_loading-<version>.zip --repo aeterna/nakara-oss --signer-workflow aeterna/nakara-oss/.github/workflows/release.yml
sha256sum -c SHA256SUMS --ignore-missing
```

Then read the capability table above (or `oss.json` inside the zip).

## Tests

From the repository root:

```sh
busted --config-file=.busted packages/loading/spec
node --test packages/loading/spec/
```

## License

MIT. See [LICENSE](../../LICENSE). Bundled Lucide icon SVGs are ISC-licensed and the IBM Plex Sans Thai font is OFL-1.1; see [NOTICE](NOTICE).
