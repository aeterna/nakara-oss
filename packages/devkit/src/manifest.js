// Minimal fxmanifest.lua reader. Not a Lua interpreter — it understands the declarative shapes
// manifests use in practice:  key 'value'  ·  key "value"  ·  key { 'a', "b", ... }  (multi-line).
// Unknown/dynamic constructs are ignored, never guessed.
import { existsSync } from 'node:fs';
import path from 'node:path';
import { readText, walk } from './fs.js';

const LIST_KEYS = {
  client_script: 'client', client_scripts: 'client',
  server_script: 'server', server_scripts: 'server',
  shared_script: 'shared', shared_scripts: 'shared',
  file: 'files', files: 'files',
  dependency: 'dependencies', dependencies: 'dependencies',
};
const SCALAR_KEYS = ['fx_version', 'game', 'lua54', 'name', 'author', 'description', 'version', 'ui_page', 'loadscreen'];

function stripComments(src) {
  // remove --[[ ]] / --[==[ ]==] blocks then -- line comments (outside quotes, good enough for manifests)
  return src
    .replace(/--\[(=*)\[[\s\S]*?\]\1\]/g, (m) => m.replace(/[^\n]/g, ' '))
    .replace(/--[^\n]*/g, (m) => ' '.repeat(m.length));
}

function strings(s) {
  return [...s.matchAll(/'([^'\n]*)'|"([^"\n]*)"/g)].map((m) => m[1] ?? m[2]);
}

export function parseManifest(src) {
  const text = stripComments(src);
  const m = { client: [], server: [], shared: [], files: [], dependencies: [] };
  const re = /\b([a-z_0-9]+)\s*(\{[\s\S]*?\}|'[^'\n]*'|"[^"\n]*")/g;
  for (const hit of text.matchAll(re)) {
    const [, key, value] = hit;
    if (LIST_KEYS[key]) m[LIST_KEYS[key]].push(...strings(value));
    else if (SCALAR_KEYS.includes(key)) m[key] = strings(value)[0];
  }
  return m;
}

// Every resource (a directory holding fxmanifest.lua or __resource.lua) under the given roots.
export function findResources(cwd, roots, ignore) {
  const out = [];
  for (const r of roots) {
    const abs = path.resolve(cwd, r);
    for (const f of walk(abs, { exts: ['fxmanifest.lua', '__resource.lua'], ignore })) {
      const base = path.basename(f);
      if (base !== 'fxmanifest.lua' && base !== '__resource.lua') continue;
      const dir = path.dirname(f);
      out.push({
        name: path.basename(dir),
        dir,
        manifestPath: f,
        manifest: parseManifest(readText(f)),
      });
    }
  }
  return out.sort((a, b) => a.dir.localeCompare(b.dir));
}

export function hasManifest(dir) {
  return existsSync(path.join(dir, 'fxmanifest.lua')) || existsSync(path.join(dir, '__resource.lua'));
}
