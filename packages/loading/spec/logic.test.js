// spec/logic.test.js -- node --test twin of spec/loading_spec.lua, run against html/logic.js,
// so the page's rules and the Lua rules (shared/logic/loading.lua) cannot drift.
//   node --test packages/loading/spec/
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import config from '../html/config.json' with { type: 'json' };
import locale from '../html/locale.json' with { type: 'json' };

await import('../html/logic.js');
const L = globalThis.AeternaLoadingLogic;

const fields = (errors) => errors.map((e) => e.field).sort();
const run = (msgs) => msgs.reduce((s, m) => L.reduce(s, m), L.newState());
const rep = (c, n) => c.repeat(n);

describe('1. Config validation', () => {
  test('accepts the shipped defaults with no errors', () => {
    const { config: cfg, errors } = L.validateConfig(L.defaults());
    assert.deepEqual(errors, []);
    assert.deepEqual(cfg, L.defaults());
  });

  test('the shipped html/config.json equals the defaults', () => {
    assert.deepEqual(config, L.defaults());
  });

  test('replaces a config that is not an object with the defaults and one error', () => {
    for (const raw of ['nope', null, [1, 2], 5]) {
      const { config: cfg, errors } = L.validateConfig(raw);
      assert.deepEqual(fields(errors), ['config']);
      assert.deepEqual(cfg, L.defaults());
    }
  });

  test('uses the default for a missing field without an error', () => {
    const { config: cfg, errors } = L.validateConfig({ serverName: 'Harbour' });
    assert.deepEqual(errors, []);
    assert.equal(cfg.serverName, 'Harbour');
    assert.equal(cfg.tipSeconds, 8);
    assert.equal(cfg.audio.volume, 0.3);
  });

  const cases = [
    ['serverName', { serverName: rep('a', 41) }],
    ['serverName', { serverName: '' }],
    ['serverName', { serverName: 12 }],
    ['tagline', { tagline: rep('a', 81) }],
    ['lang', { lang: 'de' }],
    ['preset', { preset: 'neon' }],
    ['background', { background: 'custom/bg.gif' }],
    ['background', { background: `custom/${rep('a', 120)}.jpg` }],
    ['tips', { tips: 'one tip' }],
    ['tips', { tips: [rep('a', 161)] }],
    ['tips', { tips: ['ok', 5] }],
    ['tipSeconds', { tipSeconds: 3 }],
    ['tipSeconds', { tipSeconds: 31 }],
    ['tipSeconds', { tipSeconds: '8' }],
    ['audio.src', { audio: { src: 'custom/a.wav' } }],
    ['audio.autoplay', { audio: { autoplay: 'yes' } }],
    ['audio.volume', { audio: { volume: 1.5 } }],
    ['audio.volume', { audio: { volume: -0.1 } }],
    ['shutdown.fallbackSeconds', { shutdown: { fallbackSeconds: 9 } }],
    ['shutdown.fallbackSeconds', { shutdown: { fallbackSeconds: 121 } }],
  ];
  for (const [field, patch] of cases) {
    test(`fails only ${field} and falls back to its default (${JSON.stringify(patch).slice(0, 40)})`, () => {
      const raw = L.defaults();
      raw.serverName = 'Harbour';
      for (const [k, v] of Object.entries(patch)) {
        if (v && typeof v === 'object' && !Array.isArray(v)) Object.assign(raw[k], v);
        else raw[k] = v;
      }
      const { config: cfg, errors } = L.validateConfig(raw);
      assert.deepEqual(fields(errors), [field]);
      const expected = L.defaults();
      if (field !== 'serverName') expected.serverName = 'Harbour';
      assert.deepEqual(cfg, expected);
    });
  }

  test('accepts the edges of every limit', () => {
    const th40 = rep('ก', 40);
    const { config: cfg, errors } = L.validateConfig({
      serverName: th40,
      tagline: rep('ข', 80),
      lang: 'th',
      preset: 'night-market',
      background: 'custom/bg.webp',
      tips: Array.from({ length: 30 }, () => rep('ค', 160)),
      tipSeconds: 30,
      audio: { src: 'custom/theme.ogg', autoplay: true, volume: 1 },
      shutdown: { fallbackSeconds: 120 },
    });
    assert.deepEqual(errors, []);
    assert.equal(cfg.serverName, th40);
    assert.equal(cfg.tips.length, 30);
    assert.equal(cfg.audio.autoplay, true);
  });

  test('refuses 31 tips', () => {
    const { errors } = L.validateConfig({ tips: Array.from({ length: 31 }, () => 'tip') });
    assert.deepEqual(fields(errors), ['tips']);
  });

  test('accepts an empty tip list and an empty tagline', () => {
    const { config: cfg, errors } = L.validateConfig({ tips: [], tagline: '' });
    assert.deepEqual(errors, []);
    assert.deepEqual(cfg.tips, []);
  });

  test('refuses paths outside the resource or with a wrong extension', () => {
    const bad = ['/x.jpg', '/custom/bg.jpg', '../bg.jpg', 'custom/../../bg.jpg', 'http://example.com/bg.jpg',
      'http:bg.jpg', '//example.com/bg.jpg', 'custom//bg.jpg', 'custom/bg.png.exe', 'custom/bg', 'nui:x.png'];
    for (const p of bad) {
      assert.equal(L.isLocalPath(p, L.IMAGE_EXT), false, p);
      assert.deepEqual(fields(L.validateConfig({ background: p }).errors), ['background'], p);
    }
    assert.equal(L.isLocalPath('custom/bg.jpg', L.IMAGE_EXT), true);
    assert.equal(L.isLocalPath('custom/bg.png', L.IMAGE_EXT), true);
    assert.equal(L.isLocalPath('custom/theme.mp3', L.AUDIO_EXT), true);
    assert.equal(L.isLocalPath('custom/theme.mp3', L.IMAGE_EXT), false);
    assert.equal(L.isLocalPath('custom/bg.jpg', L.AUDIO_EXT), false);
  });

  test('reports several bad fields at once, each falling back on its own', () => {
    const { config: cfg, errors } = L.validateConfig({ lang: 'xx', tipSeconds: 100, serverName: 'Harbour' });
    assert.deepEqual(fields(errors), ['lang', 'tipSeconds']);
    assert.equal(cfg.serverName, 'Harbour');
    assert.equal(cfg.lang, 'en');
    assert.equal(cfg.tipSeconds, 8);
  });
});

describe('2. Stage reducer', () => {
  test('starts with no stage', () => {
    const s = L.newState();
    assert.equal(s.stage, 0);
    assert.equal(s.percent, null);
  });

  test('goes Map -> Scripts -> Character in order with real percentages', () => {
    let s = L.newState();
    s = L.reduce(s, { eventName: 'startDataFileEntries', count: 4 });
    assert.equal(s.stage, L.STAGE.MAP);
    assert.equal(s.percent, 0);
    s = L.reduce(s, { eventName: 'onDataFileEntry', name: 'a', type: 1, isNew: true });
    assert.equal(s.percent, 25);
    s = L.reduce(s, { eventName: 'onDataFileEntry', name: 'b' });
    s = L.reduce(s, { eventName: 'onDataFileEntry', name: 'c' });
    assert.equal(s.percent, 75);
    s = L.reduce(s, { eventName: 'startInitFunctionOrder', type: 'INIT_SESSION', order: 1, count: 10 });
    assert.equal(s.stage, L.STAGE.SCRIPTS);
    assert.equal(s.percent, 0);
    s = L.reduce(s, { eventName: 'initFunctionInvoking', type: 'INIT_SESSION', name: 'x', idx: 5 });
    assert.equal(s.percent, 50);
    s = L.reduce(s, { type: 'aeterna_loading:stage', stage: 'character' });
    assert.equal(s.stage, L.STAGE.CHARACTER);
    assert.equal(s.percent, null);
  });

  test('sums init function orders into one percentage', () => {
    const s = run([
      { eventName: 'startInitFunctionOrder', type: 'INIT_SESSION', order: 1, count: 4 },
      { eventName: 'initFunctionInvoking', idx: 3 },
      { eventName: 'startInitFunctionOrder', type: 'INIT_SESSION', order: 2, count: 4 },
      { eventName: 'initFunctionInvoking', idx: 3 },
    ]);
    assert.equal(s.percent, 87);
  });

  test('ignores unknown and malformed messages', () => {
    let s = run([{ eventName: 'startDataFileEntries', count: 2 }, { eventName: 'onDataFileEntry' }]);
    const before = s.percent;
    for (const msg of [{ eventName: 'somethingNew' }, { type: 'other:stage', stage: 'character' },
      { type: 'aeterna_loading:stage', stage: 'unknown' }, {}, 'text', 42, false, null, undefined,
      { eventName: 'startDataFileEntries', count: 'many' }, { eventName: 'initFunctionInvoking', idx: 1 }]) {
      s = L.reduce(s, msg);
    }
    assert.equal(s.stage, L.STAGE.MAP);
    assert.equal(s.percent, before);
  });

  test('never goes back to an earlier stage', () => {
    let s = run([
      { eventName: 'startInitFunctionOrder', type: 'INIT_SESSION', order: 1, count: 2 },
      { eventName: 'startDataFileEntries', count: 4 },
      { eventName: 'onDataFileEntry' },
    ]);
    assert.equal(s.stage, L.STAGE.SCRIPTS);
    assert.equal(s.percent, 0);
    s = L.reduce(s, { type: 'aeterna_loading:stage', stage: 'character' });
    s = L.reduce(s, { eventName: 'startInitFunctionOrder', type: 'INIT_SESSION', order: 2, count: 3 });
    assert.equal(s.stage, L.STAGE.CHARACTER);
    assert.equal(s.percent, null);
  });

  test('never lowers a percentage when a later order grows the total', () => {
    let s = run([
      { eventName: 'startInitFunctionOrder', type: 'INIT_SESSION', order: 1, count: 2 },
      { eventName: 'initFunctionInvoking', idx: 2 },
    ]);
    assert.equal(s.percent, 100);
    s = L.reduce(s, { eventName: 'startInitFunctionOrder', type: 'INIT_SESSION', order: 2, count: 8 });
    assert.equal(s.percent, 100);
    s = L.reduce(s, { eventName: 'initFunctionInvoking', idx: 1 });
    assert.equal(s.percent, 100);
  });

  test('never lowers the map percentage when more entries arrive', () => {
    const s = run([
      { eventName: 'startDataFileEntries', count: 2 },
      { eventName: 'onDataFileEntry' },
      { eventName: 'startDataFileEntries', count: 6 },
    ]);
    assert.equal(s.percent, 50);
  });

  test('uses loadFraction for Scripts when it is higher', () => {
    let s = run([
      { eventName: 'startInitFunctionOrder', type: 'INIT_SESSION', order: 1, count: 10 },
      { eventName: 'initFunctionInvoking', idx: 2 },
    ]);
    assert.equal(s.percent, 20);
    s = L.reduce(s, { eventName: 'loadProgress', loadFraction: 0.64 });
    assert.equal(s.percent, 64);
    s = L.reduce(s, { eventName: 'loadProgress', loadFraction: 0.3 });
    assert.equal(s.percent, 64);
    s = L.reduce(s, { eventName: 'initFunctionInvoking', idx: 9 });
    assert.equal(s.percent, 90);
    s = L.reduce(s, { eventName: 'loadProgress', loadFraction: 7 });
    assert.equal(s.percent, 100);
  });

  test('does not use loadFraction for the Map stage', () => {
    const s = run([{ eventName: 'startDataFileEntries', count: 10 }, { eventName: 'loadProgress', loadFraction: 0.9 }]);
    assert.equal(s.percent, 0);
  });

  test('marks closing on the closing message without changing the stage', () => {
    const s = run([{ eventName: 'startDataFileEntries', count: 1 }, { type: 'aeterna_loading:closing' }]);
    assert.equal(s.closing, true);
    assert.equal(s.stage, L.STAGE.MAP);
  });

  test('does not change the state it was given', () => {
    const s = L.newState();
    const s2 = L.reduce(s, { eventName: 'startDataFileEntries', count: 3 });
    assert.equal(s.stage, 0);
    assert.equal(s2.stage, 1);
  });

  test('says "still loading" after 20 s without a message', () => {
    assert.equal(L.isStill(1000, 20999), false);
    assert.equal(L.isStill(1000, 21000), true);
  });
});

describe('3. Tip rotation', () => {
  test('rotates the tips in order and wraps around', () => {
    const tips = ['a', 'b', 'c'];
    assert.equal(L.tipAt(tips, 8, 0), 0);
    assert.equal(L.tipAt(tips, 8, 7999), 0);
    assert.equal(L.tipAt(tips, 8, 8000), 1);
    assert.equal(L.tipAt(tips, 8, 16000), 2);
    assert.equal(L.tipAt(tips, 8, 24000), 0);
  });

  test('clamps tipSeconds to 4-30', () => {
    assert.equal(L.clampTipSeconds(1), 4);
    assert.equal(L.clampTipSeconds(99), 30);
    assert.equal(L.clampTipSeconds(12), 12);
    assert.equal(L.clampTipSeconds('x'), 8);
    assert.equal(L.tipAt(['a', 'b'], 1, 4000), 1);
    assert.equal(L.tipAt(['a', 'b'], 99, 29999), 0);
  });

  test('hides the tip line for an empty list', () => {
    assert.equal(L.tipAt([], 8, 0), null);
    assert.equal(L.tipAt(null, 8, 0), null);
  });
});

describe('Locale', () => {
  const KEYS = ['loading.stage.map', 'loading.stage.scripts', 'loading.stage.character', 'loading.still',
    'loading.audio.play', 'loading.audio.mute', 'loading.tip'];

  test('html/locale.json has every key in th and en, and nothing else', () => {
    assert.deepEqual(Object.keys(locale).sort(), ['en', 'th']);
    for (const lang of ['th', 'en']) assert.deepEqual(Object.keys(locale[lang]).sort(), [...KEYS].sort(), lang);
  });

  test('a missing key falls back to en, then to the key itself', () => {
    const table = { th: { a: 'ก' }, en: { a: 'A', b: 'B' } };
    assert.equal(L.t(table, 'th', 'a'), 'ก');
    assert.equal(L.t(table, 'th', 'b'), 'B');
    assert.equal(L.t(table, 'th', 'c'), 'c');
    assert.equal(L.t(null, 'en', 'c'), 'c');
  });
});
