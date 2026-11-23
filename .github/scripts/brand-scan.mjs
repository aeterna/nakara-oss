#!/usr/bin/env node
// Starter Kit brand scan (ADR 0004 decision 9). The deny list lives in a private repo as one SHA-256 per line.
// Output names only the list position ("term #k"), so a public log never reveals a term.
import { createHash } from 'node:crypto';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';

export const SCAN_PATHS = ['packages/core', 'packages/uikit', 'packages/layout', 'packages/notify', 'packages/invkit',
  'packages/hudkit', 'packages/phonekit', 'packages/radial', 'packages/loading', 'packages/testkit',
  'packages/phonecall', 'packages/camera', 'docs/specs', 'docs/guides', 'kits/starter'];
const hash = (s) => createHash('sha256').update(s).digest('hex');

export function loadDeny(text) {
  const terms = new Map();
  text.split(/\r?\n/).forEach((line, i) => {
    const h = line.trim().toLowerCase();
    if (/^[0-9a-f]{64}$/.test(h)) terms.set(h, i + 1);
  });
  return terms;
}

// A host such as a.b.c is tested whole and by each part; hyphen and underscore stay inside a token.
export function tokens(line) {
  const out = new Set();
  for (const raw of line.toLowerCase().match(/[\p{L}\p{N}_.-]+/gu) ?? []) {
    const t = raw.replace(/^[.-]+|[.-]+$/g, '');
    if (!t) continue;
    out.add(t);
    if (t.includes('.')) for (const part of t.split('.')) if (part) out.add(part);
  }
  return out;
}

export function scanText(text, deny, file) {
  const hits = [];
  text.split(/\r?\n/).forEach((line, i) => {
    for (const t of tokens(line)) {
      const k = deny.get(hash(t));
      if (k) hits.push({ file, line: i + 1, k });
    }
  });
  return hits;
}

function files(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    const f = path.join(dir, name);
    if (statSync(f).isDirectory()) files(f, out);
    else if (!/\.(woff2|png|jpe?g|webp)$/i.test(name) && name !== 'OFL.txt') out.push(f);
  }
  return out;
}

export function scanTree(root, deny) {
  return SCAN_PATHS.flatMap((p) => files(path.join(root, p)))
    .flatMap((f) => scanText(readFileSync(f, 'utf8'), deny, path.relative(root, f)));
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  const denyPath = process.argv[2];
  const root = path.resolve(process.argv[3] ?? '.');
  if (!denyPath || !existsSync(denyPath)) {
    console.error('usage: brand-scan.mjs <deny-file> [repo-root]');
    process.exit(2);
  }
  const deny = loadDeny(readFileSync(denyPath, 'utf8'));
  if (deny.size === 0) {
    console.error('✗ the deny list has no entries');
    process.exit(2);
  }
  const hits = scanTree(root, deny);
  for (const h of hits) console.error(`✗ term #${h.k} at ${h.file}:${h.line}`);
  console.log(`brand scan: ${hits.length} hit(s) against ${deny.size} terms`);
  process.exit(hits.length ? 1 : 0);
}
