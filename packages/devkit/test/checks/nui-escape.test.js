import assert from 'node:assert/strict';
import { test } from 'node:test';
import check from '../../src/checks/nui-escape.js';
import { MANIFEST, run } from './fixture.js';

const files = {
  'resources/menu/fxmanifest.lua': MANIFEST,
  'resources/menu/client/main.lua': 'local function closeMenu() SetNuiFocus(false, false) end\nSetNuiFocus(true, true)\n',
  'resources/quiet/fxmanifest.lua': MANIFEST,
  'resources/quiet/client/main.lua': '-- SetNuiFocus(true, true) in a comment does not count\nSetNuiFocus(true, false)\n',
};
const REG = '.fivem-devkit/nui-focus-surfaces.json';
const entry = { resource: 'menu', file: 'resources/menu/client/main.lua', escape: 'ESC + close callback', evidence: 'closeMenu' };

test('missing registry with focus call sites tells how to create it', async () => {
  const out = await run(check, files);
  assert.equal(out.length, 1);
  assert.match(out[0].message, /does not exist/);
  assert.match(out[0].message, /"surfaces"/);
});

test('missing registry without focus call sites is fine', async () => {
  const out = await run(check, { 'resources/quiet/fxmanifest.lua': MANIFEST, 'resources/quiet/client/main.lua': 'print(1)\n' });
  assert.deepEqual(out, []);
});

test('judged resource with live evidence passes', async () => {
  const out = await run(check, { ...files, [REG]: JSON.stringify({ surfaces: [entry] }) });
  assert.deepEqual(out, []);
});

test('unjudged resource is flagged at the call site', async () => {
  const out = await run(check, { ...files, [REG]: JSON.stringify({ surfaces: [] }) });
  assert.equal(out.length, 1);
  assert.equal(out[0].line, 2);
  assert.match(out[0].message, /'menu' has no entry/);
});

test('stale evidence and missing files are flagged', async () => {
  const out = await run(check, {
    ...files,
    [REG]: JSON.stringify({ surfaces: [{ ...entry, evidence: 'closeUi' }, { ...entry, resource: 'gone', file: 'resources/gone/x.lua' }] }),
  });
  assert.equal(out.length, 2);
  assert.match(out[0].message, /"closeUi"/);
  assert.match(out[1].message, /does not exist/);
});

test('custom registry path and invalid JSON', async () => {
  const out = await run(check, { ...files, 'nui.json': '{ nope' }, { checks: { 'nui-escape': { registry: 'nui.json' } } });
  assert.match(out[0].message, /invalid JSON/);
});

test('zero Lua files is an error', async () => {
  const out = await run(check, {});
  assert.match(out[0].message, /scanned 0/);
});

test('extraDirs discovers SetNuiFocus in non-manifest override folders', async () => {
  const extraFiles = {
    'resources/quiet/fxmanifest.lua': MANIFEST,
    'resources/quiet/client/main.lua': 'print(1)\n',
    'overrides/custom_ui/client.lua': 'SetNuiFocus(true, true)\n',
    'reg.json': JSON.stringify({ surfaces: [] }),
  };
  const out = await run(check, extraFiles, {
    checks: {
      'nui-escape': {
        extraDirs: ['overrides'],
        registry: 'reg.json',
      },
    },
  });
  assert.equal(out.length, 1);
  assert.match(out[0].message, /'custom_ui' has no entry in reg\.json/);
});

test('extraDirs passes when override resource is judged', async () => {
  const extraFiles = {
    'resources/quiet/fxmanifest.lua': MANIFEST,
    'resources/quiet/client/main.lua': 'print(1)\n',
    'overrides/custom_ui/client.lua': 'local function close() SetNuiFocus(false, false) end\nSetNuiFocus(true, true)\n',
    'reg.json': JSON.stringify({
      surfaces: [
        { resource: 'custom_ui', file: 'overrides/custom_ui/client.lua', escape: 'close fn', evidence: 'close' },
      ],
    }),
  };
  const out = await run(check, extraFiles, {
    checks: {
      'nui-escape': {
        extraDirs: ['overrides'],
        registry: 'reg.json',
      },
    },
  });
  assert.deepEqual(out, []);
});
