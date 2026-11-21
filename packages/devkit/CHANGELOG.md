# Changelog

## Unreleased

- `safety`: count the fxmanifest `loadscreen` key as NUI use, and accept `SaveResourceFile` paths built from a literal prefix covered by a `files.write` glob (e.g. `'photos/' .. id .. '.jpg'` with `photos/*`).
- `safety`: add the optional `capabilities.httpHandlers` field and the `undeclared-http-handler` rule for `SetHttpHandler`; unused entries are reported as `over-declared`.
- `safety`: add the `font-assets` rule enforcing that fonts under `packages/*` live only as `.woff2` in `packages/<pkg>/html/fonts/` with `OFL.txt` in the same folder and at most 1 MB of fonts per package, and rejecting `.ttf`/`.otf`/`.woff`/`.eot` and `.svg` files (`launcher/assets/**` stays exempt).

## 0.1.2

- `busted`: expand FiveM native stubs with client/server KVP storage (`GetResourceKvp*`, `SetResourceKvp*`, `DeleteResourceKvp`), persistent statebags (`Entity(h).state` with `:set()`), routing buckets (`Get/SetPlayerRoutingBucket`, `Get/SetEntityRoutingBucket`), and world entity inspection stubs (`DoesEntityExist`, `GetEntityCoords`, `GetEntityHealth`, `GetEntityModel`, `GetAllVehicles`, `GetAllPeds`, `GetVehicle*`, `Network*`).

## 0.1.1

- `nui-escape`: add `extraDirs` option to scan non-manifest directories (e.g. server overrides).

## 0.1.0

- Initial public release: `check` (9 static checks), `safety` scanner with `oss.json` capability
  enforcement, busted harness.
