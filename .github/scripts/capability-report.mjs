#!/usr/bin/env node
// PR job: validate every oss.json and print (markdown, to the job summary) what each PR changes in
// package capabilities compared with the base commit. Widening is not blocked here — CODEOWNERS
// already forces owner review of any oss.json change — this makes the change impossible to miss.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { capabilityDiff } from '../../packages/devkit/src/safety/capabilities.js';
import { ROOT, resourcePackages, validate } from './oss-manifest.mjs';

const base = process.argv[2];
let failed = false;
const out = ['## Package capabilities', ''];
for (const { pkg, ossPath } of resourcePackages()) {
  const now = JSON.parse(readFileSync(ossPath, 'utf8'));
  const errs = validate(now);
  if (errs.length) {
    failed = true;
    console.error(`✗ packages/${pkg}/oss.json:\n  ${errs.join('\n  ')}`);
    out.push(`- ❌ \`${pkg}\`: invalid oss.json (see log)`);
    continue;
  }
  let before = null;
  if (base) {
    try {
      before = JSON.parse(execFileSync('git', ['show', `${base}:${path.relative(ROOT, ossPath)}`], { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }));
    } catch {
      before = null; // new package
    }
  }
  if (!before) {
    out.push(`- 🆕 \`${pkg}\` (new package) — review every capability:`, '```json', JSON.stringify(now.capabilities, null, 2), '```');
    continue;
  }
  const { added, removed } = capabilityDiff(before, now);
  if (!added.length && !removed.length) {
    out.push(`- \`${pkg}\`: unchanged`);
    continue;
  }
  out.push(`- ${added.length ? '⚠️ **widened**' : 'narrowed'} \`${pkg}\``);
  for (const a of added) out.push(`  - ➕ ${a}`);
  for (const r of removed) out.push(`  - ➖ ${r}`);
}
console.log(out.join('\n'));
process.exit(failed ? 1 : 0);
