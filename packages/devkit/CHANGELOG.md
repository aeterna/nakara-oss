# Changelog

## 0.1.2

- `busted`: expand FiveM native stubs with client/server KVP storage (`GetResourceKvp*`, `SetResourceKvp*`, `DeleteResourceKvp`), persistent statebags (`Entity(h).state` with `:set()`), routing buckets (`Get/SetPlayerRoutingBucket`, `Get/SetEntityRoutingBucket`), and world entity inspection stubs (`DoesEntityExist`, `GetEntityCoords`, `GetEntityHealth`, `GetEntityModel`, `GetAllVehicles`, `GetAllPeds`, `GetVehicle*`, `Network*`).

## 0.1.1

- `nui-escape`: add `extraDirs` option to scan non-manifest directories (e.g. server overrides).

## 0.1.0

- Initial public release: `check` (9 static checks), `safety` scanner with `oss.json` capability
  enforcement, busted harness.
