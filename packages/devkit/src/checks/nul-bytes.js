// nul-bytes — text files must not contain a single NUL byte (\x00).
//
// Why: one NUL makes grep/ripgrep classify the file as binary and SKIP IT SILENTLY, so "searched and
// found nothing" reads like proof of absence while the code is right there. git also shows its diff as
// "Binary files differ", so review cannot see changes to it. Typical sources: a raw control character
// pasted into a comment, or a regex written with raw bytes (`/[<NUL>-<US>]/`) instead of escapes —
// and every generated copy of that file inherits it.
//
// Fix: write the escape instead of the raw byte (`\0` in Lua, `\x00` in JS/regex). For generated or
// bundled files, fix the source and regenerate.
//
// Scans `paths` (default: the whole project root) with the config's `ignorePaths`, so it works on any
// tree — no git required.
import path from 'node:path';
import { noFiles } from './lib/util.js';

export const TEXT_EXTENSIONS = ['.lua', '.mjs', '.cjs', '.js', '.ts', '.tsx', '.jsx', '.py', '.md', '.json', '.css', '.html'];

/** 1-based line numbers containing at least one NUL (each line reported once). Accepts string or Buffer. */
export function nulLines(text) {
  const lines = [];
  let line = 1;
  const at = typeof text === 'string' ? (i) => text.charCodeAt(i) : (i) => text[i];
  for (let i = 0; i < text.length; i++) {
    const c = at(i);
    if (c === 0x0a) line++;
    else if (c === 0x00 && lines[lines.length - 1] !== line) lines.push(line);
  }
  return lines;
}

export default {
  id: 'nul-bytes',
  description: 'text files contain no raw NUL bytes (grep would silently skip them as binary)',
  defaults: {
    paths: ['.'], // relative to the project root
    extensions: TEXT_EXTENSIONS,
  },
  run(ctx, opts) {
    const exts = opts.extensions.map((e) => e.toLowerCase());
    const files = [...new Set(opts.paths.flatMap((p) => ctx.walk(p, null)))]
      .filter((f) => exts.includes(path.extname(f).toLowerCase()));
    if (!files.length) return noFiles(ctx, `text files (${exts.join(' ')}) under ${opts.paths.join(', ')}`);
    const findings = [];
    for (const file of files) {
      let text;
      try {
        text = ctx.readText(file);
      } catch {
        continue; // broken symlink / unreadable entry
      }
      const lines = nulLines(text);
      if (!lines.length) continue;
      findings.push({
        file,
        line: lines[0],
        message: `contains raw NUL byte(s) on line(s) ${lines.join(', ')} — grep treats the file as binary and skips it. ` +
          `Write the escape instead (\\0 in Lua, \\x00 in JS/regex); for generated files fix the source and regenerate`,
      });
    }
    return findings;
  },
};
