# busted harness for FiveM Lua resources

Unit-test FiveM resource scripts with [busted](https://lunarmodules.github.io/busted/) on a plain Lua
interpreter, without a FiveM server or client.

| File | What it is |
|---|---|
| `helpers/natives.lua` | Stubs for common FiveM globals, plus capture and assertion helpers |
| `helpers/resource.lua` | `load_resource(dir, side)`: reads `fxmanifest.lua` and runs the resource's real scripts |
| `template.busted` | `.busted` config to copy into your project |
| `spec_example/` | Example spec and fixture resource that exercise everything below |

## Install

```sh
# Lua + LuaRocks from your package manager (brew install lua luarocks, apt install lua5.1 luarocks, ...)
luarocks install busted       # also installs dkjson and luafilesystem, which the harness uses when present
npm install --save-dev @aeterna_game/fivem-devkit
cp node_modules/@aeterna_game/fivem-devkit/busted/template.busted .busted
```

`template.busted` points `lpath` at `node_modules/@aeterna_game/fivem-devkit/busted/`. If you vendor the devkit
some other way, change the `DEVKIT` line. Either way, specs load the harness with:

```lua
local natives  = require('helpers.natives')
local resource = require('helpers.resource')
```

Run `busted` from the folder that holds `.busted`.

## Write a spec

```lua
-- spec/my_resource_spec.lua
local natives  = require('helpers.natives')
local resource = require('helpers.resource')

describe('my_resource', function()
    before_each(function()
        natives.reset({ players = { [1] = 'Alice' } })   -- fresh globals, clock at 0
        resource.load_resource('resources/my_resource', 'server')
    end)

    it('answers a ping', function()
        natives.fire_net('my_resource:ping', 1, 'hello')  -- as if client 1 sent it
        local out = natives.last_emitted('client', 'my_resource:pong')
        assert.are.equal(1, out.target)
        assert.are.same({ n = 1, 'hello' }, out.args)
    end)
end)
```

`spec_example/harness_spec.lua` is a complete, runnable version of this.

## `helpers/natives.lua`

`natives.reset(opts)` removes every global the harness (or a loaded script) installed and installs fresh
stubs. Call it in `before_each`. Options: `resource` (name, default `spec_resource`), `side` (`'server'` or
`'client'`), `convars` (`{ name = value }`), `players` (`{ [id] = name }`), `now` (start time in ms),
`invoker` (what `GetInvokingResource()` returns), `json` (replacement json table), `lib = true` (a minimal
ox_lib-style `lib` with no-op `print`, `callback` and `locale`).

Stubbed globals:

| Area | Globals | Behaviour |
|---|---|---|
| Threads | `CreateThread`, `Wait`, `SetTimeout`, `ClearTimeout`, `Citizen.*` | coroutines on a fake clock; nothing runs until `natives.advance(ms)` |
| Clock | `GetGameTimer` | returns the fake clock |
| Events | `RegisterNetEvent`, `RegisterServerEvent`, `AddEventHandler`, `RemoveEventHandler`, `TriggerEvent` | handlers are kept; `TriggerEvent` dispatches synchronously and is recorded |
| Net events out | `TriggerClientEvent`, `TriggerServerEvent`, latent variants | recorded, not delivered |
| Exports | `exports('name', fn)`, `exports.res:name(...)` | per-resource registry; a missing export raises `No such export` |
| Convars | `GetConvar`, `GetConvarInt`, `GetConvarFloat`, `GetConvarBool`, `SetConvar*` | backed by a table; writes are recorded |
| Players | `GetPlayers`, `GetPlayerName`, `GetNumPlayerIndices`, `DropPlayer`, `source` | backed by `natives.add_player` |
| Runtime | `GetCurrentResourceName`, `GetInvokingResource`, `IsDuplicityVersion`, `PlayerPedId`, `PlayerId`, `GetHashKey` | `GetHashKey` returns its input, not a joaat hash, so specs compare names |
| Data | `json`, `vector3`, `vec3` | `json` uses dkjson when installed, else an encoder-only fallback |

Helpers for specs:

| Function | Purpose |
|---|---|
| `natives.advance(ms)` | move the clock forward, running due threads and timers in time order |
| `natives.now()`, `natives.set_time(ms)`, `natives.thread_count()` | clock and thread inspection |
| `natives.fire(name, ...)` | fire a local event (for example `onResourceStop`) |
| `natives.fire_net(name, src, ...)` | simulate client `src` sending a net event; only `RegisterNetEvent`-ed events are reachable, `source` is set |
| `natives.emitted(kind, name?)`, `natives.last_emitted(kind, name?)` | captured events; `kind` is `'local'`, `'client'` or `'server'`; each entry has `name`, `target`, `args` (packed with `n`) |
| `natives.is_net_event(name)`, `natives.handler_count(name)` | registration checks |
| `natives.spy(name, impl?)`, `natives.calls(name)` | install a recording stub for any native the harness does not model |
| `natives.stub(name, value)` | install any other global; removed by the next `reset()` |
| `natives.stub_export(res, name, fn)`, `natives.exports_of(res?)` | stub another resource's export; read registered exports |
| `natives.add_player(id, name)`, `natives.set_convar(name, value)`, `natives.convar_writes()` | world setup and convar assertions |
| `natives.length(v)` | length of a `vector3` (use instead of `#v`, which needs Lua 5.2+) |

Threads behave like FiveM's scheduler: `CreateThread` does not run the body immediately, `Wait(0)` yields
for one frame (1 ms on the fake clock), and `advance()` stops with an error after 100000 steps so a loop
without `Wait` fails instead of hanging.

## `helpers/resource.lua`

```lua
local res = resource.load_resource(dir, side, opts)
```

- Reads `<dir>/fxmanifest.lua` with a declarative parser (`key 'v'`, `key "v"`, `key { ... }`, comments
  ignored). The manifest is never executed.
- Runs `shared_script(s)` first, then `client_script(s)` or `server_script(s)`, each in manifest order.
  All scripts share `_G`, like scripts of one resource in FiveM.
- Globs in the file name (`client/*.lua`) are expanded in sorted order (needs luafilesystem).
  `@other_resource/file.lua` entries are skipped unless mapped in `opts.externals`.
- `GetCurrentResourceName()` returns `opts.name`, else the manifest `name`, else the folder name.
- `opts.skip = { ['client/main.lua'] = true }` loads everything except the listed entries, so a spec can
  change `Config` before the main script reads it.
- Returns `{ name, dir, side, manifest, loaded, skipped, exports }`.

`resource.read_manifest(dir)` and `resource.parse_manifest(src)` are exported too.

## Lua 5.1 vs 5.4

FiveM runs CfxLua, a Lua 5.4 fork. CI images and distro packages often provide Lua 5.1 or LuaJIT, and
busted runs on whatever interpreter LuaRocks was built for. The harness itself works on Lua 5.1 through 5.5,
but your resource files must load in that interpreter too:

- CfxLua-only syntax does not load in stock Lua at all: backtick hashes (`` `adder` ``), and in 5.1 also
  `<const>` / `<close>` locals, integer division `//`, bitwise operators and `goto`.
- In 5.1, `#v` on a table ignores `__len`, `table.unpack` is `unpack`, and `io.read` / `file:read` need
  `'*a'` instead of `'a'`.

Keep testable logic in plain-Lua files (a `logic.lua` or `config.lua` with no natives and no CfxLua syntax)
and keep native calls in thin `main.lua` files. `packages/cargen-fix` in this repository follows that split.

## Limits

The harness tests logic, not the game. It does not model entities, peds, statebags, NUI, KVP or the
network; use `natives.spy` / `natives.stub` for the natives a spec needs and assert on what was called.
