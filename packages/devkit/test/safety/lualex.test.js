import assert from 'node:assert/strict';
import test from 'node:test';
import { lex } from '../../src/safety/lualex.js';
import { analyzeLua } from '../../src/safety/luascan.js';

const vals = (src) => lex(src).tokens.filter((t) => t.type !== 'eof').map((t) => `${t.type}:${t.value}`);

test('CfxLua extensions lex without errors', () => {
  const src = "local x <const> = `adder`\nlocal f <close> = nil\nx += 1\ny -= 2\nlocal v = a?.b\nif a != b then end\n";
  const { tokens, errors } = lex(src);
  assert.deepEqual(errors, []);
  assert.ok(tokens.some((t) => t.type === 'hash' && t.value === 'adder'));
  assert.ok(tokens.some((t) => t.type === 'op' && t.value === '+='));
  assert.ok(tokens.some((t) => t.type === 'op' && t.value === '?.'));
  assert.ok(tokens.some((t) => t.type === 'op' && t.value === '!='));
});

test('comments and strings never become code tokens', () => {
  assert.deepEqual(vals("-- load(x)\nlocal a = 1"), ['keyword:local', 'name:a', 'op:=', 'number:1']);
  assert.deepEqual(vals('--[==[ load(x) ]] still comment ]==] b'), ['name:b']);
  assert.deepEqual(vals('s = [[load(x)]]'), ['name:s', 'op:=', 'string:load(x)']);
  assert.deepEqual(vals('s = [=[a]]b]=]'), ['name:s', 'op:=', 'string:a]]b']);
  assert.deepEqual(vals("s = 'it\\'s -- not a comment'"), ['name:s', 'op:=', "string:it's -- not a comment"]);
});

test('escapes decode and count runs', () => {
  const t = lex('s = "\\x6c\\x6f\\97\\100\\u{41}z"').tokens[2];
  assert.equal(t.value, 'loadAz');
  assert.equal(t.escRun, 5);
});

test('line numbers survive long strings, comments and \\z', () => {
  const { tokens } = lex('a = [[\nx\ny]]\n--[[\n\n]]\nb = "q\\z\n   r"\nc = 1');
  const line = (name) => tokens.find((t) => t.value === name).line;
  assert.equal(line('a'), 1);
  assert.equal(line('b'), 7);
  assert.equal(line('c'), 9);
});

test('numbers: hex, floats, exponents', () => {
  assert.deepEqual(vals('x = 0xFF + 1.5e3 + .5 + 0x1p4').filter((v) => v.startsWith('number')), ['number:0xFF', 'number:1.5e3', 'number:.5', 'number:0x1p4']);
});

test('unterminated strings are reported, not thrown', () => {
  assert.equal(lex('x = "abc\ny = 1').errors[0].message, 'unterminated string');
  assert.equal(lex('x = [[abc').errors[0].message, 'unterminated long string');
});

test('scopes: locals shadow globals, do-blocks end', () => {
  const m = analyzeLua('do local debug = 1 end\ndebug.sethook()\nlocal function f(load) return load end\nlocal os = os\nos.execute("x")');
  const paths = m.refs.map((r) => r.path);
  assert.ok(paths.includes('debug.sethook'));
  assert.ok(!paths.includes('load'));
  assert.ok(paths.includes('os.execute'));
});

test('folding: concat, format, constants', () => {
  const m = analyzeLua("local BASE = 'https://api.example.com/'\nf(BASE .. 'v1/' .. id)\ng(('add_' .. 'ace %s x'):format(y))\nh(string.format('%s/%d', a, b))");
  const arg = (p) => m.refs.find((r) => r.path === p).call.args[0].parts;
  assert.deepEqual(arg('f'), ['https://api.example.com/v1/', null]);
  assert.deepEqual(arg('g'), ['add_ace ', null, ' x']);
  assert.deepEqual(arg('h'), [null, '/\u0004']); // %d is an unknown *number*, %s unknown text
});
