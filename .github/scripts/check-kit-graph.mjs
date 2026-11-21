#!/usr/bin/env node
// Starter Kit checks (ADR 0004 decision 6, ADR 0005 decision 2): package edges follow the table, and every theme.css is the same file.
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { ROOT, resourcePackages } from './oss-manifest.mjs';

export const EDGES = {
  // ADR 0005 decision 2 (replaces the ADR 0004 table). Optional = local events only.
  aeterna_core: { required: [], optional: [] },
  aeterna_notify: { required: ['aeterna_core'], optional: ['aeterna_layout'] },
  aeterna_uikit: { required: ['aeterna_core'], optional: [] },
  aeterna_layout: { required: ['aeterna_core', 'aeterna_uikit'], optional: [] },
  aeterna_hudkit: { required: ['aeterna_core', 'aeterna_uikit', 'aeterna_layout'], optional: [] },
  aeterna_phonekit: { required: ['aeterna_core', 'aeterna_uikit', 'aeterna_notify'], optional: ['aeterna_layout'] },
  aeterna_invkit: { required: ['aeterna_core', 'aeterna_uikit'], optional: ['aeterna_phonekit'] },
  aeterna_testkit: { required: ['aeterna_core', 'aeterna_uikit'], optional: [] },
  aeterna_radial: { required: ['aeterna_core', 'aeterna_uikit'], optional: [] },
  aeterna_loading: { required: [], optional: ['aeterna_core'] },
  aeterna_phonecall: { required: ['aeterna_core', 'aeterna_uikit', 'aeterna_phonekit'], optional: [] },
  aeterna_camera: { required: ['aeterna_core', 'aeterna_uikit', 'aeterna_phonekit', 'aeterna_notify'], optional: [] },
};
const NAME = '((?:aeterna|nakara)_[a-z0-9_]+)';
const REFS = [
  new RegExp(`\\bexports\\.${NAME}`, 'g'),
  new RegExp(`\\bexports\\[\\s*['"]${NAME}['"]`, 'g'),
  new RegExp(`nui://${NAME}/`, 'g'),
  new RegExp(`@${NAME}/`, 'g'),
];

function sourceFiles(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const file = path.join(dir, name);
    if (statSync(file).isDirectory()) {
      if (name !== 'spec') sourceFiles(file, out);
    } else if (/\.(lua|js|html|css)$/.test(name)) out.push(file);
  }
  return out;
}

const stripComments = (text, file) => (file.endsWith('.lua')
  ? text.replace(/^\s*--.*$/gm, '')
  : text.replace(/^\s*\/\/.*$/gm, ''));

export function manifestDependencies(text) {
  const block = /\bdependencies\s*\{([^}]*)\}/.exec(stripComments(text, 'x.lua'));
  return block ? [...block[1].matchAll(/['"]([^'"]+)['"]/g)].map((m) => m[1].replace(/\/.*$/, '')) : [];
}

export function checkPackage(resource, dir) {
  const rule = EDGES[resource];
  if (!rule) return [`${resource}: not in the ADR 0005 edge table`];
  const errors = [];
  const allowed = new Set([resource, ...rule.required]);
  const label = (file) => path.relative(ROOT, file);
  const manifest = path.join(dir, 'fxmanifest.lua');
  for (const dep of manifestDependencies(readFileSync(manifest, 'utf8'))) {
    if (dep.startsWith('/')) continue;
    if (!allowed.has(dep)) errors.push(`${label(manifest)}: dependency ${dep} is not allowed for ${resource}`);
  }
  for (const file of sourceFiles(dir)) {
    const text = stripComments(readFileSync(file, 'utf8'), file);
    for (const re of REFS) {
      for (const m of text.matchAll(re)) {
        if (!allowed.has(m[1])) errors.push(`${label(file)}: reference to ${m[1]} is not allowed for ${resource}`);
      }
    }
  }
  return errors;
}

export function run() {
  const errors = [];
  const canonical = readFileSync(path.join(ROOT, 'docs/specs/theme.css'));
  for (const { dir, ossPath } of resourcePackages()) {
    const { resource } = JSON.parse(readFileSync(ossPath, 'utf8'));
    if (!resource.startsWith('aeterna_')) continue;
    errors.push(...checkPackage(resource, dir));
    const theme = path.join(dir, 'html/theme.css');
    if (existsSync(theme) && !readFileSync(theme).equals(canonical)) {
      errors.push(`${path.relative(ROOT, theme)}: differs from docs/specs/theme.css`);
    }
  }
  return errors;
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  const errors = run();
  for (const e of errors) console.error(`✗ ${e}`);
  console.log(`kit graph: ${errors.length} error(s)`);
  process.exit(errors.length ? 1 : 0);
}
