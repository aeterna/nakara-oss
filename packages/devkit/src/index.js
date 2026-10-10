import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { builtinChecks } from './checks/index.js';
import { checkOptions, loadConfig } from './config.js';
import { createContext } from './context.js';

export { loadConfig, createContext };
export { parseManifest, findResources } from './manifest.js';

export async function loadChecks(config, cwd) {
  const checks = [...builtinChecks];
  for (const p of config.plugins ?? []) {
    const mod = await import(pathToFileURL(path.resolve(cwd, p)).href);
    const list = Array.isArray(mod.default) ? mod.default : [mod.default];
    checks.push(...list);
  }
  return checks;
}

export async function runChecks({ cwd, config, only = [] }) {
  const ctx = createContext({ cwd, config });
  const checks = await loadChecks(config, cwd);
  const findings = [];
  for (const check of checks) {
    if (only.length && !only.includes(check.id)) continue;
    const opts = checkOptions(config, check);
    if (!opts.enabled) continue;
    const out = (await check.run(ctx, opts)) ?? [];
    for (const f of out) findings.push({ severity: 'error', ...f, check: check.id });
  }
  return findings;
}
