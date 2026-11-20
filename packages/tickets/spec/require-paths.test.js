const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const Module = require('node:module');

const packageRoot = path.resolve(__dirname, '..');
const serverJs = path.join(packageRoot, 'server', 'js');

const stubbedGlobals = [
  'GetConvar',
  'GetResourceKvpString',
  'SetResourceKvp',
  'DeleteResourceKvp',
  'RegisterCommand',
  'exports',
  'GetCurrentResourceName',
];

function clearServerCache() {
  for (const key of Object.keys(require.cache)) {
    if (key.startsWith(serverJs + path.sep)) {
      delete require.cache[key];
    }
  }
}

test('server scripts load with FXServer resource-root require resolution', () => {
  const originalResolveFilename = Module._resolveFilename;
  const originalSetTimeout = globalThis.setTimeout;
  const originalSetInterval = globalThis.setInterval;
  const originals = {};
  for (const name of stubbedGlobals) originals[name] = globalThis[name];

  globalThis.GetConvar = (name, def) => def;
  globalThis.GetResourceKvpString = () => null;
  globalThis.SetResourceKvp = () => {};
  globalThis.DeleteResourceKvp = () => {};
  globalThis.RegisterCommand = () => {};
  globalThis.exports = () => {};
  globalThis.GetCurrentResourceName = () => 'nakara_tickets';
  globalThis.setTimeout = () => 0;
  globalThis.setInterval = () => 0;

  // Emulate FXServer: a relative request resolves against the resource root, not the requiring file.
  Module._resolveFilename = function (request, parent, isMain, options) {
    if (typeof request === 'string' && request.startsWith('.')) {
      return originalResolveFilename.call(this, path.resolve(packageRoot, request), parent, isMain, options);
    }
    return originalResolveFilename.call(this, request, parent, isMain, options);
  };

  try {
    clearServerCache();

    // The patched resolver turns this literal into <packageRoot>/server/js/main.js, like FXServer does.
    const main = require('./server/js/main.js');

    assert.equal(typeof main.collectOnlinePlayers, 'function');
    assert.equal(typeof main.heartbeatTick, 'function');
    assert.equal(typeof main.stop, 'function');

    main.stop();
  } finally {
    Module._resolveFilename = originalResolveFilename;
    globalThis.setTimeout = originalSetTimeout;
    globalThis.setInterval = originalSetInterval;
    for (const name of stubbedGlobals) {
      if (originals[name] === undefined) delete globalThis[name];
      else globalThis[name] = originals[name];
    }
    clearServerCache();
  }
});
