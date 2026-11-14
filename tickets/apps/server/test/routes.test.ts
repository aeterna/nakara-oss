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

const STUBBED_OPERATIONS = new Set([
  // panels
  'getPanels',
  'postPanels',
  'putPanel',
  'deletePanel',
  'postPanelSend',
  // tickets read endpoints
  'getTickets',
  'getTicket',
  'getTicketMessages',
  'getTicketTranscript',
  'getAttachment',
  // tags
  'getTags',
  'postTags',
  'putTag',
  'deleteTag',
  // blocks
  'getBlocks',
  'postBlocks',
  'deleteBlock',
  // stats
  'getStats',
  // audit
  'getAudit',
  // data
  'deleteMeData',
  'getExport',
]);

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

  test('r2: every operation has a registered route; stubbed operations answer 501', async () => {
    const app = buildApp();
    for (const op of operations) {
      const res = await app.inject({ method: op.method as any, url: resolvePath(op.path) });
      expect(res.statusCode, `${op.method} ${op.path}`).not.toBe(404);
      if (STUBBED_OPERATIONS.has(op.operationId)) {
        expect(res.statusCode, `${op.method} ${op.path}`).toBe(501);
        expect(res.json()).toEqual({ code: 'not_implemented', message: op.operationId });
      }
    }
  });

  test('r3: GET /healthz answers 200 with ok: true and version', async () => {
    const app = buildApp();
    const res = await app.inject({ method: 'GET', url: '/healthz' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true, db: 'down', gateway: 'standby', version: pkg.version });
  });

  test("r4: registered METHOD path set equals the spec's set (path params converted)", async () => {
    const registered = new Set<string>();
    const app = buildApp();
    app.addHook('onRoute', (r) => {
      if (r.method !== 'HEAD') {
        const methods = Array.isArray(r.method) ? r.method : [r.method];
        for (const m of methods) {
          if (m !== 'HEAD') registered.add(`${m} ${r.url}`);
        }
      }
    });
    await app.ready();
    const specRoutes = new Set(
      operations.map((op) => `${op.method} ${op.path.replace(/\{([^}]+)\}/g, ':$1')}`)
    );
    expect(registered).toEqual(specRoutes);
  });

  test('c1: control - injecting GET /api/v1/nope answers 404', async () => {
    const app = buildApp();
    const res = await app.inject({ method: 'GET', url: '/api/v1/nope' });
    expect(res.statusCode).toBe(404);
  });
});
