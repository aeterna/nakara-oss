import assert from 'node:assert/strict';
import { test } from 'node:test';
import check, { nulLines } from '../../src/checks/nul-bytes.js';
import { run } from './fixture.js';

test('nulLines cases', () => {
  const cases = [
    [Buffer.from('ok\nclean\n'), []],
    [Buffer.from('a\nb\x00c\n'), [2]],
    [Buffer.from('\x00\n\n\x00\x00\n'), [1, 3]],
    [Buffer.from('return s.replace(/[\\x00-\\x1f]/g)'), []],
    [Buffer.from('s.replace(/[\x00-\x1f]/g)'), [1]],
  ];
  for (const [buf, want] of cases) {
    assert.deepEqual(nulLines(buf), want);
    assert.deepEqual(nulLines(buf.toString('utf8')), want);
  }
});

test('flags text files with raw NUL, ignores binaries and ignorePaths', async () => {
  const out = await run(check, {
    'resources/r/client/a.lua': 'local x = 1\n-- bad\x00byte\n',
    'resources/r/html/app.tsx': 'ok',
    'web/x.js': 'const re = /[\x00-\x1f]/;',
    'stream/model.ydd': 'bin\x00ary',
    'node_modules/dep/index.js': '\x00',
  });
  assert.deepEqual(out.map((f) => [f.rel, f.line]).sort(), [['resources/r/client/a.lua', 2], ['web/x.js', 1]]);
});

test('paths and extensions are configurable', async () => {
  const out = await run(check, {
    'resources/a.lua': '\x00',
    'other/b.lua': '\x00',
    'other/c.txt': '\x00',
  }, { checks: { 'nul-bytes': { paths: ['other'], extensions: ['.lua', '.txt'] } } });
  assert.deepEqual(out.map((f) => f.rel).sort(), ['other/b.lua', 'other/c.txt']);
});

test('zero text files is an error', async () => {
  const out = await run(check, { 'a.png': 'x' });
  assert.match(out[0].message, /scanned 0/);
});
