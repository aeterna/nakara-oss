# aeterna_core

Shared foundation for the AETERNA Starter Kit (`aeterna_*` packages): structured logging, a local event bus, Thai-aware UTF-8 text helpers, locale lookup, timezone-aware civil time, payload schema validation, sliding-window rate limiting, ACE permission checks, versioned client KVP storage, key mappings with no default key, the NUI focus lock, the theme override path, and a server self-test runner.

---

## What it does

- **Shared library (`@aeterna_core/import.lua`):** loaded by kit packages via `shared_script '@aeterna_core/import.lua'`, defining the global `AeternaCore` table on both server and client.
- **Client runtime (`client/main.lua`):** coordinates NUI focus across resources (`requestFocus`, `releaseFocus`, `focusOwner`, `aeterna_core:focusLost`) so two panels never fight over `SetNuiFocus`, and exposes `themeHref` for CSS overrides.
- **Server runtime (`server/main.lua`):** runs registered self-tests across kit resources (`addSelftest`, `reportSelftest`, `runSelftests`) via server-local events and the `aeterna_core_selftest` command.
- **Deliberate limits:** `aeterna_core` has no UI page, no database tables, no HTTP calls, and no game or framework logic (it never reads jobs, money, or items).

## Install

1. Download `aeterna_core-<version>.zip` from the [Releases](https://github.com/aeterna/nakara-oss/releases) page and verify it (see below).
2. Extract it into your `resources/` folder so you have `resources/aeterna_core/fxmanifest.lua`.
3. Add to `server.cfg` **before** every other `aeterna_*` resource:

   ```cfg
   setr aeterna_locale en
   setr aeterna_timezone "+00:00"
   ensure aeterna_core
   ```

4. Other resources load the shared API in their `fxmanifest.lua`:

   ```lua
   shared_script '@aeterna_core/import.lua'
   ```

## Config

`aeterna_core` is configured entirely through convars. Use `setr` (replicated) for `aeterna_locale`, `aeterna_timezone`, and `aeterna_theme` so clients receive them. Any value that fails validation falls back to its default and logs one `warn`.

| Convar | Default | Meaning |
|---|---|---|
| `aeterna_locale` | `en` | Active language for kit resources (`th` or `en`) |
| `aeterna_timezone` | `+00:00` | UTC offset used by `AeternaCore.time`, format `±HH:MM` (for example `+07:00`, `-03:30`) |
| `aeterna_theme` | empty | Optional `nui://<resource>/<path>.css` stylesheet override; empty uses each package's own `theme.css` |
| `aeterna_core_log_level` | `info` | Minimum log level: `debug`, `info`, `warn`, or `error` |

## API (`@aeterna_core/import.lua`)

### Logging
- `AeternaCore.log.debug(msg, fields?)`
- `AeternaCore.log.info(msg, fields?)`
- `AeternaCore.log.warn(msg, fields?)`
- `AeternaCore.log.error(msg, fields?)`

Prints `[aeterna_<res>] LEVEL msg key=value …`. Values in `fields` are stringified and cut to 200 visible characters. Messages below `aeterna_core_log_level` are suppressed.

### Event bus (local to one side of one resource)
- `AeternaCore.on(name, fn) -> handle`: wraps `AddEventHandler` on `aeterna_core:bus:<name>`.
- `AeternaCore.off(handle) -> nil`: unregisters the handler.
- `AeternaCore.emit(name, ...) -> nil`: triggers `aeterna_core:bus:<name>` locally without crossing the network.

### Text
- `AeternaCore.text.len(s) -> integer`: counts visible characters; Thai combining marks (`U+0E31`, `U+0E34`–`U+0E3A`, `U+0E47`–`U+0E4E`) count as `0`.
- `AeternaCore.text.cut(s, n) -> string`: cuts to at most `n` visible characters without splitting UTF-8 sequences or leaving a lone combining mark.
- `AeternaCore.text.clean(s, maxLen) -> string`: removes control characters (`U+0000`–`U+001F`, `U+007F`, `U+200B`–`U+200F`, `U+202A`–`U+202E`), trims whitespace, and cuts to `maxLen`.

### Locale
- `AeternaCore.t(key, vars?) -> string`: looks up `key` in `Locales[lang]`, falls back to `Locales.en`, then to `key`. Replaces `{name}` placeholders with `vars.name`.
- `AeternaCore.lang() -> 'th' | 'en'`: returns the active language from `aeterna_locale`.

### Time
- `AeternaCore.time.now() -> integer`: current Unix timestamp in UTC seconds.
- `AeternaCore.time.parts(ts?) -> { year, month, day, hour, min, sec, wday }`: civil date/time in `aeterna_timezone` (`wday` `1` = Sunday … `7` = Saturday).
- `AeternaCore.time.format(ts, pattern) -> string`: formats tokens `YYYY`, `MM`, `DD`, `HH`, `mm`, `ss` (plus `MMMM` and `dddd`/`WWWW` using locale keys `core.month.1`…`12` and `core.wday.1`…`7`).

### Validation
- `AeternaCore.validate(value, schema) -> ok, err, clean`: validates `value` against a plain table schema (`string`, `number`, `boolean`, `table`, `array`). On success returns a cleaned copy where every string has passed through `text.clean` and `maxLen`. On failure returns `false, '<path>: <rule>', nil`.

### Rate limit & ACE (server)
- `AeternaCore.rateLimit(src, key, max, windowMs) -> boolean`: sliding-window rate limit per `(src, key)`. Frees buckets on `playerDropped`.
- `AeternaCore.can(src, action) -> boolean`: checks `IsPlayerAceAllowed(src, action)` where `action` must start with `aeterna.`. Console (`src == 0`) is always allowed.

### Client KVP & Keys (client)
- `AeternaCore.kvp.get(name, version, default) -> any`: reads `aeterna_<pkg>:<name>:v<version>` as JSON; invalid JSON logs one `warn` and returns `default`.
- `AeternaCore.kvp.set(name, version, value) -> nil`: writes JSON up to 16 KB.
- `AeternaCore.kvp.migrate(name, from, to, fn) -> nil`: if `v<from>` exists and `v<to>` does not, converts once with `fn(old)`, writes `v<to>`, and deletes `v<from>`.
- `AeternaCore.key(command, description) -> nil`: calls `RegisterKeyMapping(command, t(description), 'keyboard', '')` with no default key (`command` must start with `+aeterna_`).

## Exports (`aeterna_core`)

### Client exports
| Export | Returns | Description |
|---|---|---|
| `exports.aeterna_core:requestFocus(opts)` | `token` (string) | Acquires NUI focus for `GetInvokingResource()`. `opts = { cursor = true, keyboard = true, keepGameInput = false }` |
| `exports.aeterna_core:releaseFocus(token)` | `boolean` | Releases NUI focus if `token` is the active focus token; stale tokens return `false` |
| `exports.aeterna_core:focusOwner()` | `string \| nil` | Returns the resource name currently holding focus, or `nil` |
| `exports.aeterna_core:themeHref()` | `string \| nil` | Returns `aeterna_theme` when it matches `nui://<resource>/<path>.css`, else `nil` |

### Server exports & command
| Export / Command | Returns | Description |
|---|---|---|
| `exports.aeterna_core:addSelftest(name)` | `string \| nil` | Registers self-test `<resource>.<name>` for the invoking resource |
| `exports.aeterna_core:reportSelftest(runId, name, ok, detail)` | `boolean` | Reports the outcome of `<resource>.<name>` for `runId` |
| `exports.aeterna_core:runSelftests()` | `table` | Runs all registered self-tests with a 5 s timeout and returns `{ { name, ok, detail, ms }, … }` |
| `aeterna_core_selftest` | console output | Server console or players with ACE `aeterna.core.selftest` run all self-tests and print a summary |

### Self-test hooks for package authors (server, 0.2)

| Export / helper / event | Returns / args | Description |
|---|---|---|
| `exports.aeterna_core:selftestMayWrite(runId, name)` | `boolean` | Write guard. `true` only for your in-flight test that is declared `destructive`, in a run whose destructive gate is open. An in-flight test that is not declared destructive gets `false` and becomes FAIL `undeclared destructive`. An unknown run, a test not in flight, or another resource's test gets `false` and nothing changes |
| `AeternaCore.selftest.mayWrite(runId, name)` | `boolean` | The same, from `@aeterna_core/import.lua`; `false` when `aeterna_core` cannot be reached. Call it before any persistent write (KVP, item metadata, files) made inside a test |
| `aeterna_core:selftestStarted` (server-local) | `(runId, name, ctx)` | Fired before a `ped`, `eye`, `side = 'client'` or two-player test is sent to its player(s). `ctx = { kind, side = 'client', a = src, b = src \| nil, destructive }`. Filter on your own name prefix and prepare server state the client test needs. Results still come only from the client report |
| `aeterna_core:selftestEnd` (server-local) | `(runId, name)` | Fired for every test that ends, on any side and for any reason (pass, fail, timeout, owner stopped, player left). Tear down what you prepared |

```lua
AddEventHandler('aeterna_core:selftestStarted', function(runId, name, ctx)
    if name ~= 'aeterna_mypkg.give_item' then return end
    if AeternaCore.selftest.mayWrite(runId, name) then
        -- give the test item to ctx.a
    end
end)
AddEventHandler('aeterna_core:selftestEnd', function(runId, name)
    if name == 'aeterna_mypkg.give_item' then
        -- take the test item back
    end
end)
```

## Focus rules

1. One resource owns NUI focus at a time; the newest `requestFocus` call wins.
2. Ownership is always taken from `GetInvokingResource()`, never from a caller-supplied string.
3. When a new resource preempts focus, the previous owner receives the local client event `aeterna_core:focusLost(owner, token, 'preempted')` and closes its panel.
4. Only the active token can release focus (`releaseFocus(token)`); a stale token returns `false` without touching the new owner's focus.
5. If the owning resource stops, focus is cleared and `aeterna_core:focusLost(owner, token, 'owner_stopped')` is emitted. If `aeterna_core` stops, focus is cleared with reason `'released_by_core'`.

## Support scope

- **Tested on:** FXServer Enhanced (cerulean / `lua54`), standalone or alongside `qbx_core` 1.23+ and `ox_lib` 3.x (`ox_lib` is optional and never required).
- **Supported:** the documented `AeternaCore` API, exports, convars, and focus protocol on unmodified releases from this repository.
- **Not supported:** custom modifications to internal tables, non-UTF-8 locales, or server-side framework bridges inside `aeterna_core`.

---

## ภาษาไทย (Thai)

### ภาพรวม
`aeterna_core` คือไลบรารีพื้นฐานของชุด AETERNA Starter Kit (`aeterna_*`) สำหรับการเขียนล็อก ระบบอีเวนต์ภายใน การจัดการข้อความภาษาไทย (ไม่นับวรรณยุกต์และสระลอยเป็นความยาวตัวอักษรและไม่ตัดกลางลำดับ UTF-8) ระบบแปลภาษา (`th`/`en`) เวลาตามโซนเวลาของเซิร์ฟเวอร์ การตรวจสอบข้อมูลตามโครงสร้าง (schema validation) การจำกัดอัตราการเรียก (rate limit) การตรวจสิทธิ์ ACE การจัดเก็บข้อมูลฝั่งผู้เล่นแบบระบุเวอร์ชัน (KVP) การตั้งค่าปุ่มกดแบบไม่ทับปุ่มเดิม การล็อกโฟกัส NUI และระบบทดสอบตัวเองของเซิร์ฟเวอร์

### การติดตั้ง
1. ดาวน์โหลด `aeterna_core-<version>.zip` จากหน้า Releases และตรวจสอบความถูกต้องของไฟล์
2. แตกไฟล์ไว้ที่ `resources/aeterna_core/fxmanifest.lua`
3. เพิ่มลงใน `server.cfg` ก่อนทรัพยากร `aeterna_*` ตัวอื่นทั้งหมด:

   ```cfg
   setr aeterna_locale th
   setr aeterna_timezone "+07:00"
   ensure aeterna_core
   ```

### การตั้งค่า (Convars)
- `aeterna_locale` (ค่าเริ่มต้น `en`): ภาษาของแพ็กเกจในชุด (`th` หรือ `en`) แนะนำให้ตั้งด้วย `setr`
- `aeterna_timezone` (ค่าเริ่มต้น `+00:00`): โซนเวลาในรูปแบบ `±HH:MM` เช่น `+07:00` ตั้งด้วย `setr`
- `aeterna_theme` (ค่าเริ่มต้น ว่าง): พาธ `nui://<resource>/<path>.css` สำหรับเปลี่ยนธีม ตั้งด้วย `setr`
- `aeterna_core_log_level` (ค่าเริ่มต้น `info`): ระดับการแสดงล็อก (`debug`, `info`, `warn`, `error`)

### กฎการจัดการโฟกัส (NUI Focus)
- มีเพียงหนึ่งทรัพยากรที่เป็นเจ้าของโฟกัส NUI ในแต่ละขณะ โดยคำขอล่าสุดจะได้รับโฟกัสเสมอ
- เมื่อถูกแย่งโฟกัส ทรัพยากรเดิมจะได้รับอีเวนต์ `aeterna_core:focusLost(owner, token, 'preempted')` เพื่อปิดหน้าต่างของตนเองทันที
- การคืนโฟกัสด้วย `releaseFocus(token)` จะสำเร็จเฉพาะเมื่อ `token` ตรงกับผู้ถือโฟกัสปัจจุบันเท่านั้น

---

## Capabilities

What this resource is allowed to do to your server, from [`oss.json`](oss.json). Keep this table in sync
with `oss.json`; widening a capability needs maintainer review.

| Capability | Declared |
|---|---|
| HTTP requests | none |
| `ExecuteCommand` | none |
| Registered commands | `aeterna_core_selftest` |
| Convars read | `aeterna_locale`, `aeterna_timezone`, `aeterna_theme`, `aeterna_core_log_level` |
| Convars written | none |
| Server net events (accepted from clients) | none |
| Client net events (accepted from the server) | none |
| NUI | yes (`SetNuiFocus` / `SetNuiFocusKeepInput` for focus lock) |
| Database tables | none (no DDL) |
| Files written | none |

## Verify before you install

Every release zip is built in CI and carries a build-provenance attestation. Check both the attestation
and the checksum before you put it on your server:

```sh
gh attestation verify aeterna_core-<version>.zip --repo aeterna/nakara-oss --signer-workflow aeterna/nakara-oss/.github/workflows/release.yml
sha256sum -c SHA256SUMS --ignore-missing
```

Then read the capability table above (or `oss.json` inside the zip).

## License

MIT. See [LICENSE](../../LICENSE).
