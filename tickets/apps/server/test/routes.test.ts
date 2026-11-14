import { readFileSync } from 'node:fs';
import { describe, expect, test } from 'vitest';
import YAML from 'yaml';
import { buildApp } from '../src/app.js';
import pkg from '../package.json' with { type: 'json' };

const spec = YAML.parse(readFileSync(new URL('../../../openapi.yaml', import.meta.url), 'utf8'));

interface Operation {
  method: string;
  path: string;
  operationId: string;
}

const operations: Operation[] = [];
for (const [path, pathItem] of Object.entries(spec.paths as Record<string, any>)) {
  for (const method of ['get', 'post', 'put', 'delete', 'patch']) {
    const op = pathItem[method];
    if (op?.operationId) {
      operations.push({ method: method.toUpperCase(), path, operationId: op.operationId });
    }
  }
}

function resolvePath(path: string): string {
  return path
    .replace('{guildId}', '123456789012345678')
    .replace('{userId}', '123456789012345678')
    .replace('{transition}', 'claim')
    .replace(/\{[a-zA-Z]+\}/g, '00000000-0000-4000-8000-000000000000');
}

describe('OpenAPI route stubs', () => {
  test('r1: every operation is registered and does not 404', async () => {
    const app = buildApp();
    for (const op of operations) {
      const res = await app.inject({ method: op.method as any, url: resolvePath(op.path) });
      expect(res.statusCode, `${op.method} ${op.path}`).not.toBe(404);
    }
  });

  test('r2: every operation except getHealthz answers 501 with operationId', async () => {
    const app = buildApp();
    for (const op of operations) {
      if (op.operationId === 'getHealthz') continue;
      const res = await app.inject({ method: op.method as any, url: resolvePath(op.path) });
      expect(res.statusCode, `${op.method} ${op.path}`).toBe(501);
      expect(res.json()).toEqual({ code: 'not_implemented', message: op.operationId });
    }
  });

  test('r3: GET /healthz answers 200 with ok: true and version', async () => {
    const app = buildApp();
    const res = await app.inject({ method: 'GET', url: '/healthz' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true, db: 'down', gateway: 'standby', version: pkg.version });
  });

  test('r4: count of registered routes equals count of operations in spec', async () => {
    const registered: string[] = [];
    const app = buildApp();
    app.addHook('onRoute', (r) => {
      if (r.method !== 'HEAD') registered.push(`${r.method} ${r.url}`);
    });
    await app.ready();
    expect(registered.length).toBe(operations.length);
  });

  test('c1: control - injecting GET /api/v1/nope answers 404', async () => {
    const app = buildApp();
    const res = await app.inject({ method: 'GET', url: '/api/v1/nope' });
    expect(res.statusCode).toBe(404);
  });
});
