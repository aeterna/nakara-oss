// aeterna_loading page: reads its own config.json and locale.json, follows FiveM's loadscreen messages and the
// client script's SendLoadingScreenMessage, and draws the stages. Text is set with textContent only.
(function () {
  'use strict';

  const L = globalThis.AeternaLoadingLogic;
  const $ = (id) => document.getElementById(id);
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const startedAt = Date.now();

  let config = L.defaults();
  let locale = null;
  let state = L.newState();
  let lastMessageAt = startedAt;
  let tipIndex = null;
  let audio = null;
  let audioMuted = false;

  const t = (key) => L.t(locale, config.lang, key);

  // ---- Files of this resource (literal relative URLs, so the safety scanner can see they stay local) ----

  function readJson(request) {
    return request.then((res) => (res.ok ? res.json() : null)).catch(() => null);
  }

  // ---- Static text and config ------------------------------------------------------------------

  function applyConfig() {
    const root = document.documentElement;
    root.dataset.preset = config.preset;
    root.lang = config.lang;

    $('name').textContent = config.serverName;
    $('tagline').textContent = config.tagline;
    $('tagline').hidden = config.tagline === '';
    for (const el of document.querySelectorAll('[data-key]')) el.textContent = t(el.dataset.key);

    if (config.background !== '') {
      const img = document.createElement('img');
      img.alt = '';
      img.addEventListener('error', () => img.remove());
      img.src = config.background;
      $('backdrop').appendChild(img);
    }
    setupAudio();
  }

  // ---- Stages ----------------------------------------------------------------------------------

  function render() {
    for (const li of document.querySelectorAll('.stage')) {
      const n = Number(li.dataset.stage);
      const current = n === state.stage;
      li.classList.toggle('is-done', n < state.stage);
      li.classList.toggle('is-current', current);
      li.querySelector('.pct').textContent = current && state.percent !== null ? `${state.percent}%` : '';
      if (current) li.setAttribute('aria-current', 'step');
      else li.removeAttribute('aria-current');
    }

    const bar = $('bar');
    const indeterminate = state.stage === L.STAGE.CHARACTER;
    bar.classList.toggle('is-indeterminate', indeterminate);
    if (indeterminate || state.percent === null) {
      bar.removeAttribute('aria-valuenow');
      $('fill').style.width = '';
    } else {
      bar.setAttribute('aria-valuenow', String(state.percent));
      $('fill').style.width = `${state.percent}%`;
    }
  }

  function onMessage(event) {
    let data = event.data;
    if (typeof data === 'string') {
      try { data = JSON.parse(data); } catch (_) { return; }
    }
    const next = L.reduce(state, data);
    if (next === state) return;
    const wasClosing = state.closing;
    state = next;
    lastMessageAt = Date.now();
    render();
    if (state.closing && !wasClosing) fadeOutAudio();
  }

  // ---- Tips and "still loading" ----------------------------------------------------------------

  function showTip(index) {
    const tip = $('tip');
    if (index === null) {
      tip.hidden = true;
      return;
    }
    tip.hidden = false;
    const text = config.tips[index];
    if (reducedMotion.matches || tipIndex === null) {
      $('tip-text').textContent = text;
      return;
    }
    tip.classList.add('is-fading');
    setTimeout(() => {
      $('tip-text').textContent = text;
      tip.classList.remove('is-fading');
    }, 200);
  }

  function tick() {
    const now = Date.now();
    const index = L.tipAt(config.tips, config.tipSeconds, now - startedAt);
    if (index !== tipIndex) {
      showTip(index);
      tipIndex = index;
    }
    $('still').hidden = state.closing || !L.isStill(lastMessageAt, now);
  }

  // ---- Audio -----------------------------------------------------------------------------------

  function renderAudio() {
    const on = audio !== null && !audio.paused && !audioMuted;
    $('audio').classList.toggle('is-on', on);
    $('audio-label').textContent = t(on ? 'loading.audio.mute' : 'loading.audio.play');
  }

  function setupAudio() {
    if (config.audio.src === '') return;
    audio = new Audio(config.audio.src);
    audio.loop = true;
    audio.volume = config.audio.volume;
    audio.addEventListener('play', renderAudio);
    audio.addEventListener('pause', renderAudio);
    const button = $('audio');
    button.hidden = false;
    button.addEventListener('click', () => {
      if (audio.paused) {
        audioMuted = false;
        audio.muted = false;
        audio.play().catch(() => {});
      } else {
        audioMuted = !audioMuted;
        audio.muted = audioMuted;
      }
      renderAudio();
    });
    if (config.audio.autoplay) audio.play().catch(() => {});
    renderAudio();
  }

  // Over 1 s when the page is about to close (the client script waits for it).
  function fadeOutAudio() {
    if (audio === null || audio.paused) return;
    const from = audio.volume;
    const began = Date.now();
    const timer = setInterval(() => {
      const k = Math.min((Date.now() - began) / 1000, 1);
      audio.volume = from * (1 - k);
      if (k >= 1) {
        clearInterval(timer);
        audio.pause();
      }
    }, 50);
  }

  // ---- Start -----------------------------------------------------------------------------------

  window.addEventListener('message', onMessage);
  render();

  Promise.all([readJson(fetch('config.json')), readJson(fetch('locale.json'))]).then(([rawConfig, rawLocale]) => {
    config = L.validateConfig(rawConfig).config;
    locale = rawLocale;
    applyConfig();
    tick();
    setInterval(tick, 500);
  });
})();
