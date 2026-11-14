# Tickets W1-0 rework · typecheck fails after run 20261114-192045-c4fd14

**Route:** agy:B · reviewer ran `npx vitest run` (31 passed) and `npx tsc -b` in `tickets/` (46 errors).

## Findings to fix
1. `packages/core` and `packages/discord`: every `node:crypto` import and `Buffer` → TS2591. TypeScript 7 loads no
   `@types` by default. Add `"types": ["node"]` to `compilerOptions` in `packages/core/tsconfig.json` and
   `packages/discord/tsconfig.json` (and `apps/server/tsconfig.json` if missing).
2. `apps/server/src/config.ts` uses the zod 3 API; the installed version is **zod 4.6.7**:
   - `z.enum([...], { errorMap })` → `z.enum([...], { error: '...' })`
   - `z.string({ required_error, invalid_type_error })` → `z.string({ error: '...' })`
   - `z.ZodIssueCode.custom` → the string `'custom'`; `ctx.addIssue({ code: 'custom', message, path })`.
   Keep the error messages naming the variable only. All tests e1–e6 must still pass unchanged.
3. Move the database type to the db package so every lane shares one name:
   `tickets/packages/db/src/index.ts` add `export type TicketsDb = PgDatabase<PgQueryResultHKT, typeof schema>;`
   (imports from `drizzle-orm/pg-core`; `schema` = this package's tables). `apps/server/src/db.ts` and
   `types.ts` import `TicketsDb` from `@nakara-tickets/db` instead of defining `NodePgDatabase<…>`.
4. `apps/server/src/main.ts`: on `SIGTERM` and `SIGINT`, `await app.close()` then `await close()` of the db handle,
   then exit 0.

## Acceptance
`npx tsc -b` in `tickets/` reports 0 errors; `npx vitest run` still 31 passed. Do not run shell commands; use only
read-file and write-file tools. Never print connection strings, passwords, tokens or keys.

## Scope
`tickets/packages/core/tsconfig.json` · `tickets/packages/discord/tsconfig.json` · `tickets/apps/server/tsconfig.json` ·
`tickets/apps/server/src/{config,db,types,main}.ts` · `tickets/packages/db/src/index.ts`
