import assert from 'node:assert/strict';
import test from 'node:test';
import { MANIFEST, clientLua, js, lua, nui, of, oss, scan } from './helpers.js';

const count = async (p, id) => of(await p, id).length;

// ---- missing-manifest --------------------------------------------------------------------------
test('missing-manifest: no oss.json → error, and every use is undeclared', async () => {
  const f = await lua("RegisterNetEvent('nakara_test:x', function() end)", { ossJson: null });
  assert.equal(of(f, 'missing-manifest').length, 1);
  assert.equal(of(f, 'undeclared-net-event').length, 1);
});

test('missing-manifest: requireManifest false skips must-declare, keeps hard-deny', async () => {
  const f = await lua("RegisterNetEvent('nakara_test:x', function() end)\nload(x)", { ossJson: null, safety: { requireManifest: false } });
  assert.equal(of(f, 'missing-manifest').length, 0);
  assert.equal(of(f, 'undeclared-net-event').length, 0);
  assert.equal(of(f, 'dynamic-load').length, 1);
});

test('missing-manifest: invalid oss.json is reported', async () => {
  assert.equal(await count(lua('local a = 1', { ossJson: '{ not json' }), 'missing-manifest'), 1);
  assert.equal(await count(lua('local a = 1', { ossJson: { name: 'x', resource: 'nakara_test', capabilities: { http: 'x' } } }), 'missing-manifest'), 1);
  assert.equal(await count(lua('local a = 1'), 'missing-manifest'), 0);
});

// ---- undeclared-http ---------------------------------------------------------------------------
test('undeclared-http: literal URLs against declared prefixes', async () => {
  const caps = oss({ http: ['https://api.example.com/'] });
  assert.equal(await count(lua("PerformHttpRequest('https://api.example.com/v1/x', cb)", { ossJson: caps }), 'undeclared-http'), 0);
  assert.equal(await count(lua("PerformHttpRequest('https://evil.example.invalid/x', cb)", { ossJson: caps }), 'undeclared-http'), 1);
  assert.equal(await count(lua("local BASE = 'https://api.example.com/'\nPerformHttpRequest(BASE .. 'v1/' .. id, cb)", { ossJson: caps }), 'undeclared-http'), 0);
  assert.equal(await count(js("fetch('https://api.example.com/v2');", { ossJson: caps }), 'undeclared-http'), 0);
  assert.equal(await count(js("const https = require('https'); https.request('https://evil.example.invalid/');", { ossJson: caps }), 'undeclared-http'), 1);
});

test('undeclared-http: dynamic URLs, aliases and value escapes', async () => {
  const caps = oss({ http: ['https://api.example.com/'] });
  const dyn = of(await lua('local function post(url) PerformHttpRequest(url, cb) end', { ossJson: caps }), 'undeclared-http');
  assert.equal(dyn.length, 1);
  assert.match(dyn[0].message, /dynamic URL/);
  assert.equal(await count(lua("local P = PerformHttpRequest\nP('https://evil.example.invalid/', cb)", { ossJson: caps }), 'undeclared-http'), 1);
  assert.equal(await count(lua('local t = { send = PerformHttpRequest }', { ossJson: caps }), 'undeclared-http'), 1);
});

test('undeclared-http: ${convar} placeholders', async () => {
  const caps = oss({ http: ['127.0.0.1:${netPort}/perf/', '${api_host}/v1'], convars: { read: ['netPort', 'api_host'], write: [] } });
  const ok = "PerformHttpRequest('http://127.0.0.1:' .. GetConvar('netPort', '30120') .. '/perf/x', cb)\nPerformHttpRequest('https://' .. GetConvar('api_host', '') .. '/v1/y', cb)";
  assert.equal(await count(lua(ok, { ossJson: caps }), 'undeclared-http'), 0);
  // a placeholder never matches a hard-coded host
  assert.equal(await count(lua("PerformHttpRequest('https://evil.example.invalid/v1', cb)", { ossJson: caps }), 'undeclared-http'), 1);
});

test('undeclared-http: NUI callbacks and local files are not outbound HTTP', async () => {
  const code = "fetch(`https://${GetParentResourceName()}/close`, {});\nconst RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'dev';\nfetch('https://' + RES + '/cb');\nfetch('./data.json');\nfetch('https://nakara_test/cb');";
  assert.equal(await count(nui(code), 'undeclared-http'), 0);
  assert.equal(await count(nui("fetch('https://evil.example.invalid/beacon');"), 'undeclared-http'), 1);
  // a fallback that is a real host does not count as the resource name
  assert.equal(await count(nui("const R = inGame ? GetParentResourceName() : 'evil.example.invalid'; fetch('https://' + R + '/x');"), 'undeclared-http'), 1);
});

test('undeclared-http: remote ui_page', async () => {
  const f = await scan({}, { manifest: MANIFEST + "ui_page 'https://evil.example.invalid/ui'\n", ossJson: oss({ nui: true }) });
  assert.equal(of(f, 'undeclared-http').length, 1);
});

// ---- undeclared-command ------------------------------------------------------------------------
test('undeclared-command', async () => {
  assert.equal(await count(lua("ExecuteCommand('mycmd arg')"), 'undeclared-command'), 1);
  assert.equal(await count(lua("ExecuteCommand('mycmd arg')", { ossJson: oss({ commands: ['mycmd'] }) }), 'undeclared-command'), 0);
  assert.equal(await count(clientLua('ExecuteCommand(name)'), 'undeclared-command'), 1);
});

// ---- undeclared-registered-command -------------------------------------------------------------
test('undeclared-registered-command', async () => {
  assert.equal(await count(lua("RegisterCommand('heal', function() end, true)"), 'undeclared-registered-command'), 1);
  assert.equal(await count(lua("RegisterCommand('heal', function() end, true)", { ossJson: oss({ registeredCommands: ['heal'] }) }), 'undeclared-registered-command'), 0);
  assert.equal(await count(lua("lib.addCommand({ 'a', 'b' }, {}, function() end)", { ossJson: oss({ registeredCommands: ['a'] }) }), 'undeclared-registered-command'), 1);
  assert.equal(await count(lua('RegisterCommand(name, function() end)'), 'undeclared-registered-command'), 1);
  // Config constant from another file resolves
  const files = { 'shared/config.lua': "Config = {}\nConfig.openCommand = 'panel'", 'client/main.lua': 'RegisterCommand(Config.openCommand, function() end)' };
  assert.equal(await count(scan(files, { ossJson: oss({ registeredCommands: ['panel'] }) }), 'undeclared-registered-command'), 0);
});

// ---- undeclared-convar -------------------------------------------------------------------------
test('undeclared-convar', async () => {
  assert.equal(await count(lua("local d = GetConvar('nakara_test_debug', 'false')"), 'undeclared-convar'), 1);
  assert.equal(await count(lua("local d = GetConvarInt('nakara_test_port', 0)", { ossJson: oss({ convars: { read: ['nakara_test_*'], write: [] } }) }), 'undeclared-convar'), 0);
  assert.equal(await count(lua("SetConvar('nakara_test_mode', 'x')", { ossJson: oss({ convars: { read: ['nakara_test_*'], write: [] } }) }), 'undeclared-convar'), 1);
  assert.equal(await count(lua("SetConvarReplicated('nakara_test_mode', 'x')", { ossJson: oss({ convars: { read: [], write: ['nakara_test_mode'] } }) }), 'undeclared-convar'), 0);
  assert.equal(await count(lua('local v = GetConvar(name, "")'), 'undeclared-convar'), 1);
});

// ---- undeclared-net-event ----------------------------------------------------------------------
test('undeclared-net-event: sides follow the manifest', async () => {
  const ev = "RegisterNetEvent('nakara_test:ping', function() NakaraCore.rateLimit(source) end)";
  assert.equal(await count(lua(ev), 'undeclared-net-event'), 1);
  assert.equal(await count(lua(ev, { ossJson: oss({ netEvents: { server: ['nakara_test:ping'], client: [] } }) }), 'undeclared-net-event'), 0);
  // the same event in a client file needs the client list
  assert.equal(await count(clientLua(ev, { ossJson: oss({ netEvents: { server: ['nakara_test:ping'], client: [] } }) }), 'undeclared-net-event'), 1);
  // shared counts as both
  const shared = await scan({ 'shared/ev.lua': ev }, { ossJson: oss({ netEvents: { server: ['nakara_test:*'], client: [] } }) });
  assert.equal(of(shared, 'undeclared-net-event').length, 1);
  assert.match(of(shared, 'undeclared-net-event')[0].message, /netEvents\.client/);
  assert.equal(await count(js("onNet('nakara_test:js', () => { rateLimit(source); });"), 'undeclared-net-event'), 1);
  assert.equal(await count(lua("RegisterNetEvent('nakara_test:' .. name)"), 'undeclared-net-event'), 1);
});

// ---- undeclared-nui ----------------------------------------------------------------------------
test('undeclared-nui', async () => {
  assert.equal(await count(clientLua('SetNuiFocus(true, true)'), 'undeclared-nui'), 1);
  assert.equal(await count(clientLua("RegisterNUICallback('close', function(_, cb) cb(1) end)", { ossJson: oss({ nui: true }) }), 'undeclared-nui'), 0);
  assert.equal(await count(scan({ 'html/index.html': '<p>x</p>' }, { manifest: MANIFEST + "ui_page 'html/index.html'\n" }), 'undeclared-nui'), 1);
});

// ---- undeclared-file-write ---------------------------------------------------------------------
test('undeclared-file-write', async () => {
  const own = "SaveResourceFile(GetCurrentResourceName(), 'data/state.json', s, -1)";
  assert.equal(await count(lua(own), 'undeclared-file-write'), 1);
  assert.equal(await count(lua(own, { ossJson: oss({ files: { write: ['data/*'] } }) }), 'undeclared-file-write'), 0);
  const other = of(await lua("SaveResourceFile('other_resource', 'fxmanifest.lua', s, -1)", { ossJson: oss({ files: { write: ['fxmanifest.lua'] } }) }), 'undeclared-file-write');
  assert.equal(other.length, 1);
  assert.match(other[0].message, /another|only GetCurrentResourceName/);
});

// ---- undeclared-db -----------------------------------------------------------------------------
test('undeclared-db: tables and DDL', async () => {
  const q = "MySQL.query.await('SELECT id FROM nakara_test_rows r JOIN users u ON u.id = r.uid WHERE r.x = ?', { x })";
  const f = await lua(q, { ossJson: oss({ db: { tables: ['nakara_test_*'], ddl: false } }) });
  assert.deepEqual(of(f, 'undeclared-db').map((x) => /'([^']+)'/.exec(x.message)[1]), ['users']);
  assert.equal(await count(lua("MySQL.insert('INSERT INTO t (a) VALUES (?) ON DUPLICATE KEY UPDATE a = VALUES(a)', {1})", { ossJson: oss({ db: { tables: ['t'], ddl: false } }) }), 'undeclared-db'), 0);
  assert.equal(await count(lua("MySQL.query([[CREATE TABLE IF NOT EXISTS t (id INT)]])", { ossJson: oss({ db: { tables: ['t'], ddl: false } }) }), 'undeclared-db'), 1);
  assert.equal(await count(lua("MySQL.query([[CREATE TABLE IF NOT EXISTS t (id INT)]])", { ossJson: oss({ db: { tables: ['t'], ddl: true } }) }), 'undeclared-db'), 0);
  assert.equal(await count(scan({ 'sql/install.sql': '-- schema\nCREATE TABLE secret_stuff (id INT);\n' }, { ossJson: oss({ db: { tables: [], ddl: true } }) }), 'undeclared-db'), 1);
  // English text and client code are not SQL
  assert.equal(await count(lua("local s = 'Please select from the list'"), 'undeclared-db'), 0);
  assert.equal(await count(clientLua("local q = 'SELECT * FROM users'"), 'undeclared-db'), 0);
});
