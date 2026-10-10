import assert from 'node:assert/strict';
import { test } from 'node:test';
import check, { findFuncrefArgs, findFuncrefHandlers } from '../../src/checks/export-funcref.js';
import { MANIFEST, run } from './fixture.js';

const owners = {
  registerDisconnectTask: 'reads meta.resource / meta.export',
  declareCommand: 'reads spec.name / spec.tier',
  'my_lib:registerSelftest': 'reads meta.resource / meta.export',
};

const BAD = [
  "exports.my_lib:registerDisconnectTask('video', function(src) stop(src) end)",
  "exports['my_lib']:registerDisconnectTask('v', function() end)",
  'exports.my_lib:declareCommand(function() end)',
  "exports.my_lib:registerSelftest('x', function() end)",
];
const OK = [
  "exports.my_lib:registerDisconnectTask('video', { resource = 'my_video', export = 'onPlayerGone' })",
  'exports.my_lib:createThread(function() while true do Wait(0) end end)',
  "exports.my_lib:bindKey('x', function() end)",
  "exports.ox_inventory:registerHook('swapItems', function() end)",
  "exports('onPlayerGone', function(ctx) return 1 end)",
  "exports.my_lib:registerDisconnectTask('x', { export = 'myFunctionName' })",
  "-- exports.my_lib:registerDisconnectTask('x', function() end)",
  "exports.other_lib:registerSelftest('x', function() end)", // resource-scoped owner key
];
const BAD_HANDLER = [
  "RegisterNetEvent('buffs:apply', exports.my_lib:guard('buffs', function(eff)\n  if type(eff) ~= 'table' then return end\nend, 'apply'))",
  "AddEventHandler('x', exports['my_lib']:guard('r', function() end))",
  "RegisterNetEvent('x',\n    exports.my_lib:guard('r', function(a, b) f(a, b) end, 'x'))",
];
const OK_HANDLER = [
  "local onApply = exports.my_lib:guard('buffs', function(eff) end, 'apply')\nRegisterNetEvent('buffs:apply', function(...) onApply(...) end)",
  "AddEventHandler('playerSpawned', refreshHud)",
  "RegisterNetEvent('x', function(d) exports.ox_lib:notify({ description = d }) end)",
  "RegisterNetEvent('my:ev')",
  "exports.my_lib:createThread('r', function() end)",
  "-- RegisterNetEvent('x', exports.my_lib:guard('r', function() end))",
];

test('rule 1: closures into table-contract exports', () => {
  for (const s of BAD) assert.equal(findFuncrefArgs(s, owners).length, 1, s);
  for (const s of OK) assert.equal(findFuncrefArgs(s, owners).length, 0, s);
});

test('rule 1 is off with the default empty owners map', () => {
  for (const s of BAD) assert.equal(findFuncrefArgs(s).length, 0, s);
});

test('rule 2: export funcref in the handler slot', () => {
  for (const s of BAD_HANDLER) assert.equal(findFuncrefHandlers(s).length, 1, s);
  for (const s of OK_HANDLER) assert.equal(findFuncrefHandlers(s).length, 0, s);
});

test('runs over resource files with configured owners', async () => {
  const files = {
    'resources/r/fxmanifest.lua': MANIFEST,
    'resources/r/server/main.lua': `${BAD[0]}\n${BAD_HANDLER[1]}\n`,
  };
  assert.equal((await run(check, files)).length, 1);
  const out = await run(check, files, { checks: { 'export-funcref': { owners } } });
  assert.deepEqual(out.map((f) => f.line), [1, 2]);
});

test('zero Lua files is an error', async () => {
  const out = await run(check, {});
  assert.match(out[0].message, /scanned 0/);
});
