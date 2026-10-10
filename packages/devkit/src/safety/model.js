// Turns files on disk into what rules read:
//   entry (every file):  { file, rel, ext, text, binary, bytecode, minified }
//   model (Lua/JS/HTML): entry + { lang, side, isServer, isClient, isNui, refs, strings, ... }
// Side comes from the resource's fxmanifest.lua lists. A Lua file in no list is 'unlisted' and
// counts as both server and client (conservative: it might be loaded some other way); a JS/HTML
// file in no list is NUI (browser) code.
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { hasGlob, pathGlobRegex } from './glob.js';
import { analyzeJs } from './jsscan.js';
import { analyzeLua } from './luascan.js';
import { MAX_LINE } from './rules/obfuscation.js';

export const LUA_EXTS = ['.lua'];
export const JS_EXTS = ['.js', '.mjs', '.cjs'];
export const HTML_EXTS = ['.html', '.htm'];
export const UNSUPPORTED_EXTS = ['.ts', '.tsx', '.mts', '.cts', '.jsx', '.vue', '.svelte'];
const TEXT_EXTS = new Set([...LUA_EXTS, ...JS_EXTS, ...HTML_EXTS, '.sql', '.json', '.css', '.md', '.txt']);

export function classifier(res) {
  const compile = (list) =>
    (list ?? [])
      .filter((p) => !p.startsWith('@'))
      .map((p) => {
        const n = p.replace(/\\/g, '/').replace(/^\.\//, '');
        return hasGlob(n) ? pathGlobRegex(n) : n;
      });
  const lists = { server: compile(res.manifest.server), client: compile(res.manifest.client), shared: compile(res.manifest.shared) };
  const hit = (pats, rel) => pats.some((p) => (typeof p === 'string' ? p === rel : p.test(rel)));
  return (rel, lang) => {
    const base = path.posix.basename(rel);
    if (lang === 'lua' && rel === base && (base === 'fxmanifest.lua' || base === '__resource.lua')) return 'manifest';
    const s = hit(lists.server, rel);
    const c = hit(lists.client, rel);
    if (hit(lists.shared, rel) || (s && c)) return 'shared';
    if (s) return 'server';
    if (c) return 'client';
    return lang === 'lua' ? 'unlisted' : 'nui';
  };
}

export function buildEntry(file, resDir) {
  const buf = readFileSync(file);
  const ext = path.extname(file).toLowerCase();
  const rel = path.relative(resDir, file).split(path.sep).join('/');
  const entry = { file, rel, ext, text: '', binary: false, bytecode: false, minified: null };
  if (!TEXT_EXTS.has(ext) && !UNSUPPORTED_EXTS.includes(ext)) return entry;
  if (buf.length >= 4 && buf[0] === 0x1b && buf.toString('latin1', 1, 4) === 'Lua') { entry.bytecode = true; return entry; }
  if (buf.subarray(0, 8192).includes(0)) { entry.binary = true; return entry; }
  entry.text = buf.toString('utf8').replace(/^﻿/, '');
  if (JS_EXTS.includes(ext)) {
    if (/\.min\.[cm]?js$/i.test(file)) entry.minified = 'minified file (*.min.js)';
    else if (entry.text.length >= 1000) {
      const lines = entry.text.split('\n').filter((l) => l.trim());
      const avg = lines.length ? entry.text.length / lines.length : 0;
      if (avg > 300) entry.minified = `minified JS (average line length ${Math.round(avg)})`;
    }
  }
  return entry;
}

function longLines(text) {
  const out = [];
  let line = 1;
  let start = 0;
  for (let i = 0; i <= text.length; i++) {
    if (i === text.length || text.charCodeAt(i) === 10) {
      if (i - start > MAX_LINE) out.push(line);
      line++;
      start = i + 1;
    }
  }
  return out;
}

const SIDE_FLAGS = {
  server: { isServer: true, isClient: false, isNui: false },
  client: { isServer: false, isClient: true, isNui: false },
  shared: { isServer: true, isClient: true, isNui: false },
  unlisted: { isServer: true, isClient: true, isNui: false },
  manifest: { isServer: false, isClient: false, isNui: false },
  nui: { isServer: false, isClient: false, isNui: true },
};

// → model or null (not a source file)
export function buildModel(entry, classify) {
  const { ext } = entry;
  if (LUA_EXTS.includes(ext)) {
    const a = analyzeLua(entry.text);
    const side = classify(entry.rel, 'lua');
    return {
      ...entry, ...a, side, ...SIDE_FLAGS[side],
      longLines: longLines(entry.text),
      tableStrings: (arg) => a.tokens.slice(arg.range[0], arg.range[1]).filter((t) => t.type === 'string').map((t) => t.value),
    };
  }
  if (JS_EXTS.includes(ext)) {
    const a = analyzeJs(entry.text);
    const side = classify(entry.rel, 'js');
    return { ...entry, ...a, side, ...SIDE_FLAGS[side], longLines: longLines(entry.text), tableStrings: jsTableStrings };
  }
  if (HTML_EXTS.includes(ext)) return htmlModel(entry);
  return null;
}

function jsTableStrings(arg) {
  const n = arg.node;
  if (n?.type !== 'ArrayExpression') return null;
  const out = n.elements.map((e) => (e?.type === 'Literal' && typeof e.value === 'string' ? e.value : null));
  return out.includes(null) ? null : out;
}

// Inline <script> blocks are NUI code; <script src="https://..."> is remote code.
function htmlModel(entry) {
  const text = entry.text;
  const model = {
    ...entry, lang: 'js', side: 'nui', ...SIDE_FLAGS.nui,
    refs: [], strings: [], errors: [], htmlSinks: [], evalSinks: [], numericTables: [], remoteScripts: [], longLines: [],
    tableStrings: jsTableStrings,
  };
  const lineAt = (off) => text.slice(0, off).split('\n').length;
  for (const m of text.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi)) {
    const attrs = m[1];
    const src = /\bsrc\s*=\s*["']?([^"'\s>]+)/i.exec(attrs)?.[1];
    if (src) {
      if (/^(?:https?:)?\/\//i.test(src)) model.remoteScripts.push({ line: lineAt(m.index), src });
      continue;
    }
    const type = /\btype\s*=\s*["']?([^"'\s>]+)/i.exec(attrs)?.[1]?.toLowerCase();
    if (type && !/^(module|text\/javascript|application\/javascript)$/.test(type)) continue;
    const bodyOffset = m.index + m[0].indexOf('>') + 1;
    const pad = '\n'.repeat(lineAt(bodyOffset) - 1);
    const a = analyzeJs(pad + m[2]);
    model.refs.push(...a.refs);
    model.strings.push(...a.strings);
    model.errors.push(...a.errors);
    model.htmlSinks.push(...a.htmlSinks);
    model.evalSinks.push(...a.evalSinks);
  }
  return model;
}
