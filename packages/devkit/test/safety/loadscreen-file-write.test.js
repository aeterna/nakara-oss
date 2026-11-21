import assert from 'node:assert/strict';
import test from 'node:test';
import { MANIFEST, js, lua, of, oss, scan } from './helpers.js';

// ---- undeclared-nui: the loadscreen manifest key -----------------------------------------------
test('undeclared-nui: a local loadscreen without nui is an error', async () => {
  const f = await scan({ 'html/loading.html': '<p>loading</p>' }, { manifest: MANIFEST + "loadscreen 'html/loading.html'\n" });
  const findings = of(f, 'undeclared-nui');
  assert.equal(findings.length, 1);
  assert.match(findings[0].message, /loadscreen/);
});

test('undeclared-nui: a local loadscreen with nui true is accepted and not over-declared', async () => {
  const f = await scan({ 'html/loading.html': '<p>loading</p>' }, {
    manifest: MANIFEST + "loadscreen 'html/loading.html'\n",
    ossJson: oss({ nui: true }),
  });
  assert.equal(of(f, 'undeclared-nui').length, 0);
  assert.equal(of(f, 'over-declared').length, 0);
});

// ---- undeclared-file-write: literal-prefix paths ----------------------------------------------
test('undeclared-file-write: Lua prefix concat covered by a declared glob is accepted and used', async () => {
  const f = await lua("SaveResourceFile(GetCurrentResourceName(), 'photos/' .. id .. '.jpg', data, -1)", {
    ossJson: oss({ files: { write: ['photos/*'] } }),
  });
  assert.equal(of(f, 'undeclared-file-write').length, 0);
  assert.equal(of(f, 'over-declared').length, 0);
});

test('undeclared-file-write: JS + and template prefix concat covered by a declared glob is accepted', async () => {
  const code = "SaveResourceFile(GetCurrentResourceName(), 'photos/' + id + '.jpg', data, -1);\n"
    + 'SaveResourceFile(GetCurrentResourceName(), `photos/${id}.jpg`, data, -1);';
  const f = await js(code, { ossJson: oss({ files: { write: ['photos/*'] } }) });
  assert.equal(of(f, 'undeclared-file-write').length, 0);
  assert.equal(of(f, 'over-declared').length, 0);
});

test('undeclared-file-write: a prefix containing .. is still an error', async () => {
  const f = await lua("SaveResourceFile(GetCurrentResourceName(), '../photos/' .. id .. '.jpg', data, -1)", {
    ossJson: oss({ files: { write: ['../photos/*'] } }),
  });
  const findings = of(f, 'undeclared-file-write');
  assert.equal(findings.length, 1);
  assert.match(findings[0].message, /unsafe literal prefix/);
});

test('undeclared-file-write: a path with no literal prefix is still an error', async () => {
  const f = await lua('SaveResourceFile(GetCurrentResourceName(), path, data, -1)', {
    ossJson: oss({ files: { write: ['*'] } }),
  });
  const findings = of(f, 'undeclared-file-write');
  assert.equal(findings.length, 1);
  assert.match(findings[0].message, /literal prefix/);
});

test('undeclared-file-write: a prefix no declared glob covers is still an error', async () => {
  const f = await lua("SaveResourceFile(GetCurrentResourceName(), 'photos/' .. id .. '.jpg', data, -1)", {
    ossJson: oss({ files: { write: ['cache/*'] } }),
  });
  const findings = of(f, 'undeclared-file-write');
  assert.equal(findings.length, 1);
  assert.match(findings[0].message, /not declared/);
});
