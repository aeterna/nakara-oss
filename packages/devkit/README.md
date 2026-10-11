# @aeterna_game/fivem-devkit

Tooling for FiveM resource authors and server owners:

- **`check`** — static checks for bugs that luacheck and the FiveM runtime stay silent about
  (missing exports, dead NUI callbacks, NUI focus with no way out, Lua's 200-locals limit, …).
  See [docs/checks.md](docs/checks.md).
- **`safety`** — scans any resource for dangerous code (dynamic `load`, OS commands, secret convar
  reads, ACE grants, obfuscation, binaries) and checks the code against its declared capabilities
  (`oss.json`). Run it on anything before you install it. See [docs/safety.md](docs/safety.md).
- **busted harness** — FiveM native stubs + a resource loader so you can unit-test resource Lua
  offline. See [busted/README.md](busted/README.md).

## Usage

```bash
npx @aeterna_game/fivem-devkit list
npx @aeterna_game/fivem-devkit check                 # uses ./.fivem-devkit.json
npx @aeterna_game/fivem-devkit safety ./resources/[local]/some_resource
```

Exit code 1 when any error is found, so it works as a CI gate. `--format github` (automatic on
GitHub Actions) turns findings into PR annotations.

## Config — `.fivem-devkit.json`

```json
{
  "roots": ["resources"],
  "specRoots": ["spec"],
  "checks": { "export-calls": { "ignore": { "my_res:futureHook": "planned API, called before it exists" } } },
  "safety": { "allow": { "dynamic-url": [{ "path": "my_res/server/http.lua", "reason": "URL built from declared convar" }] } },
  "plugins": ["./tools/devkit/my-project-check.mjs"]
}
```

Project-specific checks are plugins with the same interface as the built-ins
(`{ id, description, defaults, run(ctx, options) }`, see `src/checks/index.js`).

## License

MIT
