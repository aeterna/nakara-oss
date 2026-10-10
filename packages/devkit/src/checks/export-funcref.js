// export-funcref — two rules about function references crossing an export boundary.
//
// Rule 1: an export whose contract is "pass me a TABLE" must not be passed a FUNCTION.
//   Read this before widening it: "never pass functions across exports" is NOT true. Plenty of exports
//   take callbacks on purpose (thread helpers, key binds, inventory hooks, target zones) and work fine:
//   a funcref that crossed runtimes can still be CALLED. What it cannot be is INDEXED like a table.
//   An export that reads `arg.resource` / `arg.export` out of its argument crashes with
//   `Cannot index a funcref` when it gets a closure — at boot, and whatever was being registered is
//   simply never registered while the rest of the resource works normally. luacheck is green, busted
//   does not cross resources, and export-calls is green because the target really exists — the bug is
//   the VALUE. So the rule is about each export's contract, not the language: list the exports that
//   read fields from their argument in `owners`. Do not turn it into "every export" — a gate that fires
//   on dozens of correct callback sites gets disabled within a week. Default: empty (rule 1 is off).
//
// Rule 2: a funcref obtained from an export must not be passed DIRECTLY as the handler of
//   RegisterNetEvent / AddEventHandler, e.g. `RegisterNetEvent(name, exports.lib:wrap(fn))`.
//   Unlike rule 1 the funcref is not called by your code but handed to the event scheduler, which
//   fails to invoke it on some client builds — the handler never runs, on every event. Calling it
//   yourself works, so the fix is a local wrapper:
//       local f = exports.lib:wrap(fn)
//       RegisterNetEvent(name, function(...) f(...) end)
//   Only the literal `exports.…` form in the handler slot is caught (local variables are not tracked —
//   shadowing/reassignment cannot be followed by regex).
import { noFiles } from './lib/util.js';

const CALL = /exports(?:\.([A-Za-z_]\w*)|\[\s*['"]([^'"]+)['"]\s*\])\s*:\s*([A-Za-z_]\w*)\s*\(/g;
const HANDLER_REG = /(?<![\w.:])(RegisterNetEvent|AddEventHandler)\s*\(/g;

// Comments are stripped before matching (examples in comments must not count). Newlines are kept.
function stripComments(src) {
  return src
    .replace(/--\[(=*)\[[\s\S]*?\]\1\]/g, (m) => m.replace(/[^\n]/g, ' '))
    .replace(/--[^\n]*/g, '');
}

const lineAt = (code, i) => code.slice(0, i).split('\n').length;

// Arguments of the call starting at `from` up to the balancing `)` (strings skipped).
function argsOf(code, from) {
  let depth = 1;
  let i = from;
  while (i < code.length && depth > 0) {
    const c = code[i];
    if (c === '(') depth++;
    else if (c === ')') depth--;
    else if (c === "'" || c === '"') {
      const q = c;
      i++;
      while (i < code.length && code[i] !== q) i += code[i] === '\\' ? 2 : 1;
    }
    i++;
  }
  return code.slice(from, i - 1);
}

// Top-level arguments (split on `,` outside brackets and strings).
function splitTopLevel(args) {
  const out = [];
  let depth = 0;
  let start = 0;
  for (let i = 0; i < args.length; i++) {
    const c = args[i];
    if (c === '(' || c === '{' || c === '[') depth++;
    else if (c === ')' || c === '}' || c === ']') depth--;
    else if (c === "'" || c === '"') {
      const q = c;
      i++;
      while (i < args.length && args[i] !== q) i += args[i] === '\\' ? 2 : 1;
    } else if (c === ',' && depth === 0) {
      out.push(args.slice(start, i));
      start = i + 1;
    }
  }
  out.push(args.slice(start));
  return out.map((a) => a.trim());
}

// owners: { "exportName": "why" } or { "resource:exportName": "why" }
export function findFuncrefArgs(source, owners = {}) {
  const code = stripComments(source);
  const hits = [];
  for (const m of code.matchAll(CALL)) {
    const resource = m[1] || m[2];
    const name = m[3];
    const why = owners[`${resource}:${name}`] ?? owners[name];
    if (!why) continue;
    const args = argsOf(code, m.index + m[0].length);
    if (!/\bfunction\b/.test(args)) continue;
    hits.push({ resource, export: name, why, line: lineAt(code, m.index) });
  }
  return hits;
}

export function findFuncrefHandlers(source) {
  const code = stripComments(source);
  const hits = [];
  for (const m of code.matchAll(HANDLER_REG)) {
    const handler = splitTopLevel(argsOf(code, m.index + m[0].length))[1];
    if (!handler || !/^exports\s*[.[]/.test(handler)) continue;
    hits.push({ register: m[1], handler: handler.split('\n')[0].slice(0, 80), line: lineAt(code, m.index) });
  }
  return hits;
}

export default {
  id: 'export-funcref',
  description: 'no closures into table-contract exports; no export funcref as a direct event handler',
  defaults: {
    // { "exportName" | "resource:exportName": "why this export reads fields from its argument" }
    owners: {},
  },
  run(ctx, opts) {
    const files = ctx.resourceFiles(['.lua']);
    if (!files.length) return noFiles(ctx, 'Lua files');
    const findings = [];
    for (const file of files) {
      const src = ctx.readText(file);
      for (const h of findFuncrefArgs(src, opts.owners ?? {})) {
        findings.push({
          file,
          line: h.line,
          message: `exports.${h.resource}:${h.export}(... function ...) — this export reads fields from its argument ` +
            `(${h.why}); a funcref can be called but not indexed. Pass a table such as { resource = '...', export = '...' }`,
        });
      }
      for (const h of findFuncrefHandlers(src)) {
        findings.push({
          file,
          line: h.line,
          message: `${h.register}(..., ${h.handler}...) — a funcref returned by an export is passed directly as an event handler ` +
            `and may never be invoked. Use: local f = exports...(...); ${h.register}(name, function(...) f(...) end)`,
        });
      }
    }
    return findings;
  },
};
