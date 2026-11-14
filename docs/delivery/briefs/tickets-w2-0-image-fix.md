# Tickets W2-0 image fix · the container cannot start

Evidence (reviewer, real `docker compose up` with dummy secrets, 2026-11-14): `migrate` exits 1 with
`Cannot find module '/app/apps/server/dist/main.js'`. Causes:
1. `tsc -b` writes `apps/server/dist/src/main.js` (rootDir `.` includes `test/` and `package.json`).
2. Every workspace package has `"main": "./src/index.ts"`, so at runtime Node would load TypeScript sources that the
   image does not contain and cannot run.
Reviewer verified the fix approach: `esbuild apps/server/src/main.ts --bundle --platform=node --format=esm
--target=node22 --packages=external --alias:@nakara-tickets/core=./packages/core/src/index.ts
--alias:@nakara-tickets/db=./packages/db/src/index.ts --alias:@nakara-tickets/discord=./packages/discord/src/index.ts`
→ one 137 KB file whose only imports are npm packages and `node:` modules.

## Fix
1. `tickets/package.json` script `"build:server"` = the command above with `--outfile=apps/server/dist/server.mjs`
   (esbuild 0.28.2 is added as a devDependency by the reviewer) and `"build"` = `tsc -b && npm run build:server &&
   npm --workspace @nakara-tickets/web run build` (add `"build": "vite build"` to `apps/web/package.json` if missing).
2. `tickets/Dockerfile`: build stage runs `npm ci` then `npm run build`; runtime stage copies only
   `apps/server/dist/server.mjs`, production `node_modules` (third-party only — the bundle contains our packages; the
   workspace symlinks may stay), `packages/db/migrations` → `/app/migrations`, web `apps/web/dist` → `/app/web`;
   `ENV MIGRATIONS_DIR=/app/migrations WEB_DIR=/app/web`; `CMD ["node","server.mjs"]` with `WORKDIR /app` and the bundle
   at `/app/server.mjs`; keep `USER node`, `HEALTHCHECK`, `ROLE`/`PORT` env.
3. `apps/server/src/main.ts` must not import `package.json` at runtime through a path that breaks in the bundle: the
   `/healthz` version comes from `routes/system.ts` importing `../../package.json` with a JSON import attribute —
   esbuild inlines it, so keep it; just confirm `main.ts` reads `MIGRATIONS_DIR` and `WEB_DIR` first (it already should).
4. `apps/server/test/deploy.test.ts`: add d4 — Dockerfile `CMD` runs `server.mjs`, sets `MIGRATIONS_DIR` and `WEB_DIR`,
   and the runtime stage copies no `src/` directory.
Do not run shell commands; file tools only. Never print connection strings, passwords, tokens or keys.

## Scope
`tickets/package.json` · `tickets/apps/web/package.json` · `tickets/Dockerfile` · `tickets/apps/server/src/main.ts` ·
`tickets/apps/server/test/deploy.test.ts`
