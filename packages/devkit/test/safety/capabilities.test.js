import assert from 'node:assert/strict';
import test from 'node:test';
import { capabilityDiff, httpEntryMatches } from '../../src/safety/capabilities.js';
import { convarMarker } from '../../src/safety/luascan.js';

const base = { name: 'p', resource: 'nakara_p', capabilities: { http: ['a.example/'], commands: [], convars: { read: ['x_*'], write: [] }, netEvents: { server: ['p:a'], client: [] }, nui: false, db: { tables: ['t1'], ddl: false }, files: { write: [] } } };

test('capabilityDiff: widening and narrowing', () => {
  const next = structuredClone(base);
  next.capabilities.http.push('b.example/');
  next.capabilities.netEvents.server = [];
  next.capabilities.nui = true;
  next.capabilities.db.tables.push('t2');
  const d = capabilityDiff(base, next);
  assert.deepEqual(d.added, ['http: b.example/', 'db.tables: t2', 'nui: true (was false)']);
  assert.deepEqual(d.removed, ['netEvents.server: p:a']);
});

test('capabilityDiff: new package, JSON text input, no change', () => {
  const d = capabilityDiff(null, JSON.stringify(base));
  assert.ok(d.added.includes('http: a.example/'));
  assert.ok(d.added.includes('convars.read: x_*'));
  assert.deepEqual(d.removed, []);
  assert.deepEqual(capabilityDiff(base, structuredClone(base)), { added: [], removed: [] });
  const off = structuredClone(base);
  off.capabilities.db.ddl = true;
  assert.deepEqual(capabilityDiff(off, base).removed, ['db.ddl: false (was true)']);
});

test('httpEntryMatches: prefix, scheme, placeholders', () => {
  assert.ok(httpEntryMatches('https://api.example.com/', ['https://api.example.com/v1']));
  assert.ok(httpEntryMatches('api.example.com/', ['http://api.example.com/v1']));
  assert.ok(!httpEntryMatches('api.example.com/', ['https://api.example.com.evil.invalid/']));
  assert.ok(!httpEntryMatches('api.example.com', ['https://api.example.com.evil.invalid/']));
  assert.ok(httpEntryMatches('api.example.com', ['https://api.example.com/x']));
  assert.ok(httpEntryMatches('api.example.com', ['https://api.example.com']));
  assert.ok(!httpEntryMatches('api.example.com/', ['https://evil.invalid/api.example.com/']));
  assert.ok(httpEntryMatches('127.0.0.1:${netPort}/perf/', ['http://127.0.0.1:', null, '/perf/x']));
  assert.ok(httpEntryMatches('127.0.0.1:${netPort}/perf/', ['http://127.0.0.1:30120/perf/']));
  assert.ok(httpEntryMatches('${api_host}/v1', [`https://${convarMarker('api_host')}/v1/x`]));
  assert.ok(!httpEntryMatches('${api_host}/v1', ['https://', null, '/v1/x']));
  assert.ok(!httpEntryMatches('${api_host}/v1', [`https://${convarMarker('other')}/v1/x`]));
  assert.ok(!httpEntryMatches('${api_host}/v1', ['https://evil.example.invalid/v1']));
});
