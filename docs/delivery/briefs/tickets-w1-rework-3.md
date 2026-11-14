# Tickets W1 · rework 3 · typecheck after rework-2 (runs 3e803c df9d6a c59ffa)

**Route:** agy:B · Evidence: `npx vitest run` 98/98 three runs in a row ✅ · safety 0/0 ✅ · `tsc --noEmit -p apps/web` ✅ ·
`npx tsc -b` fails: TS6307/TS6059 — `packages/db/test-support/pglite.ts` is not in `packages/db/tsconfig.json`
`include`, and the server tests import it by a relative path into another project (`../../../packages/db/test-support/pglite.js`),
which pulls db sources into the server program outside its `rootDir`.

## Fix
1. `tickets/packages/db/package.json`: add `"exports": { ".": "./src/index.ts", "./test-support": "./test-support/pglite.ts" }`
   (keep `main`/`types`).
2. `tickets/packages/db/tsconfig.json`: `include` adds `"test-support/**/*"`; add `"composite": true` and
   `"types": ["node"]`.
3. Every importer of the helper uses the package path `@nakara-tickets/db/test-support` instead of a relative path
   (server tests, `packages/db/test/queries.test.ts` may keep `../test-support/pglite.js`, discord tests use the package path).
4. `tickets/apps/server/tsconfig.json`: add `"references": [{ "path": "../../packages/core" }, { "path": "../../packages/db" }]`;
   `tickets/packages/discord/tsconfig.json` the same for core and db.
Do not change test logic. Do not run shell commands; file tools only. Never print connection strings, passwords, tokens or keys.

## Acceptance
`npx tsc -b` 0 errors; vitest still 98/98.
