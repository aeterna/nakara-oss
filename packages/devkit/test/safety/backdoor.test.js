import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { runSafety } from '../../src/safety/index.js';

const here = path.dirname(fileURLToPath(import.meta.url));

test('a real-world-shaped backdoor produces errors on every layer', async () => {
  const dir = path.join(here, 'fixtures', 'backdoor');
  const f = await runSafety({ cwd: here, config: {}, paths: [dir] });
  const errors = new Set(f.filter((x) => x.severity === 'error').map((x) => x.check.replace('safety/', '')));
  for (const id of ['dynamic-load', 'secret-convar', 'undeclared-http', 'obfuscation', 'env-tamper', 'ace-command', 'undeclared-net-event']) {
    assert.ok(errors.has(id), `expected ${id}, got ${[...errors].join(', ')}`);
  }
  // both load() calls, including the one reached through _G['lo' .. 'ad']
  const loads = f.filter((x) => x.check === 'safety/dynamic-load').map((x) => x.line);
  assert.deepEqual(loads, [6, 14]);
});
