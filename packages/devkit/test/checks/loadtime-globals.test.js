import assert from 'node:assert/strict';
import { test } from 'node:test';
import check from '../../src/checks/loadtime-globals.js';
import { run } from './fixture.js';

const R = 'resources/[local]/fake_res';
const GLOB_MANIFEST = "fx_version 'cerulean'\nserver_scripts {\n    'server/*.lua',\n}\n";

test('file-level read of a global created by a later-loading file is flagged', async () => {
  const out = await run(check, {
    [`${R}/fxmanifest.lua`]: GLOB_MANIFEST,
    [`${R}/server/repository.lua`]: 'FakeRepo = {}\nFakeRepo.MAX = 8\n',
    [`${R}/server/main.lua`]: "local T = {\n  msg = ('cap %d'):format(FakeRepo.MAX),\n}\n",
  });
  assert.equal(out.length, 1);
  assert.equal(out[0].rel, `${R}/server/main.lua`);
  assert.equal(out[0].line, 2);
  assert.match(out[0].message, /'FakeRepo'/);
});

test('the same read inside a function is fine', async () => {
  const out = await run(check, {
    [`${R}/fxmanifest.lua`]: GLOB_MANIFEST,
    [`${R}/server/repository.lua`]: 'FakeRepo = {}\nFakeRepo.MAX = 8\n',
    [`${R}/server/main.lua`]: "local function t()\n  if x then return 1 end\n  return ('cap %d'):format(FakeRepo.MAX)\nend\nlocal run = function() return FakeRepo.MAX end\n",
  });
  assert.deepEqual(out, []);
});

test("reading the file's own global is fine", async () => {
  const out = await run(check, {
    [`${R}/fxmanifest.lua`]: GLOB_MANIFEST,
    [`${R}/server/main.lua`]: 'OwnThing = {}\nlocal x = OwnThing.a\n',
  });
  assert.deepEqual(out, []);
});

test("whole-value capture `local F = Global` is flagged ('.' sorts before '_')", async () => {
  const out = await run(check, {
    [`${R}/fxmanifest.lua`]: GLOB_MANIFEST,
    [`${R}/server/fake_rules.lua`]: 'FakeRules = FakeRules or {}\nFakeRules.V = 1\n',
    [`${R}/server/fake.lua`]: 'local F = FakeRules\nlocal function v() return F.V end\n',
  });
  assert.equal(out.length, 1);
  assert.equal(out[0].rel, `${R}/server/fake.lua`);
});

test('`X = X or {}` in the reading file, and table keys, are fine', async () => {
  const out = await run(check, {
    [`${R}/fxmanifest.lua`]: GLOB_MANIFEST,
    [`${R}/server/fake_rules.lua`]: 'FakeRules = FakeRules or {}\nFakeRules.V = 1\n',
    [`${R}/server/fake.lua`]: 'FakeRules = FakeRules or {}\nlocal F = FakeRules\nlocal K = { FakeRules = 1 }\n',
  });
  assert.deepEqual(out, []);
});

test('explicit order in the manifest wins over the alphabet; shared loads first', async () => {
  const out = await run(check, {
    [`${R}/fxmanifest.lua`]: "fx_version 'cerulean'\nshared_script 'shared/consts.lua'\nserver_scripts {\n  'server/repository.lua',\n  'server/main.lua',\n}\n",
    [`${R}/shared/consts.lua`]: 'Consts = { A = 1 }\n',
    [`${R}/server/repository.lua`]: 'FakeRepo = {}\nFakeRepo.MAX = Consts.A\n',
    [`${R}/server/main.lua`]: 'local m = FakeRepo.MAX\n',
  });
  assert.deepEqual(out, []);
});

test('client and server are separate lanes', async () => {
  const out = await run(check, {
    [`${R}/fxmanifest.lua`]: "fx_version 'cerulean'\nserver_script 'server/a.lua'\nclient_script 'client/b.lua'\n",
    [`${R}/server/a.lua`]: 'Thing = {}\n',
    [`${R}/client/b.lua`]: 'local t = Thing.x\n',
  });
  assert.equal(out.length, 1);
});

test('local aliases and files the manifest does not load are skipped', async () => {
  const out = await run(check, {
    [`${R}/fxmanifest.lua`]: "fx_version 'cerulean'\nserver_scripts { 'server/main.lua', 'server/rules.lua' }\n",
    [`${R}/server/rules.lua`]: 'Rules = {}\n',
    [`${R}/server/main.lua`]: 'local Rules = {}\nlocal r = Rules.x\n',
    [`${R}/tools/unused.lua`]: 'local r = Rules.x\n',
  });
  assert.deepEqual(out, []);
});

test('zero Lua files is an error', async () => {
  const out = await run(check, {});
  assert.match(out[0].message, /scanned 0/);
});
