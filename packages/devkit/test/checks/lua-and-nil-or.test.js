import assert from 'node:assert/strict';
import { test } from 'node:test';
import check, { findAndNilOr } from '../../src/checks/lua-and-nil-or.js';
import { MANIFEST, run } from './fixture.js';

const BAD = [
  "tone = isDeposit and nil or 'danger',",
  'c.claimedBy = (c.claimedBy == mcid) and nil or mcid',
  'local keys = allowedKeys(src, admin and nil or opts, admin)',
  "add('x', ok, ok  and\tnil   or 'why')",
];
const OK = [
  "tone = (not isDeposit) and 'danger' or nil,",
  'if c.claimedBy == mcid then c.claimedBy = nil else c.claimedBy = mcid end',
  'local x = a and b or c',
  'local y = a and nil',
  '-- never write ctl and nil or x',
  '--[[ a and nil or c ]]',
];

test('catches every trap shape', () => {
  for (const s of BAD) assert.equal(findAndNilOr(s).length, 1, s);
});

test('silent on correct code and comments', () => {
  for (const s of OK) assert.equal(findAndNilOr(s).length, 0, s);
});

test('known limitation: the pattern inside a string is still reported', () => {
  assert.equal(findAndNilOr('local s = "a and nil or c"').length, 1);
});

test('line numbers survive block comments', () => {
  assert.equal(findAndNilOr('--[[\nx\n]]\nlocal t = a and nil or b')[0].line, 4);
});

test('scans resources and spec roots', async () => {
  const out = await run(check, {
    'resources/r/fxmanifest.lua': MANIFEST,
    'resources/r/client/main.lua': `local a = 1\n${BAD[0]}\n`,
    'spec/r_spec.lua': `${BAD[1]}\n`,
  });
  assert.deepEqual(out.map((f) => [f.rel, f.line]).sort(), [['resources/r/client/main.lua', 2], ['spec/r_spec.lua', 1]]);
});

test('zero Lua files is an error', async () => {
  const out = await run(check, {});
  assert.match(out[0].message, /scanned 0/);
});
