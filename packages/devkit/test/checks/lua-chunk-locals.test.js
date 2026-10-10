import assert from 'node:assert/strict';
import { test } from 'node:test';
import check, { countChunkLocals } from '../../src/checks/lua-chunk-locals.js';
import { MANIFEST, run } from './fixture.js';

test('counter cases', () => {
  const cases = [
    ['local a = 1', 1],
    ['local a, b, c = 1, 2, 3', 3],
    ['local function f() end', 1],
    ['  local indented = 1', 0],
    ['-- local commented = 1', 0],
    ['--[[\nlocal inside = 1\n]]', 0],
    ['local t = {\n  local_looking = 1,\n}', 1],
  ];
  for (const [src, want] of cases) assert.equal(countChunkLocals(src), want, src);
});

test('counter can still say no: a file past the hard limit is counted past it', () => {
  const over = Array.from({ length: 205 }, (_, i) => `local v${i} = ${i}`).join('\n');
  assert.ok(countChunkLocals(over) > 200);
});

const locals = (n) => Array.from({ length: n }, (_, i) => `local v${i} = ${i}`).join('\n');

test('blocks at 190, warns at 185, silent below', async () => {
  const out = await run(check, {
    'resources/r/fxmanifest.lua': MANIFEST,
    'resources/r/server/big.lua': locals(190),
    'resources/r/server/near.lua': locals(186),
    'resources/r/server/ok.lua': locals(50),
  });
  assert.deepEqual(out.map((f) => [f.rel, f.severity ?? 'error']).sort(), [
    ['resources/r/server/big.lua', 'error'],
    ['resources/r/server/near.lua', 'warn'],
  ]);
});

test('thresholds are configurable', async () => {
  const out = await run(check, {
    'resources/r/fxmanifest.lua': MANIFEST,
    'resources/r/server/a.lua': locals(20),
  }, { checks: { 'lua-chunk-locals': { block: 20, warn: 10 } } });
  assert.equal(out.length, 1);
});

test('zero Lua files is an error', async () => {
  const out = await run(check, {});
  assert.match(out[0].message, /scanned 0/);
});
