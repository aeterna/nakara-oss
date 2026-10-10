// export-self-param — the handler of `exports('name', fn)` must not take `self` / `_` as its first
// parameter.
//
// Callers write `exports.res:name(a, b)` (with a colon), but the FiveM export proxy drops the implicit
// self before invoking the handler, so the handler receives `(a, b)`. Written as `function(_, a, b)`,
// every argument shifts by one:
//     seed('hunting', rows)  ->  _ = 'hunting', kind = rows, list = nil
// No error, luacheck green, busted green (specs call the inner function directly, not through the
// export wrapper) — the data simply never arrives where it should.
//
// Three shapes are caught:
//   1. inline        `exports('x', function(self, ...)` / `function(_, ...)`
//   2. named local   `exports('x', fn)` with `local function fn(_, ...)` / `fn = function(self, ...)` in the same file
//   3. colon method  `exports('x', Mod.fn)` with `function Mod:fn(...)` — the colon declares self invisibly
// Accepted blind spot: names declared in another file are not followed (regex cannot track them reliably).
import { lineOf, noFiles, stripLuaComments } from './lib/util.js';

const EXPORT = /\bexports\s*\(\s*(['"])([^'"]+)\1\s*,\s*(?:function\s*\(\s*([^)]*)\)|([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*\))/g;
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const firstParam = (params) => (params ?? '').split(',')[0].trim();
const BAD_FIRST = new Set(['self', '_']);

/** @returns {{ line: number, name: string, why: string }[]} */
export function findSelfParamExports(source) {
  const code = stripLuaComments(source);
  const hits = [];
  for (const m of code.matchAll(EXPORT)) {
    const line = lineOf(code, m.index);
    const name = m[2];
    if (m[3] !== undefined) {
      const p = firstParam(m[3]);
      if (BAD_FIRST.has(p)) hits.push({ line, name, why: `inline function(${p}, ...)` });
      continue;
    }
    const ref = m[4];
    const parts = ref.split('.');
    const last = parts.pop();
    if (parts.length === 0) {
      const re = new RegExp(`\\bfunction\\s+${esc(last)}\\s*\\(\\s*([^)]*)\\)|(?<![.:\\w])${esc(last)}\\s*=\\s*function\\s*\\(\\s*([^)]*)\\)`);
      const d = code.match(re);
      if (!d) continue;
      const p = firstParam(d[1] ?? d[2]);
      if (BAD_FIRST.has(p)) hits.push({ line, name, why: `${ref}(${p}, ...) declared at line ${lineOf(code, d.index)}` });
    } else {
      const base = parts.map(esc).join('\\s*\\.\\s*');
      const re = new RegExp(`\\bfunction\\s+${base}\\s*([.:])\\s*${esc(last)}\\s*\\(\\s*([^)]*)\\)|\\b${base}\\s*\\.\\s*${esc(last)}\\s*=\\s*function\\s*\\(\\s*([^)]*)\\)`);
      const d = code.match(re);
      if (!d) continue;
      const at = lineOf(code, d.index);
      if (d[1] === ':') hits.push({ line, name, why: `${parts.join('.')}:${last} is declared with a colon (implicit self) at line ${at}` });
      else {
        const p = firstParam(d[2] ?? d[3]);
        if (BAD_FIRST.has(p)) hits.push({ line, name, why: `${ref}(${p}, ...) declared at line ${at}` });
      }
    }
  }
  return hits;
}

export default {
  id: 'export-self-param',
  description: 'exports(\'x\', fn) handlers must not expect self/_ as the first parameter',
  defaults: {},
  run(ctx) {
    const files = ctx.resourceFiles(['.lua']);
    if (!files.length) return noFiles(ctx, 'Lua files');
    const findings = [];
    for (const file of files) {
      for (const h of findSelfParamExports(ctx.readText(file))) {
        findings.push({
          file,
          line: h.line,
          message: `exports('${h.name}') — ${h.why}. FiveM does not pass self to export handlers, so every argument shifts by one. ` +
            `Write function(a, b), not function(_, a, b); for a colon method wrap it: exports('x', function(...) return Mod:fn(...) end)`,
        });
      }
    }
    return findings;
  },
};
