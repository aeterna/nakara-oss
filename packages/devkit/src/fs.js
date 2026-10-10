import { readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';

// Plain recursive walk. Deliberately NOT a glob: FiveM category folders like `[local]` are glob
// character classes, so a glob silently matches nothing and a check passes green on zero files.
export function walk(dir, { exts = null, ignore = ['node_modules', '.git'] } = {}) {
  const out = [];
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    if (ignore.includes(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p, { exts, ignore }));
    else if (!exts || exts.some((x) => e.name.endsWith(x))) out.push(p);
  }
  return out;
}

const cache = new Map();
export function readText(file) {
  if (!cache.has(file)) cache.set(file, readFileSync(file, 'utf8'));
  return cache.get(file);
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
