// Shared helpers for release/CI scripts: find packages, read + validate oss.json against oss.schema.json.
// Tiny hand-rolled validator (types, required, additionalProperties, pattern) — no npm deps in CI scripts.
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';

export const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const schema = JSON.parse(readFileSync(path.join(ROOT, 'oss.schema.json'), 'utf8'));

export function resourcePackages() {
  const dir = path.join(ROOT, 'packages');
  return readdirSync(dir)
    .filter((p) => existsSync(path.join(dir, p, 'oss.json')))
    .map((p) => ({ pkg: p, dir: path.join(dir, p), ossPath: path.join(dir, p, 'oss.json') }));
}

export function validate(value, node = schema, at = 'oss.json') {
  const errs = [];
  const type = Array.isArray(value) ? 'array' : value === null ? 'null' : typeof value;
  if (node.type && node.type !== type) return [`${at}: expected ${node.type}, got ${type}`];
  if (node.pattern && typeof value === 'string' && !new RegExp(node.pattern).test(value)) errs.push(`${at}: "${value}" does not match ${node.pattern}`);
  if (type === 'object') {
    for (const k of node.required ?? []) if (!(k in value)) errs.push(`${at}: missing "${k}"`);
    for (const [k, v] of Object.entries(value)) {
      const sub = node.properties?.[k];
      if (!sub) {
        if (node.additionalProperties === false) errs.push(`${at}: unknown key "${k}"`);
        continue;
      }
      errs.push(...validate(v, sub, `${at}.${k}`));
    }
  }
  if (type === 'array' && node.items) value.forEach((v, i) => errs.push(...validate(v, node.items, `${at}[${i}]`)));
  return errs;
}

export function fxVersion(dir) {
  const src = readFileSync(path.join(dir, 'fxmanifest.lua'), 'utf8');
  return {
    name: src.match(/^\s*name\s+['"]([^'"]+)['"]/m)?.[1],
    version: src.match(/^\s*version\s+['"]([^'"]+)['"]/m)?.[1],
  };
}
