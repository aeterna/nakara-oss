import { readdirSync, readFileSync, realpathSync, statSync } from 'node:fs';
import path from 'node:path';

// Plain recursive walk. Deliberately NOT a glob: FiveM category folders like `[local]` are glob
// character classes, so a glob silently matches nothing and a check passes green on zero files.
export function walk(dir, { exts = null, ignore = ['node_modules', '.git'] } = {}, seen = new Set()) {
  const out = [];
  let real, entries;
  try {
    real = realpathSync(dir);
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  // Follow symlinked folders (servers often symlink asset packs into resources/) but never loop.
  if (seen.has(real)) return out;
  seen.add(real);
  for (const e of entries) {
    if (ignore.includes(e.name)) continue;
    const p = path.join(dir, e.name);
    let isDir = e.isDirectory();
    if (e.isSymbolicLink()) isDir = isDirFollow(p);
    if (isDir) out.push(...walk(p, { exts, ignore }, seen));
    else if (!exts || exts.some((x) => e.name.endsWith(x))) out.push(p);
  }
  return out;
}

function isDirFollow(p) {
  try {
    return statSync(p).isDirectory();
  } catch {
    return false;
  }
}

// Small LRU: several checks read the same Lua files, but a whole-tree scan must not pin every file in memory.
const CACHE_MAX = 2000;
const cache = new Map();
export function readText(file) {
  let text = cache.get(file);
  if (text !== undefined) {
    cache.delete(file);
  } else {
    text = readFileSync(file, 'utf8');
    if (cache.size >= CACHE_MAX) cache.delete(cache.keys().next().value);
  }
  cache.set(file, text);
  return text;
}

export function isDir(p) {
  try {
    return statSync(p).isDirectory();
  } catch {
    return false;
  }
}

// 1-based line number of a character offset.
export function lineOf(text, offset) {
  let line = 1;
  for (let i = 0; i < offset && i < text.length; i++) if (text.charCodeAt(i) === 10) line++;
  return line;
}
