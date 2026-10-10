// loadtime-globals — file-level code (outside any function) must not read a global that ANOTHER file
// of the same resource creates, unless that file is guaranteed to load first.
//
// Why: `server_scripts { 'server/*.lua' }` expands the glob alphabetically, so `main.lua` loads before
// `repository.lua`. A file-level line such as
//     local MSG = ('cap %d'):format(Repo.MAX)
// indexes nil and the WHOLE file dies from that line down — including every handler registered below
// it. luacheck is green (the global really is declared elsewhere), busted rarely loads the file, and
// the only signal is a line in the server boot console. The same read inside a function body is fine:
// functions run when called, after every file has loaded. Hoisting a constant to the top of a file —
// normally a good refactor — is exactly what turns working code into broken code here.
//
// Capturing the whole global is worse than indexing it: `local F = Rules` (no `.`/`[`) LOADS fine and
// leaves F nil forever, so the crash happens later, far from the cause. That form is caught too.
// Note: '.' (0x2E) sorts before '_' (0x5F), so `rules.lua` loads before `rules_data.lua`.
//
// Scope (narrow on purpose, so findings are real): only globals that some file of the same resource
// creates (`X = {}`, `X = X or {}`, `X.y = ...`, `function X.y()`), with names starting uppercase.
// Framework globals (Config, lib, exports, MySQL, ...) come from other mechanisms and are not tracked.
//
// The question is not "who owns X" but "has anything created X yet when this line runs":
//   - the read is safe if THIS file created X on an earlier line, or a creating file loads earlier
//     in the same lane (load order is read from fxmanifest: globs expand alphabetically, explicit
//     entries keep their written order, shared scripts load before client/server);
//   - client and server are separate runtimes, so the order is compared per lane;
//   - `X = X or {}` only protects the file that runs it, not files that loaded before it;
//   - a name the file declares as `local` is an alias, not the global;
//   - files the manifest does not load are skipped.
//
// Fix: move the read into a function, or run `X = X or {}` in the reading file before using it.
import path from 'node:path';
import { noFiles, resourceFiles } from './lib/util.js';

const DECL_TABLE_RE = /^\s*([A-Z][A-Za-z0-9_]*)\s*=\s*\{/;
const DECL_FUNC_RE = /^\s*function\s+([A-Z][A-Za-z0-9_]*)[.:]/;
const DECL_GUARDED_RE = /^\s*([A-Z][A-Za-z0-9_]*)\s*=\s*\1\s+or\s*\{/;
const DECL_FIELD_RE = /^\s*([A-Z][A-Za-z0-9_]*)\s*\.\s*[A-Za-z0-9_]+\s*=/;

// Rough end-of-line comment strip: do not cut when `--` sits inside a string (odd quote count before it).
function stripComment(line) {
  const i = line.indexOf('--');
  if (i === -1) return line;
  const before = line.slice(0, i);
  const q = (before.match(/"/g) || []).length + (before.match(/'/g) || []).length;
  return q % 2 === 0 ? before : line;
}

// Reads of uppercase globals that happen at file level. Every block closed by `end` is tracked
// (function / if / do — `for` and `while` open with `do`), not only `function`: otherwise an `if ... end`
// inside a function closes the function early and its body is misread as file level. Tokens are
// processed by their position in the line, so `run = function() return X.y() end` is a read inside
// a function body, not at file level.
export function scanFile(src) {
  const lines = src.split('\n');
  const hits = [];
  const stack = []; // true = this block is a function
  let inLongComment = false;

  for (let i = 0; i < lines.length; i++) {
    let line = lines[i];
    if (inLongComment) {
      if (line.includes(']]')) {
        inLongComment = false;
        line = line.slice(line.indexOf(']]') + 2);
      } else continue;
    }
    if (/--\[\[/.test(line) && !/\]\]/.test(line)) {
      inLongComment = true;
      continue;
    }
    line = stripComment(line);
    if (!line.trim()) continue;

    const events = [];
    for (const t of line.matchAll(/\b(function|elseif|if|do|end)\b/g)) {
      events.push({ at: t.index, kind: 'block', w: t[1] });
    }
    // `Name.` / `Name[` reads — skipping the declaration form `function Name.y(` (a write)
    for (const m of line.matchAll(/\b([A-Z][A-Za-z0-9_]*)\s*[.[]/g)) {
      if (/\bfunction\s+$/.test(line.slice(0, m.index))) continue;
      events.push({ at: m.index, kind: 'read', name: m[1] });
    }
    // whole-value capture on the right of a file-level `local ... =` (strings blanked first;
    // `{ Key = 1 }` is a table key, not a read; names followed by `.`/`[` were counted above)
    const loc = line.match(/^(\s*local\s+[A-Za-z_][\w\s,<>]*=)(.*)$/);
    if (loc && !/^\s*local\s+function\b/.test(line)) {
      const off = loc[1].length;
      const rhs = loc[2].replace(/'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"/g, (s) => ' '.repeat(s.length));
      for (const m of rhs.matchAll(/(^|[^.:\w])([A-Z][A-Za-z0-9_]*)\b(?!\s*[.[:(])(?!\s*=(?!=))/g)) {
        events.push({ at: off + m.index + m[1].length, kind: 'read', name: m[2] });
      }
    }
    events.sort((a, b) => a.at - b.at);

    for (const e of events) {
      if (e.kind === 'read') {
        if (!stack.includes(true)) hits.push({ line: i + 1, name: e.name, text: line });
        continue;
      }
      if (e.w === 'elseif') continue;
      if (e.w === 'function') stack.push(true);
      else if (e.w === 'if' || e.w === 'do') stack.push(false);
      else if (e.w === 'end') stack.pop();
    }
  }
  return hits;
}

function globalCreators(ctx, files) {
  const byName = new Map(); // name -> [{ file, line }]
  for (const f of files) {
    const lines = ctx.readText(f).split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = stripComment(lines[i]);
      if (/^\s*local\b/.test(line)) continue;
      const m = line.match(DECL_GUARDED_RE) || line.match(DECL_TABLE_RE) || line.match(DECL_FUNC_RE) || line.match(DECL_FIELD_RE);
      if (!m) continue;
      if (!byName.has(m[1])) byName.set(m[1], []);
      byName.get(m[1]).push({ file: f, line: i + 1 });
    }
  }
  return byName;
}

// Expand one manifest entry to absolute file paths in FiveM load order (globs expand alphabetically).
function expand(ctx, resDir, entry) {
  if (entry.startsWith('@')) return []; // cross-resource include — its own order
  if (!entry.includes('*')) return [path.join(resDir, entry)];
  const ext = path.extname(entry) || '.lua';
  const recursive = entry.includes('**');
  const base = path.join(resDir, recursive ? entry.slice(0, entry.indexOf('**')) : path.dirname(entry));
  return ctx
    .walk(base, [ext])
    .filter((f) => recursive || path.dirname(f) === path.resolve(base))
    .sort();
}

function loadOrder(ctx, res) {
  const m = res.manifest;
  const shared = m.shared.flatMap((e) => expand(ctx, res.dir, e));
  return {
    client: [...shared, ...m.client.flatMap((e) => expand(ctx, res.dir, e))],
    server: [...shared, ...m.server.flatMap((e) => expand(ctx, res.dir, e))],
  };
}

function localNames(src) {
  const out = new Set();
  for (const m of src.matchAll(/^\s*local\s+([A-Za-z_][A-Za-z0-9_]*)/gm)) out.add(m[1]);
  return out;
}

export default {
  id: 'loadtime-globals',
  description: 'file-level code must not read a global another file of the resource creates later in load order',
  defaults: {},
  run(ctx) {
    const all = resourceFiles(ctx, ['.lua']);
    if (!all.length) return noFiles(ctx, 'Lua files');
    const byRes = new Map();
    for (const f of all) {
      if (!byRes.has(f.resource)) byRes.set(f.resource, []);
      byRes.get(f.resource).push(f.file);
    }

    const findings = [];
    for (const [res, files] of byRes) {
      const creators = globalCreators(ctx, files);
      const lanes = loadOrder(ctx, res);
      const posOf = { client: new Map(), server: new Map() };
      for (const k of ['client', 'server']) {
        lanes[k].forEach((f, i) => {
          if (!posOf[k].has(f)) posOf[k].set(f, i);
        });
      }

      for (const f of files) {
        const src = ctx.readText(f);
        const locals = localNames(src);
        for (const { line, name, text } of scanFile(src)) {
          if (locals.has(name)) continue;
          const made = creators.get(name);
          if (!made) continue;
          const inLanes = ['client', 'server'].filter((k) => posOf[k].has(f));
          if (!inLanes.length) continue;
          const safeInLane = (k) =>
            made.some((c) => {
              if (c.file === f) return c.line < line;
              const iC = posOf[k].get(c.file);
              const iRead = posOf[k].get(f);
              return iC !== undefined && iRead !== undefined && iC < iRead;
            });
          if (inLanes.some(safeInLane)) continue;
          findings.push({
            file: f,
            line,
            message: `file-level read of '${name}' (created in ${path.basename(made[0].file)}) may run before that file loads — ` +
              `the whole file then dies at this line. Move the read into a function, or run \`${name} = ${name} or {}\` first. ` +
              `Line: ${text.trim().slice(0, 110)}`,
          });
        }
      }
    }
    return findings;
  },
};
