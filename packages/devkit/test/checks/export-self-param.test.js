import assert from 'node:assert/strict';
import { test } from 'node:test';
import check, { findSelfParamExports } from '../../src/checks/export-self-param.js';
import { MANIFEST, run } from './fixture.js';

const BAD = [
  "exports('zonesSeed', function(_, kind, list) end)",
  'exports("x", function (self) end)',
  "exports('x',\n  function(\n    _ , a)\nend)",
  "local function seed(_, kind) end\nexports('zonesSeed', seed)",
  "local seed = function(self, kind) end\nexports('zonesSeed', seed)",
  "function Zones:seed(kind) end\nexports('zonesSeed', Zones.seed)",
  "Zones.seed = function(_, kind) end\nexports('zonesSeed', Zones.seed)",
];
const OK = [
  "exports('zonesSeed', function(kind, list) end)",
  "exports('noargs', function() end)",
  "exports('under', function(_x, a) end)",
  "local function seed(kind) end\nexports('zonesSeed', seed)",
  "function Zones.seed(kind) end\nexports('zonesSeed', Zones.seed)",
  "exports('fromElsewhere', SomeGlobal)",
  "Other.seed = function(_, k) end\nlocal function seed(k) end\nexports('s', seed)",
  "-- exports('x', function(_, a) end)",
  "--[[ exports('x', function(self) end) ]]",
  "exports.my_lib:registerSelftest('x', function(_, a) end)",
];

test('catches each shift shape exactly once', () => {
  for (const s of BAD) assert.equal(findSelfParamExports(s).length, 1, s);
});

test('silent on correct shapes, comments and export calls', () => {
  for (const s of OK) assert.equal(findSelfParamExports(s).length, 0, s);
});

test('line number points at the exports() call', () => {
  assert.equal(findSelfParamExports("\n\n-- x\nexports('a', function(_, b) end)")[0].line, 4);
});

test('runs over resource files', async () => {
  const out = await run(check, {
    'resources/r/fxmanifest.lua': MANIFEST,
    'resources/r/server/main.lua': `${BAD[0]}\n${OK[0]}\n`,
  });
  assert.equal(out.length, 1);
  assert.match(out[0].message, /zonesSeed/);
});

test('zero Lua files is an error', async () => {
  const out = await run(check, {});
  assert.match(out[0].message, /scanned 0/);
});
