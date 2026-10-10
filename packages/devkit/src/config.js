// Loads `.fivem-devkit.json` from the project root and merges it over each check's defaults.
//
// {
//   "roots": ["resources"],            // directories searched (recursively) for fxmanifest.lua
//   "specRoots": ["spec"],             // busted spec directories (Lua checks that look at tests)
//   "ignorePaths": ["**/node_modules/**"],
//   "checks": { "<check-id>": { "enabled": true, ...check options } },
//   "safety": { ...safety options },
//   "plugins": ["./scripts/devkit/my-check.mjs"]   // extra checks, same interface as src/checks/*
// }
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';

export const CONFIG_FILE = '.fivem-devkit.json';

export const DEFAULT_CONFIG = Object.freeze({
  roots: ['resources'],
  specRoots: ['spec'],
  ignorePaths: ['node_modules', '.git', 'dist'],
  checks: {},
  safety: {},
  plugins: [],
});

export function loadConfig(cwd, explicitPath) {
  const file = explicitPath ? path.resolve(cwd, explicitPath) : path.join(cwd, CONFIG_FILE);
  if (!existsSync(file)) {
    if (explicitPath) throw new Error(`config not found: ${file}`);
    return { ...DEFAULT_CONFIG, file: null };
  }
  let raw;
  try {
    raw = JSON.parse(readFileSync(file, 'utf8'));
  } catch (err) {
    throw new Error(`${file}: invalid JSON (${err.message})`);
  }
  return { ...DEFAULT_CONFIG, ...raw, file };
}

// A check's effective options = its `defaults` overlaid with the project's `checks.<id>` block.
export function checkOptions(config, check) {
  return { enabled: true, ...(check.defaults ?? {}), ...(config.checks?.[check.id] ?? {}) };
}
