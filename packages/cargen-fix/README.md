# nakara_cargen_fix

A guard against this client-log spam, and the `net.dll` crash it can escalate to:

```
CNetworkCarGenWorldStateData Pool Full, Size == 100   (crash_hash net.dll+487A2)
```

…plus the two facts we wish we had known first: the popular `GAMECONFIG_FILE` "fix" does nothing, and the
obvious way to call the native **causes** the overflow. Client-only, framework-independent, no
configuration required.

> **Read [What we have verified](#what-we-have-verified) before relying on it.** We have proven that this
> resource does not fill the pool itself. We have **not** been able to reproduce the vanilla overflow it
> guards against, so we cannot yet claim it fixes that case.

## The problem

`CNetworkCarGenWorldStateData` is a network pool with a fixed size of 100. On OneSync servers whose map has
more than 100 vehicle generators (the game's ambient *parked* cars), the pool can fill up and the client
logs the line above repeatedly. When it happens during a disconnect, an ordinary "connection lost" can
escalate into a `net.dll` crash dump.

## Why the popular `GAMECONFIG_FILE` overlay does nothing

A widely shared fix is a partial gameconfig overlay that claims to raise the pool from 100 to 1000:

```lua
data_file 'GAMECONFIG_FILE' 'gameconfig.meta'
```

It is a silent no-op. Every client logs this on connect, and the pool is never touched:

```
Could not add data_file resources:/<resource>/gameconfig.meta - invalid type GAMECONFIG_FILE
```

Why, checked against the CitizenFX source and the official references:

- FiveM's `LookupDataFileType` (`gta-streaming-five/src/LoadStreamingFile.cpp` in
  [citizenfx/fivem](https://github.com/citizenfx/fivem)) resolves a `data_file` type by hashing the
  upper-cased name and matching it against the native RAGE data-file-type enum only. FiveM registers no
  `GAMECONFIG_FILE` type (a full-tree search of `citizenfx/fivem` finds none), and it is not in the
  [data-files reference](https://docs.fivem.net/docs/game-references/data-files/). The type is invalid on
  every game build, so no mounter is ever found.
- `CNetworkCarGenWorldStateData` cannot be raised by any supported mechanism. It is not in the base
  `common/data/gameconfig.xml` `<PoolSizes>` (it is a hardcoded network world-state pool), and it is not on
  the [`increase_pool_size`](https://docs.fivem.net/docs/server-manual/server-commands/#increase_pool_size)
  allow-list.

Because the pool size is fixed at 100, the only fix is to stop creating networked car-generator world state.

## What it does

On spawn, and again every 5 seconds (the engine re-enables generators on zone changes and respawns), each
client calls:

```lua
SetAllVehicleGeneratorsActiveInArea(<whole map>, false --[[bActive]], false --[[bNetworked]])
```

This disables vehicle generators (ambient parked cars) map-wide, locally, so no
`CNetworkCarGenWorldStateData` is allocated. Player- and script-spawned vehicles (dealerships, garages,
job vehicles) are not generators and are unaffected. When the resource stops it restores the vanilla
(active) state, so a restart does not leave generators switched off.

It does not delete parked cars that already exist. If you want those gone too, do it in your traffic or
density resource (for example `SetParkedVehicleDensityMultiplierThisFrame(0.0)` every frame).

### The last argument is `bNetworked`, and it must stay `false`

This native has no "instantly" parameter. Passing `true` as the 8th argument publishes the change as
network world state and allocates one `CNetworkCarGenWorldStateData` slot per call, so a call on a timer
fills the 100-slot pool by itself and the fix becomes the bug. This has happened: a version that passed
`true` (with the parameter misnamed `bInstantly` in a comment) brought the `Pool Full` spam back, with the
log lines spaced exactly at the re-assert interval. With `false` the call is purely local and the interval
does not matter. `spec/cargen_fix_spec.lua` fails if any call passes anything other than the literal `false`.

## What we have verified

All on one live OneSync server, with the defaults in this repo.

| Claim | Evidence | Status |
|---|---|---|
| Passing `bNetworked = true` on a timer fills the pool by itself | client crash dump: 1,270 `Pool Full` lines, 423 of them exactly 5,000 ms apart — the re-assert interval of a version that passed `true` | ✅ observed (game build: Legacy) |
| This resource (`bNetworked = false`) does not allocate from the pool | busted spec pins the literal `false` in every call; live, 2.3 minutes with relief **on** (right after the 10.7-minute relief-off run below) with no `Pool Full` | ✅ spec · ⚠️ short live run (Enhanced / gen9) |
| `data_file 'GAMECONFIG_FILE'` is a no-op | CitizenFX source + the client log line above | ✅ verified (every build) |
| Disabling generators prevents the **vanilla** overflow | A/B test with relief **off**: 10.7 minutes driving with ~80 parked cars within 150 m, single player — **no `Pool Full` appeared**, so there was nothing to prevent | ⚠️ **not reproduced** — Enhanced, 1 player. Legacy and busy multi-player sessions not yet tested |

If you can reproduce the vanilla overflow, please open an issue with your game build, player count and
the A/B result from the exports below — that is the missing evidence.

## Install

1. Download `nakara_cargen_fix-<version>.zip` from the
   [Releases](https://github.com/aeterna/nakara-oss/releases) page and verify it (see below).
2. Extract it into your `resources/` folder so you have `resources/nakara_cargen_fix/fxmanifest.lua`.
3. Add to `server.cfg`:

   ```
   ensure nakara_cargen_fix
   ```

4. Remove any `data_file 'GAMECONFIG_FILE'` overlay you added for this problem; it never worked.

Ensure order does not matter (this is not a boot-time gameconfig override). To check it on your server,
drive through dense areas for about 15 minutes, die and respawn, and watch the client console (F8): there
should be no `CNetworkCarGenWorldStateData Pool Full` line and no `invalid type GAMECONFIG_FILE` line. To
see whether your server suffers the vanilla overflow at all, use the A/B exports below.

## Config

`config.lua` (optional; the defaults are what the resource was tested with):

| Key | Default | Meaning |
|---|---|---|
| `Config.Area` | `{ -20000.0, -20000.0, -2000.0, 20000.0, 20000.0, 5000.0 }` | box (x1, y1, z1, x2, y2, z2) where generators are disabled; invalid values fall back to the default |
| `Config.ReassertMs` | `5000` | re-apply interval in ms; values below `1000` fall back to the default |

`bNetworked` is not configurable.

## Client exports (for testing)

Both are client-side and affect **only the client that calls them** — nothing is synced.

| Export | What it does |
|---|---|
| `exports.nakara_cargen_fix:setRelief(false)` | restore vanilla generators and stop re-asserting — use it to reproduce the overflow as a baseline |
| `exports.nakara_cargen_fix:setRelief(true)` | disable generators again immediately and resume the loop |
| `exports.nakara_cargen_fix:isRelief()` | `true` while relief is active |

Relief is never persisted: every start of the resource begins with relief on. A typical A/B test:
call `setRelief(false)`, drive through busy parking areas with F8 open until `Pool Full` appears, then
`setRelief(true)` and confirm the line stops.

## Compatibility

- Framework-independent (no dependency on ESX, QBCore, Qbox or ox_lib); client-side natives only.
- The overflow was observed on a OneSync server; behaviour without OneSync has not been tested.
- The `GAMECONFIG_FILE` analysis above applies to every game build. For what the resource itself has
  been verified to do, and on which build, see [What we have verified](#what-we-have-verified).

## Capabilities

What this resource is allowed to do to your server, from [`oss.json`](oss.json):

| Capability | Declared |
|---|---|
| HTTP requests | none |
| `ExecuteCommand` | none |
| Registered commands | none |
| Convars read | none |
| Convars written | none |
| Server net events (accepted from clients) | none |
| Client net events (accepted from the server) | none |
| NUI | no |
| Database tables | none (no DDL) |
| Files written | none |

## Verify before you install

Every release zip is built in CI and carries a build-provenance attestation. Check both the attestation
and the checksum before you put it on your server:

```sh
gh attestation verify nakara_cargen_fix-<version>.zip --repo aeterna/nakara-oss --signer-workflow aeterna/nakara-oss/.github/workflows/release.yml
sha256sum -c SHA256SUMS --ignore-missing
```

Then read the capability table above (or `oss.json` inside the zip): this resource should declare nothing.

## Tests

From the repository root: `busted --config-file=.busted` (see
[`packages/devkit/busted/README.md`](../devkit/busted/README.md)).

## License

MIT. See [LICENSE](../../LICENSE).
