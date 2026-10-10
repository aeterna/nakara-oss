// Fixture helper for check tests: builds a throwaway project tree under os.tmpdir() and runs one
// check against it through the real config + context code paths.
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after } from 'node:test';
import { checkOptions, DEFAULT_CONFIG } from '../../src/config.js';
import { createContext } from '../../src/context.js';

const dirs = [];
after(() => {
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});

// files: { 'resources/[local]/my_res/fxmanifest.lua': '...', ... }
export function project(files, config = {}) {
  const cwd = mkdtempSync(path.join(os.tmpdir(), 'fivem-devkit-'));
  dirs.push(cwd);
  for (const [rel, content] of Object.entries(files)) {
    const abs = path.join(cwd, rel);
    mkdirSync(path.dirname(abs), { recursive: true });
    writeFileSync(abs, content);
  }
  return { cwd, config: { ...DEFAULT_CONFIG, file: null, ...config } };
}

export async function run(check, files, config = {}) {
  const { cwd, config: cfg } = project(files, config);
  const ctx = createContext({ cwd, config: cfg });
  const findings = (await check.run(ctx, checkOptions(cfg, check))) ?? [];
  return findings.map((f) => ({ ...f, rel: f.file ? path.relative(cwd, f.file) : '' }));
}

export const MANIFEST = "fx_version 'cerulean'\ngame 'gta5'\n";
