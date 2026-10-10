// lua-and-nil-or — `a and nil or c` in Lua ALWAYS returns `c`, whatever `a` is.
//
// The author means a ternary ("if a then nil else c"), but `and`/`or` work on truthiness, not branches:
//     a truthy -> `a and nil` = nil -> `nil or c` = c
//     a falsy  -> `a and nil` = a   -> `a or c`   = c
// Both paths yield `c`; the first branch does not exist. luacheck is silent because the syntax is
// valid, and nothing errors at runtime — the symptoms are things like a "danger" colour on every row,
// or a toggle that can never be switched back off.
//
// A comment warning about the trap is not a guard: codebases that document it still reintroduce it.
//
// Fix: invert it — `(not a) and c or nil` (safe when `c` is always truthy, e.g. a string or table).
// If `c` can be false/nil, write a plain `if`; Lua's and/or idiom cannot express that case.
//
// Known limitation: the pattern inside a string literal is still reported (comments are stripped,
// strings are not). Rewrite the string or split it.
import { lineOf, noFiles, stripLuaComments } from './lib/util.js';

const TRAP = /\band\s+nil\s+or\b/g;

export function findAndNilOr(source) {
  const code = stripLuaComments(source);
  const lines = code.split('\n');
  const hits = [];
  for (const m of code.matchAll(TRAP)) {
    const line = lineOf(code, m.index);
    hits.push({ line, text: lines[line - 1].trim().slice(0, 110) });
  }
  return hits;
}

export default {
  id: 'lua-and-nil-or',
  description: '`a and nil or c` always yields c — the first branch can never be chosen',
  defaults: {
    includeSpecs: true, // also scan the config's specRoots
  },
  run(ctx, opts) {
    const files = [...new Set([...ctx.resourceFiles(['.lua']), ...(opts.includeSpecs ? ctx.specFiles() : [])])];
    if (!files.length) return noFiles(ctx, 'Lua files');
    const findings = [];
    for (const file of files) {
      for (const h of findAndNilOr(ctx.readText(file))) {
        findings.push({
          file,
          line: h.line,
          message: `\`a and nil or c\` always returns c (${h.text}) — write \`(not a) and c or nil\`, or an \`if\` when c can be false/nil`,
        });
      }
    }
    return findings;
  },
};
