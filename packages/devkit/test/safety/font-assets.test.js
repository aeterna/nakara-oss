import assert from 'node:assert/strict';
import test from 'node:test';
import { of, scan } from './helpers.js';

const FAKE_FONT = Buffer.from('fake-font-fixture-not-real-font-data');
const OFL_TEXT = 'SIL Open Font License 1.1 (fixture placeholder)\n';

test('font-assets: allows .woff2 inside packages/<pkg>/html/fonts/ with OFL.txt under 1 MB', async () => {
  const f = await scan(
    {
      'html/fonts/IBMPlexSansThai-Regular.woff2': FAKE_FONT,
      'html/fonts/IBMPlexSansThai-SemiBold.woff2': FAKE_FONT,
      'html/fonts/OFL.txt': OFL_TEXT,
    },
    { name: 'packages/uikit' },
  );
  assert.equal(of(f, 'font-assets').length, 0);

  // exact 1 MB (1,048,576 bytes) boundary passes
  const atLimit = await scan(
    {
      'html/fonts/Regular.woff2': Buffer.alloc(512 * 1024, 0x41),
      'html/fonts/Bold.woff2': Buffer.alloc(512 * 1024, 0x42),
      'html/fonts/OFL.txt': OFL_TEXT,
    },
    { name: 'packages/uikit' },
  );
  assert.equal(of(atLimit, 'font-assets').length, 0);
});

test('font-assets: rejects .woff2 outside html/fonts/', async () => {
  for (const badPath of ['html/Regular.woff2', 'fonts/Regular.woff2', 'web/fonts/Regular.woff2', 'html/fonts/nested/Regular.woff2']) {
    const f = await scan(
      {
        [badPath]: FAKE_FONT,
        'html/fonts/OFL.txt': OFL_TEXT,
      },
      { name: 'packages/uikit' },
    );
    const hits = of(f, 'font-assets');
    assert.equal(hits.length, 1, `expected 1 font-assets error for ${badPath}`);
    assert.equal(hits[0].severity, 'error');
    assert.match(hits[0].message, /html\/fonts\//);
  }
});

test('font-assets: rejects .woff2 in html/fonts/ when OFL.txt is missing', async () => {
  const missing = await scan(
    {
      'html/fonts/Regular.woff2': FAKE_FONT,
    },
    { name: 'packages/uikit' },
  );
  const hits = of(missing, 'font-assets');
  assert.equal(hits.length, 1);
  assert.equal(hits[0].severity, 'error');
  assert.match(hits[0].message, /OFL\.txt/);

  // OFL.txt in the wrong directory does not satisfy html/fonts/OFL.txt
  const wrongDir = await scan(
    {
      'html/fonts/Regular.woff2': FAKE_FONT,
      'OFL.txt': OFL_TEXT,
    },
    { name: 'packages/uikit' },
  );
  assert.equal(of(wrongDir, 'font-assets').length, 1);
});

test('font-assets: rejects package when total font size in html/fonts/ exceeds 1 MB', async () => {
  const combined = await scan(
    {
      'html/fonts/Regular.woff2': Buffer.alloc(600 * 1024, 0x41),
      'html/fonts/Bold.woff2': Buffer.alloc(600 * 1024, 0x42),
      'html/fonts/OFL.txt': OFL_TEXT,
    },
    { name: 'packages/uikit' },
  );
  const hits = of(combined, 'font-assets');
  assert.equal(hits.length, 1);
  assert.equal(hits[0].severity, 'error');
  assert.match(hits[0].message, /1 MB/);

  const singleOver = await scan(
    {
      'html/fonts/Giant.woff2': Buffer.alloc(1024 * 1024 + 1, 0x41),
      'html/fonts/OFL.txt': OFL_TEXT,
    },
    { name: 'packages/uikit' },
  );
  assert.equal(of(singleOver, 'font-assets').length, 1);
});

test('font-assets: rejects .ttf, .otf, .woff and .eot font files anywhere under packages/*', async () => {
  for (const ext of ['.ttf', '.otf', '.woff', '.eot']) {
    const f = await scan(
      {
        [`html/fonts/Font${ext}`]: FAKE_FONT,
        'html/fonts/OFL.txt': OFL_TEXT,
      },
      { name: 'packages/uikit' },
    );
    const hits = of(f, 'font-assets');
    assert.equal(hits.length, 1, `expected 1 font-assets error for ${ext}`);
    assert.equal(hits[0].severity, 'error');
    assert.match(hits[0].message, new RegExp(`\\${ext}\\b`));
  }
});

test('font-assets: rejects .svg files anywhere under packages/*', async () => {
  for (const svgPath of ['html/icon.svg', 'html/fonts/icon.svg', 'web/ui/logo.svg']) {
    const f = await scan(
      {
        [svgPath]: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"></svg>',
      },
      { name: 'packages/uikit' },
    );
    const hits = of(f, 'font-assets');
    assert.equal(hits.length, 1, `expected 1 font-assets error for ${svgPath}`);
    assert.equal(hits[0].severity, 'error');
    assert.match(hits[0].message, /\.svg\b/);
  }
});

test('font-assets: leaves launcher/assets/** untouched', async () => {
  const f = await scan(
    {
      'assets/Anuphan-Regular.ttf': FAKE_FONT,
      'assets/Anuphan-Bold.otf': FAKE_FONT,
      'assets/logo.svg': '<svg xmlns="http://www.w3.org/2000/svg"></svg>',
    },
    { name: 'launcher' },
  );
  assert.equal(of(f, 'font-assets').length, 0);

  const nested = await scan(
    {
      'launcher/assets/Anuphan-Regular.ttf': FAKE_FONT,
      'launcher/assets/icon.svg': '<svg xmlns="http://www.w3.org/2000/svg"></svg>',
    },
    { name: 'packages/uikit' },
  );
  assert.equal(of(nested, 'font-assets').length, 0);
});

test('font-assets: ignores resources outside packages/ (e.g. resources/foo)', async () => {
  const f = await scan(
    {
      'html/logo.svg': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"></svg>',
      'html/fonts/Font.ttf': FAKE_FONT,
    },
    { name: 'resources/foo' },
  );
  assert.equal(of(f, 'font-assets').length, 0);
});
