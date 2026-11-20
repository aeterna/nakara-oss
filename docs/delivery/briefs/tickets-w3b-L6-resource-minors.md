# tickets W3b L6 — nakara_tickets resource: five Q3 minors + "Reader released"
Repo nakara-oss, resource `packages/tickets` (FiveM server JS, ES/CommonJS as the files already are; specs with `node --test` in `packages/tickets/spec`). Write the failing spec first, then the fix. Use your file editing tools only; do not run shell commands. Edit only files in the scope. Follow `.aeterna/engineer.md` (no computed require, no fs, every capability declared in `oss.json`; if a fix needs a new capability, stop and report). Add one line under `## Unreleased` in `packages/tickets/CHANGELOG.md`.

On FXServer a relative `require` resolves from the resource root (that is why files use a try/fallback `loadSibling` pattern; keep it — computed require was rejected by the safety scanner).
1. `server/js/actions.js`: config fallback tries `../../config.json` first, which on FXServer is outside the resource. Try the path that is correct on FXServer first (or `LoadResourceFile(GetCurrentResourceName(), 'config.json')` + JSON.parse when that global exists), then the test path.
2. `loadSibling` treats a missing dependency INSIDE a module like a missing module and reports the fallback path. Only fall back when the error is MODULE_NOT_FOUND for the requested specifier itself; rethrow anything else.
3. Loader and player helpers are copied into several files. Move the player helpers into one module loaded with the existing literal-require pattern. If the loader itself must stay copied (it cannot load itself), keep it and say so in your report.
4. `qbx_medical.Revive` return value is ignored: if it returns `false`, report the action as failed.
5. Guard the player id with `Number.isFinite` (after converting a string id) before any native call; invalid → failed result.
6. After pairing, FXServer logs an unhandled rejection "Invalid state: Reader released" on each long-poll cycle (`server/js/api.js`, fetch body reader / abort). Find the cause and handle it so no unhandled rejection is left; keep the long poll working.
Tests in `packages/tickets/spec/*.test.js` for each item.
