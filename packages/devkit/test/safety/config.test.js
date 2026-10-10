import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { runSafety, validateAllow } from '../../src/safety/index.js';
import { lua, of, scan } from './helpers.js';

test('allow: an entry with a reason suppresses that rule for matching files only', async () => {
  const files = { 'server/catalog.lua': 'local f = load(raw)', 'server/main.lua': 'local g = load(raw)' };
  const safety = { allow: { 'dynamic-load': [{ path: 'nakara_test/server/catalog.lua', reason: 'loads a reviewed data table shipped in this resource' }] } };
  const f = of(await scan(files, { safety }), 'dynamic-load');
  assert.equal(f.length, 1);
  assert.match(f[0].file, /main\.lua$/);
});

test('allow: paths may also be relative to the resource, and globs work', async () => {
  const safety = { allow: { 'dynamic-load': [{ path: 'server/**', reason: 'test' }] } };
  assert.equal(of(await lua('load(x)', { safety }), 'dynamic-load').length, 0);
});

test('allow: entry without a reason is rejected and not applied', async () => {
  const f = await lua('load(x)', { safety: { allow: { 'dynamic-load': ['server/main.lua'] } } });
  assert.equal(of(f, 'invalid-allow').length, 1);
  assert.equal(of(f, 'dynamic-load').length, 1);
  const g = await lua('load(x)', { safety: { allow: { 'dynamic-load': [{ path: 'server/main.lua' }] } } });
  assert.equal(of(g, 'invalid-allow').length, 1);
  assert.equal(of(g, 'dynamic-load').length, 1);
});

test('allow: secret-convar and ace-command cannot be allowlisted', async () => {
  const safety = {
    allow: {
      'secret-convar': [{ path: 'server/**', reason: 'we really need it' }],
      'ace-command': [{ path: 'server/**', reason: 'admin tool' }],
    },
  };
  const f = await lua("local p = GetConvar('rcon_password', '')\nExecuteCommand('add_ace group.admin x allow')", { safety });
  assert.equal(of(f, 'invalid-allow').length, 2);
  assert.equal(of(f, 'secret-convar').length, 1);
  assert.equal(of(f, 'ace-command').length, 1);
});

test('allow: unknown rule ids and catch-all paths are rejected', () => {
  const { findings, entries } = validateAllow({ 'no-such-rule': [{ path: 'x', reason: 'y' }], 'host-exec': [{ path: '**', reason: 'everything' }] }, 'cfg');
  assert.equal(findings.length, 2);
  assert.equal(entries.size, 0);
});

test('no resources under a path is an error, not a green run', async () => {
  const root = mkdtempSync(path.join(os.tmpdir(), 'devkit-safety-empty-'));
  const f = await runSafety({ cwd: root, config: {}, paths: [root] });
  assert.equal(f.length, 1);
  assert.equal(f[0].check, 'safety/no-resources');
});

test('dist/ is scanned (committed build output is where payloads hide)', async () => {
  const f = await scan({ 'html/dist/app.js': 'eval(atob(x));' });
  assert.equal(of(f, 'code-eval').length, 1);
});
