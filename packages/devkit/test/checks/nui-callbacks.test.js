import assert from 'node:assert/strict';
import { test } from 'node:test';
import check from '../../src/checks/nui-callbacks.js';
import { MANIFEST, run } from './fixture.js';

const R = 'resources/menu';

test('flags a callback nothing in the page posts', async () => {
  const out = await run(check, {
    [`${R}/fxmanifest.lua`]: MANIFEST + "ui_page 'html/index.html'\n",
    [`${R}/client/main.lua`]: "RegisterNUICallback('menu_select', function() end)\nRegisterNUICallback('menu_close', function() end)\n",
    [`${R}/html/app.js`]: "post('menu_select', {})\n",
  });
  assert.equal(out.length, 1);
  assert.equal(out[0].line, 2);
  assert.match(out[0].message, /'menu_close'/);
});

test('poster under the ui_page directory (not html/) counts; any quote style counts', async () => {
  const out = await run(check, {
    [`${R}/fxmanifest.lua`]: MANIFEST + "ui_page 'dist/index.html'\n",
    [`${R}/client/main.lua`]: "RegisterNUICallback('a', cb)\nRegisterNUICallback(\"b\", cb)\nRegisterNUICallback('c', cb)\n",
    [`${R}/dist/index.js`]: 'send("a"); send(`b`)',
    [`${R}/web-src/x.ts`]: "send('c')",
  });
  assert.deepEqual(out, []);
});

test('a name that is only a substring does not count; ignore option silences', async () => {
  const files = {
    [`${R}/fxmanifest.lua`]: MANIFEST,
    [`${R}/client/main.lua`]: "RegisterNUICallback('close', cb)\n",
    [`${R}/html/app.js`]: "post('close_all')",
  };
  assert.equal((await run(check, files)).length, 1);
  assert.deepEqual(await run(check, files, { checks: { 'nui-callbacks': { ignore: { 'menu:close': 'posted by a shared bundle' } } } }), []);
});

test('zero Lua files is an error', async () => {
  const out = await run(check, {});
  assert.match(out[0].message, /scanned 0/);
});
