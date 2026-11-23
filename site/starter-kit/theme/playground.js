// Theme playground: switches data-preset on the .kit-stage element and shows the resolved token values.
// Text is set with textContent only.
(function () {
  var stage = document.getElementById('kit-stage');
  var cfg = document.getElementById('cfg-preset');
  var body = document.getElementById('tok-body');
  var buttons = document.querySelectorAll('.preset-btn');
  if (!stage || !buttons.length) return;

  var TOKENS = ['--surface', '--raised', '--text', '--text-2', '--text-3', '--line', '--track',
    '--accent', '--on-accent', '--good', '--warn', '--bad'];

  function renderTokens() {
    if (!body || !window.getComputedStyle) return;
    var cs = window.getComputedStyle(stage);
    while (body.firstChild) body.removeChild(body.firstChild);
    TOKENS.forEach(function (name) {
      var value = cs.getPropertyValue(name).trim();
      var tr = document.createElement('tr');
      var tdName = document.createElement('td');
      var code = document.createElement('code');
      code.textContent = name;
      tdName.appendChild(code);
      var tdSw = document.createElement('td');
      var sw = document.createElement('span');
      sw.className = 'tok-sw';
      sw.style.background = value;
      tdSw.appendChild(sw);
      var tdVal = document.createElement('td');
      tdVal.className = 'mono';
      tdVal.textContent = value;
      tr.appendChild(tdName);
      tr.appendChild(tdSw);
      tr.appendChild(tdVal);
      body.appendChild(tr);
    });
  }

  function choose(name) {
    stage.setAttribute('data-preset', name);
    Array.prototype.forEach.call(buttons, function (b) {
      b.setAttribute('aria-pressed', b.getAttribute('data-preset') === name ? 'true' : 'false');
    });
    if (cfg) cfg.textContent = 'setr aeterna_theme_preset "' + name + '"';
    renderTokens();
  }

  Array.prototype.forEach.call(buttons, function (b) {
    b.addEventListener('click', function () { choose(b.getAttribute('data-preset')); });
  });
  choose(stage.getAttribute('data-preset') || 'asphalt');
})();
