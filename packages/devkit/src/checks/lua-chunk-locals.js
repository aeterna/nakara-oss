// lua-chunk-locals — Lua rejects more than 200 local variables per chunk (LUAI_MAXVARS); the whole
// file then fails to compile, and everything it declares — functions, exports, event handlers — is
// nil. The visible symptom is "an unrelated feature broke", which points everyone at the wrong place.
// luacheck is a linter, not a compiler, so it does not count registers; busted rarely loads files that
// need FiveM globals; at runtime the error scrolls past in a server console nobody watches.
//
// Why a heuristic and not `luac -p`: a locally installed luac may be a different Lua version than the
// FiveM runtime and reject valid FiveM code (and this check must run on any tree without external
// tools). A gate that false-positives gets switched off. The limit itself is the same in every
// version, so counting is version-independent.
//
// What is counted: lines that start with `local` at column 0 (chunk level), outside comments.
// `local a, b, c` counts 3, `local function f` counts 1. Locals inside a top-level `do ... end` are
// not seen, so the number is a LOWER BOUND — the real count has been measured a few above it.
// That is why `block` sits below 200: the margin is the only thing that compensates for the
// undercount, and the cost of a false block ("move new locals into a namespace table") is a minute,
// while the cost of a miss is a silently dead file.
import { noFiles } from './lib/util.js';

export function countChunkLocals(src) {
  let n = 0;
  let inBlockComment = false;
  for (const line of src.split('\n')) {
    if (inBlockComment) {
      if (line.includes(']]')) inBlockComment = false;
      continue;
    }
    if (/^--\[\[/.test(line)) {
      inBlockComment = !line.includes(']]');
      continue;
    }
    if (/^\s*--/.test(line)) continue;
    const m = /^local\s+(function\s+[\w.:]+|[\w\s,]+?)\s*(=|$|\()/.exec(line);
    if (!m) continue;
    const head = m[1];
    n += head.startsWith('function') ? 1 : head.split(',').length;
  }
  return n;
}

export default {
  id: 'lua-chunk-locals',
  description: 'chunk-level locals stay well below Lua\'s 200-per-chunk limit',
  defaults: {
    block: 190, // error at/above this count (200 minus a margin for the counter's undercount)
    warn: 185, // warning at/above this count
  },
  run(ctx, opts) {
    const files = ctx.resourceFiles(['.lua']);
    if (!files.length) return noFiles(ctx, 'Lua files');
    const findings = [];
    for (const file of files) {
      const n = countChunkLocals(ctx.readText(file));
      if (n >= opts.block) {
        findings.push({
          file,
          message: `${n} chunk-level locals (blocking at ${opts.block}; Lua's hard limit is 200 and this count is a lower bound) — ` +
            `move new values into an existing namespace table instead of adding top-level locals`,
        });
      } else if (n >= opts.warn) {
        findings.push({ file, severity: 'warn', message: `${n} chunk-level locals (blocking at ${opts.block}, hard limit 200) — prefer a namespace table for new values` });
      }
    }
    return findings;
  },
};
