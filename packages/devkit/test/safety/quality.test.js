import assert from 'node:assert/strict';
import test from 'node:test';
import { js, lua, nui, of, oss, scan } from './helpers.js';

const count = async (p, id) => of(await p, id).length;
const SERVER_EV = oss({ netEvents: { server: ['nakara_test:*'], client: [] } });

// ---- net-event-rate-limit ----------------------------------------------------------------------
test('net-event-rate-limit: handler without a limiter warns', async () => {
  const f = await lua("RegisterNetEvent('nakara_test:give', function(n) GiveItem(source, n) end)", { ossJson: SERVER_EV });
  const w = of(f, 'net-event-rate-limit');
  assert.equal(w.length, 1);
  assert.equal(w[0].severity, 'warn');
});

test('net-event-rate-limit: default and configured limiter names', async () => {
  assert.equal(await count(lua("RegisterNetEvent('nakara_test:give', function(n)\n  if not NakaraCore.rateLimit(source, 'give') then return end\nend)", { ossJson: SERVER_EV }), 'net-event-rate-limit'), 0);
  assert.equal(await count(lua("RegisterNetEvent('nakara_test:give', function() if not exports.mylib:eventOk(source) then return end end)", { ossJson: SERVER_EV }), 'net-event-rate-limit'), 1);
  assert.equal(await count(lua("RegisterNetEvent('nakara_test:give', function() if not exports.mylib:eventOk(source) then return end end)", { ossJson: SERVER_EV, safety: { rateLimitFns: ['eventOk'] } }), 'net-event-rate-limit'), 0);
});

test('net-event-rate-limit: named handlers and AddEventHandler pairs resolve', async () => {
  const named = "local function onGive(n)\n  rateLimit(source)\nend\nRegisterNetEvent('nakara_test:give', onGive)";
  assert.equal(await count(lua(named, { ossJson: SERVER_EV }), 'net-event-rate-limit'), 0);
  const pair = "RegisterNetEvent('nakara_test:give')\nAddEventHandler('nakara_test:give', function() GiveItem(source) end)\nAddEventHandler('playerDropped', function() end)";
  assert.equal(await count(lua(pair, { ossJson: SERVER_EV }), 'net-event-rate-limit'), 1);
  assert.equal(await count(js("onNet('nakara_test:js', (x) => { give(source, x); });", { ossJson: SERVER_EV }), 'net-event-rate-limit'), 1);
});

test('net-event-rate-limit: client handlers are not checked', async () => {
  const f = await scan({ 'client/main.lua': "RegisterNetEvent('nakara_test:notify', function(m) print(m) end)" }, { ossJson: oss({ netEvents: { server: [], client: ['nakara_test:notify'] } }) });
  assert.equal(of(f, 'net-event-rate-limit').length, 0);
});

// ---- nui-html-injection ------------------------------------------------------------------------
test('nui-html-injection', async () => {
  assert.equal(await count(nui('el.innerHTML = data.name;'), 'nui-html-injection'), 1);
  assert.equal(await count(nui('el.innerHTML = `<b>${name}</b>`;'), 'nui-html-injection'), 1);
  assert.equal(await count(nui("el.insertAdjacentHTML('beforeend', html);"), 'nui-html-injection'), 1);
  assert.equal(await count(nui('document.write(x);'), 'nui-html-injection'), 1);
  assert.equal(await count(nui("$('#x').html(msg);"), 'nui-html-injection'), 1);
  assert.equal(await count(nui("el.innerHTML = '';\nel.innerHTML = '<b>static</b>';\nel.textContent = data.name;"), 'nui-html-injection'), 0);
  const html = await scan({ 'html/index.html': '<html>\n<body>\n<script>\nwindow.addEventListener("message", (e) => { box.innerHTML = e.data.text; });\n</script>\n</body></html>' });
  const hit = of(html, 'nui-html-injection');
  assert.equal(hit.length, 1);
  assert.equal(hit[0].line, 4);
});

// ---- over-declared -----------------------------------------------------------------------------
test('over-declared: unused capabilities warn', async () => {
  const caps = oss({ http: ['https://api.example.com/'], nui: true, db: { tables: ['t'], ddl: true }, commands: ['x'] });
  const f = of(await lua('local a = 1', { ossJson: caps }), 'over-declared');
  assert.equal(f.length, 5);
  assert.ok(f.every((x) => x.severity === 'warn'));
});

test('over-declared: used capabilities do not warn', async () => {
  const caps = oss({ http: ['https://api.example.com/'], convars: { read: ['nakara_test_*'], write: [] } });
  const f = await lua("PerformHttpRequest('https://api.example.com/x', cb)\nlocal d = GetConvar('nakara_test_debug', '')", { ossJson: caps });
  assert.equal(of(f, 'over-declared').length, 0);
});

// ---- parse-error / unscanned -------------------------------------------------------------------
test('parse-error and unscanned', async () => {
  assert.equal(await count(lua('local s = "unterminated\nlocal x = 1'), 'parse-error'), 1);
  assert.equal(await count(nui('function ( {'), 'parse-error'), 1);
  assert.equal(await count(scan({ 'web/src/App.tsx': 'export const A = () => <div/>;' }), 'unscanned'), 1);
});
