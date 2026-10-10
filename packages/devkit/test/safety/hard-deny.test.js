import assert from 'node:assert/strict';
import test from 'node:test';
import { clientLua, js, lua, nui, of, scan } from './helpers.js';

const fires = async (p, id) => assert.ok(of(await p, id).length > 0, `expected ${id}`);
const silent = async (p, id) => {
  const hits = of(await p, id);
  assert.equal(hits.length, 0, `unexpected ${id}: ${hits.map((h) => h.message).join(' | ')}`);
};

// ---- dynamic-load ------------------------------------------------------------------------------
test('dynamic-load: positives incl. evasions', async () => {
  await fires(lua('load(body)()'), 'dynamic-load');
  await fires(lua('local l = load; l(x)'), 'dynamic-load');
  await fires(lua('local ok = pcall(load, x)'), 'dynamic-load');
  await fires(lua("_G['lo' .. 'ad'](x)"), 'dynamic-load');
  await fires(lua("_ENV.loadstring(x)"), 'dynamic-load');
  await fires(lua("dofile('x.lua')"), 'dynamic-load');
  await fires(lua("local t = { fn = loadfile }"), 'dynamic-load');
  await fires(js('const m = require(name);'), 'dynamic-load');
  await fires(js('const m = await import(`./${x}.js`);'), 'dynamic-load');
  await fires(scan({ 'html/index.html': '<script src="https://cdn.example.invalid/x.js"></script>' }), 'dynamic-load');
});

test('dynamic-load: comments, strings, fields, shadowing do not trigger', async () => {
  await silent(lua('-- load(x)\n--[[ load(y) ]]\nlocal s = "load(z)"\nlocal t = [[loadstring(q)]]'), 'dynamic-load');
  await silent(lua('obj.load(x)\nself:load()\nConfig.load = 1\nlocal t = { load = 1 }'), 'dynamic-load');
  await silent(lua('local function f(load) return load(1) end'), 'dynamic-load');
  await silent(js("const fs = require('./lib.js'); const x = { load: 1 }; x.load();"), 'dynamic-load');
});

// ---- host-exec ---------------------------------------------------------------------------------
test('host-exec', async () => {
  await fires(lua("os.execute('rm -rf /')"), 'host-exec');
  await fires(lua("local p = io.popen('id')"), 'host-exec');
  await fires(lua('local o = os\no.remove(path)'), 'host-exec');
  await fires(lua("local f = io.open(path, 'w')"), 'host-exec');
  await fires(lua("local f = io.open(path, 'a+')"), 'host-exec');
  await fires(lua('local f = io.open(path, mode)'), 'host-exec');
  await fires(lua("os['exe' .. 'cute']('x')"), 'host-exec');
  await fires(js("const cp = require('child_process'); cp.exec('id');"), 'host-exec');
  await fires(js("const { exec } = require('node:child_process');"), 'host-exec');
  await fires(js("import vm from 'vm'; vm.runInThisContext(x);"), 'host-exec');
  await fires(js('process.binding("fs");'), 'host-exec');
  await silent(lua("local f = io.open(path)\nlocal g = io.open(path, 'rb')\nlocal t = os.time() + os.clock()"), 'host-exec');
  await silent(js("const t = child.process; const m = require('./worker_threads_helper.js');"), 'host-exec');
});

// ---- host-access -------------------------------------------------------------------------------
test('host-access', async () => {
  await fires(lua("local h = os.getenv('HOME')"), 'host-access');
  await fires(js("const fs = require('fs'); fs.writeFileSync('x', y);"), 'host-access');
  await fires(js('const k = process.env.DB_PASSWORD;'), 'host-access');
  await silent(js("const f = fsHelper.read('x'); const e = Config.env;"), 'host-access');
});

// ---- code-eval ---------------------------------------------------------------------------------
test('code-eval', async () => {
  await fires(nui('eval(x);'), 'code-eval');
  await fires(nui("const f = new Function('a', body);"), 'code-eval');
  await fires(nui("setTimeout('doThing()', 10);"), 'code-eval');
  await fires(nui("''.constructor.constructor('return this')();"), 'code-eval');
  await fires(nui("window['ev' + 'al'](x);"), 'code-eval');
  await silent(nui('if (x instanceof Function) {} setTimeout(() => go(), 10); if (typeof eval === "undefined") {}'), 'code-eval');
});

// ---- env-tamper --------------------------------------------------------------------------------
test('env-tamper: positives', async () => {
  await fires(lua('debug.sethook(f)'), 'env-tamper');
  await fires(lua('local d = debug\nd.getupvalue(f, 1)'), 'env-tamper');
  await fires(lua('setfenv(f, {})'), 'env-tamper');
  await fires(lua('local e = getfenv(1)'), 'env-tamper');
  await fires(lua('local b = string.dump(f)'), 'env-tamper');
  await fires(lua('local s = string\nlocal b = s.dump(f)'), 'env-tamper');
  await fires(lua("local x = rawget(_G, 'lo' .. 'ad')"), 'env-tamper');
  await fires(lua('local fn = _G[name]'), 'env-tamper');
  await fires(lua('local g = _G'), 'env-tamper');
  await fires(lua('local _ENV = {}'), 'env-tamper');
  await fires(lua('do local debug = 1 end\ndebug.sethook()'), 'env-tamper');
  await fires(nui('globalThis[name]();'), 'env-tamper');
});

test('env-tamper: literal global access, fields and locals are fine', async () => {
  await silent(lua("_G.Config = {}\nlocal c = _G['Config']\nif Config.debug then end\nlocal t = { debug = true }\nself.debug = 1"), 'env-tamper');
  await silent(lua('local debug = false\nif debug then print(1) end'), 'env-tamper');
  await silent(lua('xpcall(f, debug.traceback)\nprint(debug.traceback())'), 'env-tamper');
  await silent(nui('window.addEventListener("message", f); const d = window.devicePixelRatio;'), 'env-tamper');
});

// ---- invoke-native -----------------------------------------------------------------------------
test('invoke-native: server only', async () => {
  await fires(lua('Citizen.InvokeNative(0x561C060B, "x")'), 'invoke-native');
  await silent(clientLua('Citizen.InvokeNative(0x5FBCA48327B914DF, ped)'), 'invoke-native');
});

// ---- secret-convar -----------------------------------------------------------------------------
test('secret-convar: positives', async () => {
  await fires(lua("local p = GetConvar('rcon_password', '')"), 'secret-convar');
  await fires(lua("local k = GetConvar('sv_licenseKey', '')"), 'secret-convar');
  await fires(lua("local k = GetConvar('steam_' .. 'webApiKey', '')"), 'secret-convar');
  await fires(lua("local ok, c = pcall(GetConvar, 'mysql_connection_string', '')"), 'secret-convar');
  await fires(lua("local t = GetConvar('my_discord_bot_token', '')"), 'secret-convar');
  await fires(lua("local gc = GetConvar\nlocal w = gc('logs_webhook', '')"), 'secret-convar');
  await fires(js("const k = GetConvar('payments_apikey', '');"), 'secret-convar');
  // the name comes from config.lua in another file of the same resource
  await fires(scan({ 'shared/config.lua': "Config = { tokenConvar = 'bot_token' }", 'server/main.lua': 'local t = GetConvar(Config.tokenConvar, "")' }), 'secret-convar');
});

test('secret-convar: ordinary convars and comments are not secrets', async () => {
  await silent(lua("-- GetConvar('rcon_password')\nlocal d = GetConvar('nakara_test_debug', 'false')"), 'secret-convar');
});

// ---- ace-command -------------------------------------------------------------------------------
test('ace-command: positives incl. evasions', async () => {
  await fires(lua("ExecuteCommand('add_ace group.admin command allow')"), 'ace-command');
  await fires(lua("ExecuteCommand('add_' .. 'ace group.admin command allow')"), 'ace-command');
  await fires(lua("ExecuteCommand(('add_principal identifier.%s group.admin'):format(id))"), 'ace-command');
  await fires(lua("ExecuteCommand('ensure ' .. res)"), 'ace-command');
  await fires(lua("ExecuteCommand('say hi; quit')"), 'ace-command');
  await fires(lua('ExecuteCommand(cmd)'), 'ace-command');
  await fires(lua("local e = ExecuteCommand\ne('exec server.cfg')"), 'ace-command');
  await fires(lua("pcall(ExecuteCommand, 'set sv_hostname x')"), 'ace-command');
  await fires(lua('local t = { run = ExecuteCommand }'), 'ace-command');
  await fires(js("ExecuteCommand(`add_principal identifier.${id} group.admin`);"), 'ace-command');
  await fires(clientLua("ExecuteCommand('quit')"), 'ace-command');
});

test('ace-command: ordinary commands are not denied', async () => {
  await silent(lua("ExecuteCommand('say we restart at six')\n-- ExecuteCommand('add_ace x')"), 'ace-command');
  await silent(clientLua("ExecuteCommand('e ' .. emote)"), 'ace-command');
});

// ---- command-injection -------------------------------------------------------------------------
test('command-injection: server-side runtime args', async () => {
  await fires(lua("ExecuteCommand('say ' .. msg)"), 'command-injection');
  await silent(lua("ExecuteCommand('say hello')"), 'command-injection');
  await silent(clientLua("ExecuteCommand('e ' .. emote)"), 'command-injection');
});

// ---- obfuscation -------------------------------------------------------------------------------
test('obfuscation: positives', async () => {
  await fires(lua('local s = "\\x50\\x65\\x72\\x66\\x6f\\x72\\x6d\\x48"'), 'obfuscation');
  await fires(lua('local s = "\\80\\101\\114\\102\\111\\114\\109\\72"'), 'obfuscation');
  await fires(lua(`local b = '${'QUJD'.repeat(55)}'`), 'obfuscation');
  await fires(lua('local s = string.char(108, 111, 97, 100, 115, 116, 114, 105)'), 'obfuscation');
  await fires(lua('local s = string.char(table.unpack(t))'), 'obfuscation');
  await fires(lua(`local t = { ${Array.from({ length: 40 }, (_, i) => 60 + i).join(', ')} }\nlocal s = ''\nfor _, b in ipairs(t) do s = s .. string.char(b) end`), 'obfuscation');
  await fires(nui('const s = String.fromCharCode(...bytes);'), 'obfuscation');
  await fires(lua(`local x = 1 ${' '.repeat(1100)} local y = load`), 'obfuscation');
});

test('obfuscation: negatives', async () => {
  await silent(lua('local s = "\\x41\\x42\\x43\\x44\\x45\\x46\\x47 gap \\x48"'), 'obfuscation');
  await silent(lua(`local b = '${'QUJD'.repeat(30)}'`), 'obfuscation');
  await silent(lua('local s = string.char(65, 66)\n-- "\\x50\\x65\\x72\\x66\\x6f\\x72\\x6d\\x48\\x48"'), 'obfuscation');
  await silent(lua(`local colors = { ${Array.from({ length: 40 }, (_, i) => i).join(', ')} }`), 'obfuscation');
});

// ---- opaque-file -------------------------------------------------------------------------------
test('opaque-file', async () => {
  await fires(scan({ 'bin/helper.dll': Buffer.from([0x4d, 0x5a, 0, 0]) }), 'opaque-file');
  await fires(scan({ 'server/x.luac': Buffer.from([0x1b, 0x4c, 0x75, 0x61]) }), 'opaque-file');
  await fires(scan({ 'server/main.lua': Buffer.concat([Buffer.from([0x1b]), Buffer.from('LuaT\0\x19\x93')]) }), 'opaque-file');
  await fires(scan({ 'html/lib.min.js': 'var a=1;' }), 'opaque-file');
  await fires(scan({ 'html/bundle.js': `var a=${'1+'.repeat(800)}1;` }), 'opaque-file');
  await fires(scan({ 'stream/car.ytd': Buffer.from([1, 2, 3]) }), 'opaque-file');
  await silent(scan({ 'stream/car.ytd': Buffer.from([1, 2, 3]) }, { safety: { allowAssets: true } }), 'opaque-file');
  await silent(scan({ 'html/app.js': 'const a = 1;\nconst b = 2;\n', 'html/logo.png': Buffer.from([0x89, 0x50, 0x4e, 0x47, 0]) }), 'opaque-file');
});

test('command-injection: numeric format directives cannot inject', async () => {
  await silent(lua("ExecuteCommand(('profiler record %d'):format(frames))"), 'command-injection');
  await fires(lua("ExecuteCommand(('say %s'):format(msg))"), 'command-injection');
  await fires(lua("ExecuteCommand(('say %c'):format(ch))"), 'command-injection');
});
