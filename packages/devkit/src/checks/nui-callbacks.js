// nui-callbacks — every `RegisterNUICallback('name', ...)` must be posted from somewhere in the
// resource's own NUI page, or it is dead code.
//
// Why: a Lua callback that no button, keydown handler or message-bus branch ever posts looks like a
// working feature in review. The dangerous variant is a registered-but-unreachable "way out" of a
// focused screen: the safety net exists in Lua, nothing in the page ever calls it, and the player is
// soft-locked.
//
// The matcher is deliberately loose: it looks for the callback name as a quoted string ('', "" or ``)
// ANYWHERE in the resource's NUI files, not specifically inside a `fetch`/`post("name")` call — pages
// often post through a shared helper or bundle, and a matcher anchored to one call shape would
// false-positive on those. If a real poster is missed, widen `nuiDirs` / `nuiExtensions`; do not
// silence a real finding by narrowing the search.
//
// The NUI root is NOT hardcoded to `html/`: it is the directory of the manifest's `ui_page`, plus the
// conventional `nuiDirs` (a page built to `web/` from `web-src/` would otherwise be invisible).
import path from 'node:path';
import { lineOf, noFiles, resourceFiles } from './lib/util.js';

const CALLBACK_RE = /RegisterNUICallback\s*\(\s*(['"])([A-Za-z0-9_:\-./]+)\1/g;
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

export default {
  id: 'nui-callbacks',
  description: 'every RegisterNUICallback name is posted from the resource\'s own NUI page',
  defaults: {
    // directories (relative to the resource) searched for posters, in addition to dirname(ui_page)
    nuiDirs: ['html', 'web', 'web-src'],
    nuiExtensions: ['.js', '.jsx', '.ts', '.tsx', '.mjs', '.vue', '.svelte', '.html', '.css'],
    // { "resource:callbackName": "reason" }
    ignore: {},
  },
  run(ctx, opts) {
    const files = resourceFiles(ctx, ['.lua']);
    if (!files.length) return noFiles(ctx, 'Lua files');

    const byRes = new Map();
    for (const f of files) {
      if (!byRes.has(f.resource)) byRes.set(f.resource, []);
      byRes.get(f.resource).push(f.file);
    }

    const ignore = opts.ignore ?? {};
    const findings = [];
    for (const [res, luaFiles] of byRes) {
      const callbacks = new Map(); // name -> { file, line }
      for (const file of luaFiles) {
        const src = ctx.readText(file);
        for (const m of src.matchAll(CALLBACK_RE)) {
          if (!callbacks.has(m[2])) callbacks.set(m[2], { file, line: lineOf(src, m.index) });
        }
      }
      if (!callbacks.size) continue;

      let nuiRoot = 'html';
      const ui = ctx.readText(res.manifestPath).match(/ui_page\s*\(?\s*['"]([^'"]+)['"]/);
      if (ui) nuiRoot = path.dirname(ui[1]);
      const dirs = new Set([nuiRoot, ...(opts.nuiDirs ?? [])].map((d) => path.join(res.dir, d)));
      const blob = [...dirs]
        .flatMap((d) => ctx.walk(d, opts.nuiExtensions))
        .map((f) => ctx.readText(f))
        .join('\n');

      for (const [name, loc] of callbacks) {
        if (new RegExp(`['"\`]${esc(name)}['"\`]`).test(blob)) continue;
        if (ignore[`${res.name}:${name}`]) continue;
        findings.push({
          ...loc,
          message: `NUI callback '${name}' is registered but nothing in ${res.name}'s NUI files ever posts it — ` +
            `wire a poster in the page or delete the RegisterNUICallback`,
        });
      }
    }
    return findings;
  },
};
