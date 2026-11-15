(function () {
  var svg = document.getElementById('flow');
  var btn = document.getElementById('flow-toggle');
  if (!svg || !btn) return;
  if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    btn.hidden = true;
    return;
  }
  var lab = document.getElementById('flow-lab');
  var icoPause = document.getElementById('flow-ico-pause');
  var icoPlay = document.getElementById('flow-ico-play');
  var isTh = (document.documentElement.lang || '').slice(0, 2) === 'th';
  var user = false, onScreen = true;
  if (icoPlay) { icoPlay.setAttribute('hidden', ''); icoPlay.hidden = true; }

  function sync() {
    if (svg.classList) {
      if (user || !onScreen) { svg.classList.add('paused'); }
      else { svg.classList.remove('paused'); }
    }
  }

  btn.addEventListener('click', function () {
    user = !user;
    btn.setAttribute('aria-pressed', user ? 'true' : 'false');
    if (lab) lab.textContent = user ? (isTh ? 'เล่น' : 'Play') : (isTh ? 'หยุด' : 'Pause');
    if (icoPause) {
      if (user) { icoPause.setAttribute('hidden', ''); icoPause.hidden = true; }
      else { icoPause.removeAttribute('hidden'); icoPause.hidden = false; }
    }
    if (icoPlay) {
      if (user) { icoPlay.removeAttribute('hidden'); icoPlay.hidden = false; }
      else { icoPlay.setAttribute('hidden', ''); icoPlay.hidden = true; }
    }
    sync();
  });

  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (entries) {
      if (entries && entries[0]) { onScreen = entries[0].isIntersecting; sync(); }
    }, { threshold: 0.1 }).observe(svg);
  }
})();
