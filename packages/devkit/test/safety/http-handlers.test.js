import assert from 'node:assert/strict';
import test from 'node:test';
import { js, lua, of, oss } from './helpers.js';

// ---- undeclared-http-handler / over-declared ---------------------------------------------------
test('undeclared-http-handler: JS SetHttpHandler with no declaration is an error', async () => {
  const f = await js("SetHttpHandler((req, res) => { res.send('ok'); });");
  const hits = of(f, 'undeclared-http-handler');
  assert.equal(hits.length, 1);
  assert.equal(hits[0].severity, 'error');
  assert.match(hits[0].message, /httpHandlers/);
});

test('undeclared-http-handler: declared JS handler is clean', async () => {
  const f = await js("SetHttpHandler((req, res) => { res.send('ok'); });", {
    ossJson: oss({ httpHandlers: ['upload', 'upload/*'] }),
  });
  assert.equal(of(f, 'undeclared-http-handler').length, 0);
  assert.equal(of(f, 'over-declared').length, 0);
  assert.equal(of(f, 'missing-manifest').length, 0);
});

test('undeclared-http-handler: Lua SetHttpHandler with no declaration is an error', async () => {
  const f = await lua("SetHttpHandler(function(req, res) res.send('ok') end)");
  const hits = of(f, 'undeclared-http-handler');
  assert.equal(hits.length, 1);
  assert.equal(hits[0].severity, 'error');
  assert.match(hits[0].message, /httpHandlers/);
});

test('over-declared: httpHandlers declared with no SetHttpHandler warns', async () => {
  const f = await lua('local a = 1', { ossJson: oss({ httpHandlers: ['policy/*'] }) });
  const hits = of(f, 'over-declared').filter((x) => /httpHandlers/.test(x.message));
  assert.equal(hits.length, 1);
  assert.equal(hits[0].severity, 'warn');
  assert.match(hits[0].message, /httpHandlers/);
});
