import assert from 'node:assert/strict';
import { test } from 'node:test';
import check from '../../src/checks/export-calls.js';
import { MANIFEST, run } from './fixture.js';

const R = 'resources/[local]';
const base = {
  [`${R}/res_a/fxmanifest.lua`]: MANIFEST,
  [`${R}/res_b/fxmanifest.lua`]: MANIFEST,
  [`${R}/res_b/server/main.lua`]: "exports('channelLabel', function(src) return 'x' end)\n",
};

test('flags a call to an export the target never declares', async () => {
  const out = await run(check, {
    ...base,
    [`${R}/res_a/server/main.lua`]: "local ch\npcall(function() ch = exports.res_b:channelOf(1) end)\n",
  });
  assert.equal(out.length, 1);
  assert.equal(out[0].line, 2);
  assert.match(out[0].message, /res_b:channelOf/);
});

test('passes when the export exists; skips resources outside the roots by default', async () => {
  const out = await run(check, {
    ...base,
    [`${R}/res_a/server/main.lua`]: "exports.res_b:channelLabel(1)\nexports.ox_inventory:AddItem(1, 'x', 1)\n",
  });
  assert.deepEqual(out, []);
});

test('scope "all" reports calls into resources that were not found', async () => {
  const out = await run(check, {
    ...base,
    [`${R}/res_a/server/main.lua`]: "exports.ox_inventory:AddItem(1, 'x', 1)\n",
  }, { checks: { 'export-calls': { scope: 'all' } } });
  assert.equal(out.length, 1);
  assert.match(out[0].message, /not found/);
});

test('a commented-out or quoted declaration does not count', async () => {
  const out = await run(check, {
    ...base,
    [`${R}/res_b/server/extra.lua`]: "-- exports('channelOf', fn) removed\nlocal ok = src:find(\"exports('channelOf'\", 1, true)\n",
    [`${R}/res_a/server/main.lua`]: 'exports.res_b:channelOf(1)\n',
  });
  assert.equal(out.length, 1);
});

test('ignore entries silence a call; stale entries warn', async () => {
  const out = await run(check, {
    ...base,
    [`${R}/res_a/server/main.lua`]: 'exports.res_b:channelOf(1)\n',
  }, { checks: { 'export-calls': { ignore: { 'res_b:channelOf': 'optional hook', 'res_b:channelLabel': 'old' } } } });
  assert.equal(out.length, 1);
  assert.equal(out[0].severity, 'warn');
  assert.match(out[0].message, /res_b:channelLabel/);
});

test('duplicate declaration on the same side is flagged; server vs client is not', async () => {
  const dup = await run(check, {
    ...base,
    [`${R}/res_b/server/garage.lua`]: "exports('channelLabel', function(a, b) end)\n",
  });
  assert.equal(dup.length, 1);
  assert.match(dup[0].message, /2 times/);

  const split = await run(check, {
    ...base,
    [`${R}/res_b/client/main.lua`]: "exports('channelLabel', function() end)\n",
  });
  assert.deepEqual(split, []);

  const shared = await run(check, {
    ...base,
    [`${R}/res_b/shared/util.lua`]: "exports('channelLabel', function() end)\n",
  });
  assert.equal(shared.length, 1);

  const allowed = await run(check, {
    ...base,
    [`${R}/res_b/server/garage.lua`]: "exports('channelLabel', function(a, b) end)\n",
  }, { checks: { 'export-calls': { ignoreDuplicates: { 'res_b:channelLabel': 'intended override' } } } });
  assert.deepEqual(allowed, []);
});

test('zero Lua files is an error, not a pass', async () => {
  const out = await run(check, { 'README.md': 'x' });
  assert.equal(out.length, 1);
  assert.match(out[0].message, /scanned 0/);
});
