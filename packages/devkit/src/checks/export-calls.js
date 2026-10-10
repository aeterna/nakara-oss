// export-calls — every `exports.<resource>:<name>(...)` must have a real `exports('<name>', ...)` in
// the target resource, and no resource may declare the same export twice on the same side.
//
// Why: calling a missing export throws, and the usual `pcall(function() x = exports.res:fn() end)`
// turns "this function does not exist" into "it returned nil" — indistinguishable from a valid answer,
// so the caller's fallback runs forever and nothing ever reports it. luacheck has no notion of resource
// boundaries and busted never loads two resources together, so nothing else sees it.
//
// A duplicate declaration is the mirror bug: the file loaded later silently replaces the first
// handler, and reordering the manifest swaps which one wins — with no error either way.
//
// Lessons kept from the original:
//   - A comment is not a declaration. A comment explaining "removed exports('x', ...) because it was a
//     duplicate" must not count as the export still existing.
//   - A string is not a declaration either: a self-test reading its own source with
//     `src:find("exports('x'", 1, true)` must not be reported as a duplicate. The `(?<!['"])`
//     lookbehind rejects `exports(` preceded by a quote.
//   - The side of a file (server / client / shared) is inferred from its path inside the resource
//     (`server/…`, `client/…`, anything else = shared). Server and client exports live in separate
//     runtimes and never clash; shared clashes with both.
//
// Exceptions need a written reason (`ignore` / `ignoreDuplicates`): a silent mute is exactly how a
// real break gets hidden later. Stale exceptions are reported as warnings so they get cleaned up.
import { noFiles, resourceFiles } from './lib/util.js';

const DECL_RE = /(?<!['"])exports\(\s*['"](\w+)['"]/g;
const CALL_RE = /exports\.(\w+)\s*:\s*(\w+)\s*\(/g;

function sideOf(rel) {
  if (rel.startsWith('server/')) return 'server';
  if (rel.startsWith('client/')) return 'client';
  return 'shared';
}
const OVERLAP = { server: ['server', 'shared'], client: ['client', 'shared'], shared: ['server', 'client', 'shared'] };

export default {
  id: 'export-calls',
  description: 'exports.<res>:<fn>() must target an export that really exists; no duplicate export declarations',
  defaults: {
    // "own": only check calls into resources found under the config roots (third-party resources you
    //        do not scan are skipped). "all": also report calls into resources that were not found.
    scope: 'own',
    // { "resource:exportName": "reason" } — calls allowed to target a missing export (e.g. an optional hook)
    ignore: {},
    // { "resource:exportName": "reason" } — declarations allowed to appear twice on the same side
    ignoreDuplicates: {},
  },
  run(ctx, opts) {
    const files = resourceFiles(ctx, ['.lua']);
    if (!files.length) return noFiles(ctx, 'Lua files');

    const declared = new Map(); // resource -> Set(name)
    const decls = new Map(); // 'res:name' -> [{ file, line, side }]
    const calls = new Map(); // 'res:name' -> [{ file, line }]
    for (const r of ctx.resources) declared.set(r.name, new Set());

    for (const { file, resource, rel } of files) {
      const res = resource.name;
      const side = sideOf(rel);
      ctx.readText(file).split('\n').forEach((line, i) => {
        if (line.trimStart().startsWith('--')) return;
        for (const m of line.matchAll(DECL_RE)) {
          declared.get(res).add(m[1]);
          const key = `${res}:${m[1]}`;
          if (!decls.has(key)) decls.set(key, []);
          decls.get(key).push({ file, line: i + 1, side });
        }
        for (const m of line.matchAll(CALL_RE)) {
          const key = `${m[1]}:${m[2]}`;
          if (!calls.has(key)) calls.set(key, []);
          calls.get(key).push({ file, line: i + 1 });
        }
      });
    }

    const ignore = opts.ignore ?? {};
    const ignoreDup = opts.ignoreDuplicates ?? {};
    const findings = [];

    for (const [key, sites] of [...calls].sort()) {
      const [res, name] = key.split(':');
      if (ignore[key]) continue;
      if (!declared.has(res)) {
        if (opts.scope !== 'all') continue;
        for (const s of sites) {
          findings.push({ ...s, message: `exports.${res}:${name}() — resource '${res}' was not found under the configured roots` });
        }
        continue;
      }
      if (declared.get(res).has(name)) continue;
      for (const s of sites) {
        findings.push({
          ...s,
          message: `exports.${res}:${name}() — '${res}' never declares exports('${name}', ...). ` +
            `A pcall around this call turns "missing" into nil. If it is an intentional optional hook, ` +
            `add "${key}": "<reason>" to checks.export-calls.ignore`,
        });
      }
    }

    for (const [key, sites] of [...decls].sort()) {
      if (sites.length < 2 || ignoreDup[key]) continue;
      const clash = sites.some((a, i) => sites.some((b, j) => i !== j && OVERLAP[a.side].includes(b.side)));
      if (!clash) continue;
      const [res, name] = key.split(':');
      const list = sites.map((s) => `${ctx.rel(s.file)}:${s.line} [${s.side}]`).join(', ');
      const last = sites[sites.length - 1];
      findings.push({
        file: last.file,
        line: last.line,
        message: `${res} declares exports('${name}', ...) ${sites.length} times (${list}) — the one loaded ` +
          `later silently replaces the other. Delete the dead one; if the override is intentional, add ` +
          `"${key}": "<reason>" to checks.export-calls.ignoreDuplicates`,
      });
    }

    for (const key of Object.keys(ignore)) {
      const [res, name] = key.split(':');
      if (declared.get(res)?.has(name)) {
        findings.push({ file: ctx.config.file ?? ctx.cwd, severity: 'warn', message: `ignore entry '${key}' is no longer needed — '${res}' now declares it` });
      }
    }
    for (const key of Object.keys(ignoreDup)) {
      if ((decls.get(key) ?? []).length < 2) {
        findings.push({ file: ctx.config.file ?? ctx.cwd, severity: 'warn', message: `ignoreDuplicates entry '${key}' is no longer needed — it is declared once` });
      }
    }
    return findings;
  },
};
