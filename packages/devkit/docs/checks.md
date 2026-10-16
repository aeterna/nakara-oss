# Built-in checks

Every check reads the resources found under `roots` in `.fivem-devkit.json` (a resource is a directory
holding `fxmanifest.lua` or `__resource.lua`). Options go under `checks.<id>`; every check also accepts
`"enabled": false`.

A check that scans **zero** input files reports an error instead of passing: a lint that silently reads
nothing (for example because a `[category]` folder was treated as a glob character class) is a gate that is
green while broken.

```json
{
  "roots": ["resources/[local]"],
  "checks": {
    "export-calls": { "ignore": { "my_medical:applyTreatment": "optional hook, the caller skips it when absent" } },
    "lua-chunk-locals": { "block": 190, "warn": 185 }
  }
}
```

Run one or more checks with `fivem-devkit check <id> [<id> ...]`; list them with `fivem-devkit list`.

| id | catches |
|---|---|
| [export-calls](#export-calls) | `exports.res:fn()` calls to exports that do not exist; duplicate export declarations |
| [export-self-param](#export-self-param) | export handlers written as `function(_, a, b)` / colon methods |
| [export-funcref](#export-funcref) | closures passed to table-contract exports; export funcrefs as event handlers |
| [nui-callbacks](#nui-callbacks) | `RegisterNUICallback` names the NUI page never posts |
| [nui-escape](#nui-escape) | `SetNuiFocus(true, true)` resources with no written, still-valid escape |
| [lua-and-nil-or](#lua-and-nil-or) | `a and nil or c`, which always yields `c` |
| [lua-chunk-locals](#lua-chunk-locals) | files approaching Lua's 200 locals-per-chunk limit |
| [loadtime-globals](#loadtime-globals) | file-level reads of globals another file creates later in load order |
| [nul-bytes](#nul-bytes) | raw NUL bytes that make grep skip a text file |

---

## export-calls

**Catches.** Every `exports.<resource>:<name>(...)` whose target resource never declares
`exports('<name>', ...)`, and any export name declared twice in one resource on overlapping sides.

**Why.** Calling a missing export throws, and the common `pcall(function() x = exports.res:fn() end)`
turns "this function does not exist" into "it returned nil" — indistinguishable from a real answer, so a
fallback runs forever and nothing reports it. luacheck has no notion of resource boundaries and busted
never loads two resources together. A duplicate declaration is the mirror bug: whichever file loads later
silently replaces the other, and reordering the manifest swaps the winner.

**Details.**
- Comments and strings are not declarations (`-- removed exports('x', ...)`, or a self-test doing
  `src:find("exports('x'", 1, true)`, do not count).
- The side of a file is inferred from its path inside the resource: `server/…`, `client/…`, anything else is
  shared. Server and client never clash; shared clashes with both.
- Stale `ignore` / `ignoreDuplicates` entries are reported as warnings.

**Options.**

| option | default | meaning |
|---|---|---|
| `scope` | `"own"` | `"own"`: only check calls into resources found under `roots` (third-party resources you do not scan are skipped). `"all"`: also report calls into resources that were not found — useful when `roots` covers the whole server. |
| `ignore` | `{}` | `{ "resource:export": "reason" }` — calls allowed to target a missing export. A reason is expected; a silent mute is how a real break gets hidden. |
| `ignoreDuplicates` | `{}` | `{ "resource:export": "reason" }` — declarations allowed twice. Only for an intentional override; if the first one is dead, delete it instead. |

```json
{ "checks": { "export-calls": { "scope": "own", "ignore": { "my_medical:applyTreatment": "forward hook" } } } }
```

---

## export-self-param

**Catches.** Export handlers whose first parameter is `self` or `_`:

1. inline: `exports('x', function(_, a) ... end)`
2. named function in the same file: `exports('x', fn)` with `local function fn(self, a)` or `fn = function(_, a)`
3. colon method: `exports('x', Mod.fn)` with `function Mod:fn(a)` (the colon declares `self` invisibly)

**Why.** Callers write `exports.res:name(a, b)`, but the export proxy drops the implicit self before calling
the handler, so the handler receives `(a, b)`. With `function(_, a, b)` every argument shifts by one —
no error, and specs that call the inner function directly stay green.

**Fix.** `function(a, b)`; for a colon method, wrap it: `exports('x', function(...) return Mod:fn(...) end)`.

**Limitation.** Names declared in another file are not followed.

**Options.** none.

---

## export-funcref

**Catches.**

- **Rule 1** — a `function` passed into an export listed in `owners`, i.e. an export whose contract is
  "give me a table" and which reads fields (`arg.resource`, `arg.export`, ...) from its argument.
- **Rule 2** — a value taken straight from an export used as the handler of `RegisterNetEvent` /
  `AddEventHandler`, e.g. `RegisterNetEvent(name, exports.lib:wrap(fn))`.

**Why.** A funcref that crossed runtimes can be *called* but not *indexed*. An export that indexes its
argument fails with `Cannot index a funcref` at boot, and whatever it was registering is simply never
registered. Passing callbacks across exports is otherwise normal and correct (thread helpers, key binds,
inventory hooks), which is why rule 1 only applies to exports you list — a rule that fires on every callback
site gets disabled. For rule 2, the event scheduler (not your code) invokes the handler and can fail to call
an export funcref; calling it yourself works, so wrap it:

```lua
local onApply = exports.my_lib:guard('my_res', function(eff) ... end)
RegisterNetEvent('my_res:apply', function(...) onApply(...) end)
```

**Limitation.** Rule 2 only sees the literal `exports.…` form in the handler slot; local variables are not
tracked.

**Options.**

| option | default | meaning |
|---|---|---|
| `owners` | `{}` | Exports that take a table. Keys are `"exportName"` (any resource) or `"resource:exportName"`; values say which fields the export reads. Empty = rule 1 off. |

```json
{ "checks": { "export-funcref": { "owners": {
  "registerSelftest": "reads meta.resource / meta.export to call it later",
  "my_lib:declareCommand": "reads spec.name / spec.tier"
} } } }
```

---

## nui-callbacks

**Catches.** A `RegisterNUICallback('name', ...)` whose name never appears as a quoted string (`'name'`,
`"name"` or `` `name` ``) in the resource's NUI files.

**Why.** A callback nothing ever posts is dead code that looks like a feature in review. The dangerous case
is a registered-but-unreachable "way out" of a focused screen, which leaves players soft-locked.

**Details.** The NUI files are those under `dirname(ui_page)` plus `nuiDirs`. The matcher is deliberately
loose (any quoted occurrence, not only `fetch`/`post` calls) because pages often post through a shared
helper or bundle. If a real poster is missed, widen `nuiDirs` / `nuiExtensions` rather than narrowing the
search.

**Options.**

| option | default | meaning |
|---|---|---|
| `nuiDirs` | `["html", "web", "web-src"]` | extra directories (relative to the resource) searched for posters |
| `nuiExtensions` | `.js .jsx .ts .tsx .mjs .vue .svelte .html .css` | file types searched |
| `ignore` | `{}` | `{ "resource:callbackName": "reason" }` — e.g. posted by another resource's page |

```json
{ "checks": { "nui-callbacks": { "ignore": { "my_morph:pick": "posted by the appearance editor override" } } } }
```

---

## nui-escape

**Catches.**

1. a resource that calls `SetNuiFocus(true, true)` but has no entry in the registry;
2. a registry entry whose `file` no longer exists, or whose `evidence` string is no longer in that file.

**Why.** A screen that takes exclusive input with no way out is a soft-lock. This check deliberately does
**not** claim the escape works — a heuristic like "a close button exists somewhere in this resource" passes
on real dead ends, because the button can belong to a different screen. It only proves that a human looked
at every focus-grabbing resource and wrote down how the player leaves, and that the code the answer points at
is still there. Whether the escape works belongs to runtime tests.

**Registry** (path from the `registry` option, relative to the project root):

```json
{
  "surfaces": [
    {
      "resource": "my_menu",
      "file": "resources/[local]/my_menu/client/main.lua",
      "escape": "ESC poll + close callback + onResourceStop releases focus",
      "evidence": "closeMenu"
    }
  ]
}
```

`file` is relative to the project root; `evidence` is a literal string that must exist in `file`. When the
registry is missing and at least one `SetNuiFocus(true, true)` call exists, the check reports how to create it.
Lines starting with `--` are ignored.

**Options.**

| option | default | meaning |
|---|---|---|
| `registry` | `".fivem-devkit/nui-focus-surfaces.json"` | registry path |
| `extraDirs` | `[]` | extra directories (relative to project root) to scan for Lua files outside `roots` (e.g. server overrides without `fxmanifest.lua`). The immediate subdirectory under each path is taken as the resource name. |

---

## lua-and-nil-or

**Catches.** `<anything> and nil or <anything>` in Lua code (comments are stripped).

**Why.** `and`/`or` work on truthiness, not branches: if `a` is truthy, `a and nil` is `nil` and `nil or c`
is `c`; if `a` is falsy, `a or c` is `c`. Both paths give `c`, so the "then nil" branch never exists.
luacheck is silent because the syntax is valid, and nothing errors at runtime.

**Fix.** `(not a) and c or nil` when `c` is always truthy (a string or table); otherwise a plain `if`.

**Limitation.** The pattern inside a string literal is still reported.

**Options.**

| option | default | meaning |
|---|---|---|
| `includeSpecs` | `true` | also scan `specRoots` |

---

## lua-chunk-locals

**Catches.** Files with too many chunk-level `local` declarations.

**Why.** Lua rejects more than 200 locals per chunk; the whole file then fails to compile and everything it
declares is nil, so an unrelated feature appears broken. luacheck does not count registers, and a local
`luac` may be a different Lua version than the FiveM runtime (rejecting valid code), so this check counts
instead of compiling.

**Details.** It counts lines that start with `local` at column 0 outside comments (`local a, b, c` = 3,
`local function f` = 1). Locals inside a top-level `do ... end` are not seen, so the count is a **lower
bound**; that is why the blocking threshold sits below 200.

**Fix.** Put new values into an existing namespace table instead of adding top-level locals.

**Options.**

| option | default | meaning |
|---|---|---|
| `block` | `190` | error at or above this count |
| `warn` | `185` | warning at or above this count |

---

## loadtime-globals

**Catches.** File-level code (outside any function) that reads an uppercase global which another file of
the same resource creates, when that file is not guaranteed to load first. Both `X.y` / `X[...]` reads
and whole-value captures (`local F = X`) are caught.

**Why.** `server_scripts { 'server/*.lua' }` expands alphabetically, so `main.lua` loads before
`repository.lua`. A file-level `('cap %d'):format(Repo.MAX)` indexes nil and the whole file dies from that
line down, including every handler registered below it. The same read inside a function is fine — functions
run after every file has loaded. `local F = Rules` is worse: the file loads and `F` stays nil forever, so the
crash happens later, far from the cause. Note that `.` sorts before `_`, so `rules.lua` loads before
`rules_data.lua`.

**Details.**
- A global counts as created by `X = {}`, `X = X or {}`, `X.y = ...` or `function X.y()`.
- Load order comes from the manifest: globs expand alphabetically, explicit entries keep their order,
  shared scripts load before client/server, and client/server are separate lanes.
- A read is safe if the same file created `X` on an earlier line, or a creating file loads earlier in the
  same lane. `X = X or {}` protects only the file that runs it.
- Names the file declares as `local` are aliases, not the global. Files the manifest does not load, and
  `@other_resource/...` includes, are skipped.
- Framework globals (`Config`, `lib`, `MySQL`, ...) are not created by the resource, so they are not tracked.

**Fix.** Move the read into a function, or run `X = X or {}` in the reading file before using it.

**Options.** none.

---

## nul-bytes

**Catches.** Text files containing a raw NUL byte (`\x00`).

**Why.** One NUL makes grep/ripgrep treat the file as binary and skip it silently, so "searched and found
nothing" reads as proof of absence. git shows its diff as "Binary files differ", hiding changes from review.
Typical sources are a control character pasted into a comment, or a regex written with raw bytes instead of
escapes — inherited by every generated copy.

**Fix.** Write the escape (`\0` in Lua, `\x00` in JS/regex); for generated files fix the source and regenerate.

**Details.** Walks `paths` with the config's `ignorePaths` (no git needed).

**Options.**

| option | default | meaning |
|---|---|---|
| `paths` | `["."]` | directories to scan, relative to the project root |
| `extensions` | `.lua .mjs .cjs .js .ts .tsx .jsx .py .md .json .css .html` | file types treated as text |
