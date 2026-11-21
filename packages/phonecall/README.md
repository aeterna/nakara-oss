# aeterna_phonecall

Phone numbers, text messages and voice calls for the AETERNA Starter Kit, as two apps inside `aeterna_phonekit`: **Phone** (dialer, recent calls, in-call screen) and **Messages** (threads and compose). It ships no phone of its own; every screen is drawn by phonekit ([ADR 0005](../../docs/adr/0005-starter-kit-0-2.md) · [spec](../../docs/specs/aeterna_phonecall.md)).

เบอร์โทรศัพท์ ข้อความ และการโทรด้วยเสียงสำหรับชุด AETERNA Starter Kit เป็นแอปสองตัวในโทรศัพท์ของ `aeterna_phonekit`: **โทรศัพท์** (หน้าโทร การโทรล่าสุด หน้าระหว่างคุย) และ **ข้อความ** (ห้องสนทนาและเขียนข้อความใหม่) แพ็กเกจนี้ไม่มีหน้าจอของตัวเอง phonekit เป็นผู้วาดทุกหน้า

---

## What it does / การทำงาน

- **Numbers (เบอร์):** a character gets a number in `Config.number.format` the first time it opens either app (or when it loads, with `assign = 'on_load'`). The number stays with the character; numbers compare by digits only, so `5550142` and `555-0142` are the same. / ตัวละครได้เบอร์ครั้งแรกที่เปิดแอป เบอร์อยู่กับตัวละครถาวร เทียบเฉพาะตัวเลข
- **Messages (ข้อความ):** one line of up to `Config.sms.maxLen` visible characters, written into the sender's and the recipient's lists whether the recipient is online or not. An online recipient gets a phonekit toast and a badge. / ส่งถึงผู้รับแม้ออฟไลน์ ผู้รับที่ออนไลน์ได้แจ้งเตือนและตัวเลขบนไอคอน
- **Calls (การโทร):** ringing, active, ended. The callee sees phonekit's ring screen (cover, lock screen, full card, or a toast when the phone is put away) and can also answer with a key. A call to a player already in a call ends `busy`. / ผู้รับเห็นหน้าจอสายเรียกเข้าของ phonekit และรับสายด้วยปุ่มได้
- **Contacts (รายชื่อ):** phonekit's Contacts app stays the only contact list. Its Call and Message buttons open this package's dialer and thread; a thread with an unknown number offers "Save contact". / ปุ่มโทรและส่งข้อความในรายชื่อเปิดแอปของแพ็กเกจนี้
- **Deliberate limits (ขอบเขตที่จำกัดไว้):** no group calls, voicemail, pictures, short codes, call recording, player phone book or message search. / ไม่มีโทรกลุ่ม ฝากข้อความเสียง รูปภาพ หรือค้นหาข้อความ

## Voice / ระบบเสียง

The server picks the backend once at start from the `gamename` convar:

| `gamename` | Backend | Calls work when |
|---|---|---|
| `gta5enhanced` | FXServer's own server-side voice channels (one mode-0 channel per call: both players hear each other across the map) | the voice-channel natives exist (checked at start) |
| anything else (Legacy) | `pma-voice` call channels (`setPlayerCall`, channels `Config.call.channelBase + 1` … `+ 9999`) | `pma-voice` is started |

- On Enhanced this package never calls `pma-voice`, started or not: Enhanced has no Mumble, so `pma-voice`'s call targets carry no audio there. / บน Enhanced ไม่เรียก pma-voice เลย
- `pma-voice` is never a dependency. Without a backend (Legacy without `pma-voice`), numbers and messages still work, the dialer shows "Calls are not available on this server", and the call self-tests report SKIP.
- `pma-voice`'s `setPlayerCall` does nothing when the server sets `voice_enableCalls 0`.
- If `pma-voice` stops during a call on Legacy, the call ends with reason `voice_off`.
- **Untested:** the `pma` path has not been run in game; the kit-test server runs Enhanced only. / เส้นทาง pma-voice ยังไม่ได้ทดสอบในเกม

## Install / การติดตั้ง

1. Download `aeterna_phonecall-<version>.zip` from the [Releases](https://github.com/aeterna/nakara-oss/releases) page and verify it (see below).
2. Extract it into your `resources/` folder so you have `resources/aeterna_phonecall/fxmanifest.lua`.
3. Start it after phonekit in `server.cfg`, and give admins the ACE for the number commands:

   ```cfg
   ensure aeterna_core
   ensure aeterna_uikit
   ensure aeterna_notify
   ensure aeterna_phonekit
   ensure pma-voice           # Legacy only, optional, for calls (Enhanced does not need it)
   ensure aeterna_phonecall
   add_ace group.admin aeterna.phonecall.admin allow
   ```

4. Players bind keys in **Settings → Key Bindings → FiveM → "Answer a phone call"** and **"Decline or end a phone call"**. There is no default key. / ผู้เล่นตั้งปุ่มเอง ไม่มีปุ่มตั้งต้น

## Config / การตั้งค่า

`config.lua`:

| Key | Default | Meaning / ความหมาย |
|---|---|---|
| `Config.number.format` | `'555-####'` | `#` = a random digit, any other character is literal. At least 4 `#`, at most 20 characters; anything else falls back to the default with one `error` / `#` คือตัวเลขสุ่ม |
| `Config.number.reserved` | `{ '555-0000', '555-0911' }` | Never assigned / ไม่แจกให้ใคร |
| `Config.number.assign` | `'first_open'` | `first_open`: the first time either app opens · `on_load`: when the character loads |
| `Config.sms.maxLen` | `160` | Visible characters per message (Thai counts per character), 1–300 |
| `Config.sms.keep` | `100` | Messages kept per character, in and out together; the oldest leave first. 10–100 |
| `Config.call.ringSeconds` | `30` | Ringing without an answer becomes `missed`; 5–60 (phonekit's ring card ends after 60 s) |
| `Config.call.maxMinutes` | `60` | An active call ends with reason `limit` |
| `Config.call.channelBase` | `20000` | Legacy only: first `pma-voice` call channel this package uses |
| `Config.recentCalls` | `30` | Call log entries kept per character |

A value out of range falls back to its default with one `warn`. Shared convar read via `aeterna_core`: `aeterna_locale` (`en` or `th`).

## Storage / ที่เก็บข้อมูล

Server-side resource KVP of `aeterna_phonecall`, keyed by character (`cid:<citizenid>` with `qbx_core`, else `lic:<license>`). Nothing is stored on the client, and there are no database tables. Message bodies are sent only to their two parties.

| Key | Value |
|---|---|
| `aeterna_phonecall:number:v1:<who>` | `{ number }` |
| `aeterna_phonecall:owner:v1:<digits>` | `<who>` (number → holder) |
| `aeterna_phonecall:sms:v1:<who>` | message records, at most `Config.sms.keep` |
| `aeterna_phonecall:calls:v1:<who>` | `{ peer, dir, result, ts, seconds }`, at most `Config.recentCalls` |

If a write fails, the oldest entries are dropped until it fits and one `warn` is logged. The server KVP value limit has not been measured yet; the largest value (100 Thai messages of 160 characters) is about 60 KB of JSON.

## Exports & Events / การเรียกใช้งาน

### Server exports

| Export | Returns | Description |
|---|---|---|
| `exports.aeterna_phonecall:getNumber(src)` | string or nil | The player's current number (assigns one with `assign = 'on_load'`) |
| `exports.aeterna_phonecall:findByNumber(number)` | src or nil | Online player holding that number (digits compared) |
| `exports.aeterna_phonecall:sendSms(fromLabel, toNumber, body)` | `true` or `false, err` | A message from a service (a bank, a job). `fromLabel` ≤ 24, shown as a service message with no reply box. 30 / 60 s per calling resource |
| `exports.aeterna_phonecall:endCall(src, reason?)` | boolean | Ends the player's call; `reason` defaults to `hangup` |
| `exports.aeterna_phonecall:callState(src)` | `{ state, peerNumber, since }` or nil | `state` as that player sees it: `dialing`, `ringing` or `active`; `since` in Unix seconds |

### Server-local events

```lua
AddEventHandler('aeterna_phonecall:sms', function(from, toNumber, info)
    -- from = sender number or service label; info = { id, ts }; the body is not included
end)

AddEventHandler('aeterna_phonecall:call', function(callId, state, info)
    -- state = 'dialing' | 'active' | 'ended'; info = { from = number, to = number, reason? }
end)
```

End reasons: `hangup`, `declined`, `missed`, `busy`, `unavailable`, `dropped`, `limit`, `voice_off`.

## Commands and keys / คำสั่งและปุ่มลัด

- `+aeterna_phonecall_answer` / `-aeterna_phonecall_answer` — answer a ringing call (key mapping, **no default key**)
- `+aeterna_phonecall_hangup` / `-aeterna_phonecall_hangup` — decline a ringing call or end the current call (key mapping, **no default key**)
- `aeterna_phonecall_number <serverId>` — console or ACE `aeterna.phonecall.admin`: prints that player's number in the server console
- `aeterna_phonecall_setnumber <serverId> <number>` — console or ACE `aeterna.phonecall.admin`: sets the number if it matches `Config.number.format` (formatted or digits only) and is free; the old number is freed at once

## Self-tests / การทดสอบตัวเอง

Registered with `aeterna_core` and run from `aeterna_testkit`: `number_format`, `voice_detect`, `voice_channel` and `sms_rate_limit` (headless), `number_unique` and `sms_store_cap` (mock, on the fake keys `test:a` and `test:b`, deleted before they report), `my_number` (eye), `sms_ab` (eye, two players, destructive: writes one real "Self-test" message into A's and B's lists, so it runs only while `aeterna_core_allow_destructive` is open), `call_ab` (eye, two players) and `call_busy` (ped, two players). The call tests skip without a voice backend.

## Support scope / ขอบเขตการรองรับ

- **Tested on / ทดสอบบน:** busted specs only so far (pure logic and the server scripts against the devkit harness); the kit-test FXServer smoke steps in the spec have not been run yet. / ยังทดสอบด้วย busted เท่านั้น ยังไม่ได้ทดสอบบนเซิร์ฟเวอร์จริง
- **Supported / รองรับ:** FiveM Enhanced (voice channels) and Legacy with `pma-voice`; `qbx_core` characters or license identifiers; Thai and English.
- **Not supported / ไม่รองรับ:** a phone shell of its own, group calls, the `pma` path verified in game.

## Capabilities

What this resource is allowed to do to your server, from [`oss.json`](oss.json). Keep this table in sync with `oss.json`; widening a capability needs maintainer review.

| Capability | Declared |
|---|---|
| HTTP requests | none |
| `ExecuteCommand` | none |
| Registered commands | `+aeterna_phonecall_answer`, `-aeterna_phonecall_answer`, `+aeterna_phonecall_hangup`, `-aeterna_phonecall_hangup`, `aeterna_phonecall_number`, `aeterna_phonecall_setnumber` |
| Convars read | `gamename` (server, once at start) |
| Convars written | none |
| Server net events (accepted from clients) | `aeterna_phonecall:sv:names`, `aeterna_phonecall:sv:answer`, `aeterna_phonecall:sv:hangup` |
| Client net events (accepted from the server) | `aeterna_phonecall:cl:state`, `aeterna_phonecall:cl:askNames`, `aeterna_phonecall:cl:saveContact` |
| NUI | no |
| Database tables | none (no DDL) |
| Files written | none |

`pma-voice` and `qbx_core` exports are reached only after `GetResourceState` says they are started. The voice-channel natives are FXServer server natives called by name.

## Verify before you install

Every release zip is built in CI and carries a build-provenance attestation. Check both the attestation and the checksum before you put it on your server:

```sh
gh attestation verify aeterna_phonecall-<version>.zip --repo aeterna/nakara-oss --signer-workflow aeterna/nakara-oss/.github/workflows/release.yml
sha256sum -c SHA256SUMS --ignore-missing
```

Then read the capability table above (or `oss.json` inside the zip).

## Tests

From the repository root:

```sh
busted --config-file=.busted packages/phonecall/spec
```

## License

MIT. See [LICENSE](../../LICENSE).
