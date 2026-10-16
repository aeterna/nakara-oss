// nui-escape — every resource that calls `SetNuiFocus(true, true)` must be judged in a registry file
// that says how the player leaves that screen, and the evidence string each entry points at must
// still exist.
//
// What this does NOT prove, said up front so a green run is never read as more than it is: it cannot
// verify the escape actually WORKS. A heuristic like "a cancel/close thing exists somewhere in this
// resource" passes on real dead ends — the close button can belong to a different screen than the one
// that traps the player. So the check only asks what a machine can answer:
//   1. is every focus-grabbing resource WRITTEN DOWN (a human looked and recorded an answer)?
//   2. is the evidence that answer names STILL THERE (not renamed or deleted out from under it)?
// Whether the answer is true belongs to runtime tests.
//
// Registry shape (path from the `registry` option, relative to the project root):
//   {
//     "surfaces": [
//       { "resource": "my_menu",
//         "file": "resources/my_menu/client/main.lua",     // relative to the project root
//         "escape": "ESC poll + close callback + onResourceStop releases focus",
//         "evidence": "closeMenu" }                          // literal string that must exist in `file`
//     ]
//   }
import { existsSync } from 'node:fs';
import path from 'node:path';
import { noFiles, resourceFiles } from './lib/util.js';

const CALL_RE = /SetNuiFocus\s*\(\s*true\s*,\s*true\s*\)/;

const SHAPE = '{ "surfaces": [ { "resource": "<name>", "file": "<path from project root>", ' +
  '"escape": "<how the player leaves>", "evidence": "<literal string in file>" } ] }';

export default {
  id: 'nui-escape',
  description: 'every SetNuiFocus(true, true) resource has a written, still-valid escape in the registry',
  defaults: {
    registry: '.fivem-devkit/nui-focus-surfaces.json',
    extraDirs: [],
  },
  run(ctx, opts) {
    const files = resourceFiles(ctx, ['.lua']);
    const extraDirs = Array.isArray(opts?.extraDirs) ? opts.extraDirs.filter(Boolean) : [];
    if (extraDirs.length) {
      const seen = new Set(files.map((f) => f.file));
      for (const extraDir of extraDirs) {
        const absDir = path.resolve(ctx.cwd, extraDir);
        for (const file of ctx.walk(extraDir, ['.lua'])) {
          if (seen.has(file)) continue;
          seen.add(file);
          const rel = path.relative(absDir, file);
          const name = rel.split(path.sep)[0];
          files.push({
            file,
            resource: { name, dir: path.join(absDir, name) },
            rel: rel.split(path.sep).join('/'),
          });
        }
      }
    }
    if (!files.length) return noFiles(ctx, 'Lua files');

    const sites = [];
    for (const { file, resource } of files) {
      const lines = ctx.readText(file).split('\n');
      for (let i = 0; i < lines.length; i++) {
        if (/^\s*--/.test(lines[i])) continue;
        if (CALL_RE.test(lines[i])) sites.push({ file, line: i + 1, resource: resource.name });
      }
    }

    const regPath = path.resolve(ctx.cwd, opts.registry);
    if (!existsSync(regPath)) {
      if (!sites.length) return [];
      return [{
        file: sites[0].file,
        line: sites[0].line,
        message: `${sites.length} SetNuiFocus(true, true) call site(s) found but the registry ${opts.registry} ` +
          `does not exist. Create it with one entry per resource: ${SHAPE}`,
      }];
    }

    let registry;
    try {
      registry = JSON.parse(ctx.readText(regPath));
    } catch (err) {
      return [{ file: regPath, message: `invalid JSON (${err.message}) — expected ${SHAPE}` }];
    }
    if (!Array.isArray(registry?.surfaces)) {
      return [{ file: regPath, message: `missing "surfaces" array — expected ${SHAPE}` }];
    }

    const findings = [];
    const judged = new Set(registry.surfaces.map((s) => s.resource));
    for (const s of sites) {
      if (judged.has(s.resource)) continue;
      findings.push({
        file: s.file,
        line: s.line,
        message: `calls SetNuiFocus(true, true) but resource '${s.resource}' has no entry in ${opts.registry} — ` +
          `add one (how does a player leave this screen?)`,
      });
    }

    for (const s of registry.surfaces) {
      const target = path.resolve(ctx.cwd, s.file ?? '');
      let src;
      try {
        src = ctx.readText(target);
      } catch {
        findings.push({ file: regPath, message: `entry for '${s.resource}' names a file that does not exist: ${s.file}` });
        continue;
      }
      if (typeof s.evidence !== 'string' || !s.evidence || !src.includes(s.evidence)) {
        findings.push({
          file: regPath,
          message: `entry for '${s.resource}' claims evidence "${s.evidence}" in ${s.file}, but that string is not there — ` +
            `the escape may have been renamed or deleted. Update the registry or restore the escape`,
        });
      }
    }
    return findings;
  },
};
