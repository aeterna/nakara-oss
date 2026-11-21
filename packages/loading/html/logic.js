// Pure logic for the aeterna_loading page: the JS twin of shared/logic/loading.lua (config validation,
// stage reducer, tip rotation, locale lookup). No DOM access, so node --test can load it (spec/logic.test.js).
// Loaded by index.html as a plain script; it sets globalThis.AeternaLoadingLogic.
(function () {
  'use strict';

  const IMAGE_EXT = ['.jpg', '.png', '.webp'];
  const AUDIO_EXT = ['.ogg', '.mp3'];
  const STAGE = { NONE: 0, MAP: 1, SCRIPTS: 2, CHARACTER: 3 };
  const STILL_MS = 20000;
  const LANGS = ['th', 'en'];
  const PRESETS = ['asphalt', 'paper', 'night-market'];

  function defaults() {
    return {
      version: 1,
      serverName: 'My Server',
      tagline: '',
      lang: 'en',
      preset: 'asphalt',
      background: '',
      tips: ['Bind your keys in Settings → Key Bindings → FiveM'],
      tipSeconds: 8,
      audio: { src: '', autoplay: false, volume: 0.3 },
      shutdown: { fallbackSeconds: 30 },
    };
  }

  const isNumber = (v) => typeof v === 'number' && Number.isFinite(v);
  const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

  // Characters (code points), not UTF-16 units, matching utf8.len in the Lua twin.
  function textOk(v, minLen, maxLen) {
    if (typeof v !== 'string') return false;
    const n = Array.from(v).length;
    return n >= minLen && n <= maxLen;
  }

  // A path inside this resource's html/ folder: relative, no `..`, `:` or `//`, ending in one of `exts`.
  function isLocalPath(p, exts) {
    if (!textOk(p, 1, 120)) return false;
    if (p.startsWith('/') || p.includes('..') || p.includes(':') || p.includes('//')) return false;
    return exts.some((ext) => p.endsWith(ext));
  }

  const optionalPath = (exts) => (v) => v === '' || isLocalPath(v, exts);
  const rangeOk = (lo, hi) => (v) => isNumber(v) && v >= lo && v <= hi;
  const tipsOk = (v) => Array.isArray(v) && v.length <= 30 && v.every((tip) => textOk(tip, 1, 160));

  // Field name, path into the config, check. Order is the order of the spec's table.
  const FIELDS = [
    ['serverName', ['serverName'], (v) => textOk(v, 1, 40)],
    ['tagline', ['tagline'], (v) => textOk(v, 0, 80)],
    ['lang', ['lang'], (v) => LANGS.includes(v)],
    ['preset', ['preset'], (v) => PRESETS.includes(v)],
    ['background', ['background'], optionalPath(IMAGE_EXT)],
    ['tips', ['tips'], tipsOk],
    ['tipSeconds', ['tipSeconds'], rangeOk(4, 30)],
    ['audio.src', ['audio', 'src'], optionalPath(AUDIO_EXT)],
    ['audio.autoplay', ['audio', 'autoplay'], (v) => typeof v === 'boolean'],
    ['audio.volume', ['audio', 'volume'], rangeOk(0, 1)],
    ['shutdown.fallbackSeconds', ['shutdown', 'fallbackSeconds'], rangeOk(10, 120)],
  ];

  // Validate a parsed html/config.json. Returns { config, errors: [{ field, reason }] }.
  // A failing field falls back to its default; a missing field takes the default without an error.
  function validateConfig(raw) {
    const config = defaults();
    const errors = [];
    if (!isObject(raw)) {
      errors.push({ field: 'config', reason: 'not a JSON object' });
      return { config, errors };
    }
    for (const [name, path, check] of FIELDS) {
      let v = raw;
      for (const key of path) v = isObject(v) ? v[key] : undefined;
      if (v === undefined || v === null) continue;
      if (check(v)) {
        let target = config;
        for (const key of path.slice(0, -1)) target = target[key];
        target[path[path.length - 1]] = Array.isArray(v) ? v.slice() : v;
      } else {
        errors.push({ field: name, reason: 'outside its limits' });
      }
    }
    return { config, errors };
  }

  // ---- Stage reducer --------------------------------------------------------------------------

  function newState() {
    return {
      stage: STAGE.NONE,
      percent: null,
      closing: false,
      mapTotal: 0,
      mapDone: 0,
      orderBase: 0,
      orderCount: 0,
      orderIdx: 0,
      loadFraction: 0,
    };
  }

  const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);
  const wholePercent = (done, total) => (total <= 0 ? 0 : Math.floor(clamp(done / total, 0, 1) * 100));

  function enter(s, stage) {
    s.stage = stage;
    s.percent = stage === STAGE.CHARACTER ? null : 0; // Character: indeterminate bar
  }

  function raise(s, p) {
    if (s.percent === null || p > s.percent) s.percent = p;
  }

  function scriptsPercent(s) {
    const fromInit = wholePercent(s.orderBase + s.orderIdx, s.orderBase + s.orderCount);
    const fromLoad = Math.floor(clamp(s.loadFraction, 0, 1) * 100);
    return Math.max(fromInit, fromLoad);
  }

  const HANDLERS = {
    startDataFileEntries(s, m) {
      if (!isNumber(m.count) || m.count < 0 || s.stage > STAGE.MAP) return false;
      if (s.stage < STAGE.MAP) enter(s, STAGE.MAP);
      s.mapTotal += m.count;
      raise(s, wholePercent(s.mapDone, s.mapTotal));
      return true;
    },
    onDataFileEntry(s) {
      if (s.stage !== STAGE.MAP) return false;
      s.mapDone = Math.min(s.mapDone + 1, s.mapTotal);
      raise(s, wholePercent(s.mapDone, s.mapTotal));
      return true;
    },
    startInitFunctionOrder(s, m) {
      if (!isNumber(m.count) || m.count < 0 || s.stage > STAGE.SCRIPTS) return false;
      if (s.stage < STAGE.SCRIPTS) enter(s, STAGE.SCRIPTS);
      else s.orderBase += s.orderCount;
      s.orderCount = m.count;
      s.orderIdx = 0;
      raise(s, scriptsPercent(s));
      return true;
    },
    initFunctionInvoking(s, m) {
      if (!isNumber(m.idx) || s.stage !== STAGE.SCRIPTS) return false;
      s.orderIdx = clamp(m.idx, 0, s.orderCount);
      raise(s, scriptsPercent(s));
      return true;
    },
    loadProgress(s, m) {
      if (!isNumber(m.loadFraction)) return false;
      s.loadFraction = Math.max(s.loadFraction, clamp(m.loadFraction, 0, 1));
      if (s.stage === STAGE.SCRIPTS) raise(s, scriptsPercent(s));
      return true;
    },
  };

  // Apply one loading-screen message. Returns a new state; the given one is not changed.
  // A message the page does not know is ignored. A stage never goes backwards; a percentage never decreases.
  function reduce(state, msg) {
    if (!isObject(msg)) return state;
    const s = Object.assign({}, state);
    if (typeof msg.eventName === 'string') {
      const handler = Object.prototype.hasOwnProperty.call(HANDLERS, msg.eventName) ? HANDLERS[msg.eventName] : null;
      return handler && handler(s, msg) ? s : state;
    }
    if (msg.type === 'aeterna_loading:stage' && msg.stage === 'character') {
      if (s.stage >= STAGE.CHARACTER) return state;
      enter(s, STAGE.CHARACTER);
      return s;
    }
    if (msg.type === 'aeterna_loading:closing') {
      s.closing = true;
      return s;
    }
    return state;
  }

  const isStill = (lastAt, now) => now - lastAt >= STILL_MS;

  // ---- Tips and locale ------------------------------------------------------------------------

  const clampTipSeconds = (n) => (isNumber(n) ? clamp(n, 4, 30) : 8);

  // 0-based index of the tip to show after `elapsedMs`, or null to hide the tip line.
  function tipAt(tips, tipSeconds, elapsedMs) {
    if (!Array.isArray(tips) || tips.length === 0) return null;
    const step = clampTipSeconds(tipSeconds) * 1000;
    return Math.floor(Math.max(elapsedMs, 0) / step) % tips.length;
  }

  // Locale lookup: the page's language, then en, then the key itself.
  function t(table, lang, key) {
    const pick = (l) => (isObject(table) && isObject(table[l]) && typeof table[l][key] === 'string' ? table[l][key] : null);
    return pick(lang) ?? pick('en') ?? key;
  }

  globalThis.AeternaLoadingLogic = {
    IMAGE_EXT, AUDIO_EXT, STAGE, STILL_MS,
    defaults, isLocalPath, validateConfig,
    newState, reduce, isStill,
    clampTipSeconds, tipAt, t,
  };
})();
