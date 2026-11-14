import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import Fastify from 'fastify';
import { installStatic } from '../src/static.js';

const EXPECTED_CSP = "default-src 'self'; img-src 'self' https://cdn.discordapp.com data:; frame-ancestors 'none'";

describe('static serving acceptance tests', () => {
  let tempDir: string;
  const indexHtmlContent = '<!DOCTYPE html><html><head><title>Nakara Tickets</title></head><body><div id="root">App</div></body></html>';
  const appJsContent = 'console.log("nakara-tickets-bundle-ok");';

  beforeAll(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tickets-static-test-'));
    fs.writeFileSync(path.join(tempDir, 'index.html'), indexHtmlContent, 'utf8');
    fs.writeFileSync(path.join(tempDir, 'app.js'), appJsContent, 'utf8');
  });

  afterAll(() => {
    if (tempDir && fs.existsSync(tempDir)) {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  });

  it('(s1) serves static files, falls back to index.html for unknown SPA routes, preserves API 404, sets security headers', async () => {
    const app = Fastify();
    installStatic(app, tempDir);
    await app.ready();

    // 1. /app.js served directly
    const appRes = await app.inject({ method: 'GET', url: '/app.js' });
    expect(appRes.statusCode).toBe(200);
    expect(appRes.body).toBe(appJsContent);
    expect(appRes.headers['x-content-type-options']).toBe('nosniff');
    expect(appRes.headers['content-security-policy']).toBe(EXPECTED_CSP);

    // 2. /categories is an unknown GET path outside excluded prefixes -> returns index.html
    const spaRes = await app.inject({ method: 'GET', url: '/categories' });
    expect(spaRes.statusCode).toBe(200);
    expect(spaRes.body).toContain('<title>Nakara Tickets</title>');
    expect(spaRes.body).toBe(indexHtmlContent);
    expect(spaRes.headers['x-content-type-options']).toBe('nosniff');
    expect(spaRes.headers['content-security-policy']).toBe(EXPECTED_CSP);

    // Deep nested SPA path fallback
    const nestedRes = await app.inject({ method: 'GET', url: '/settings/panels/edit' });
    expect(nestedRes.statusCode).toBe(200);
    expect(nestedRes.body).toBe(indexHtmlContent);

    // 3. /api/v1/nope is inside /api -> must NOT return index.html
    const apiRes = await app.inject({ method: 'GET', url: '/api/v1/nope' });
    expect(apiRes.statusCode).toBe(404);
    expect(apiRes.body).not.toBe(indexHtmlContent);
    expect(apiRes.body).not.toContain('<title>Nakara Tickets</title>');

    // 4. Other excluded prefixes are also protected from SPA fallback
    const authRes = await app.inject({ method: 'GET', url: '/auth/unknown' });
    expect(authRes.statusCode).toBe(404);
    expect(authRes.body).not.toBe(indexHtmlContent);

    const bridgeRes = await app.inject({ method: 'GET', url: '/bridge/unknown' });
    expect(bridgeRes.statusCode).toBe(404);
    expect(bridgeRes.body).not.toBe(indexHtmlContent);

    const healthRes = await app.inject({ method: 'GET', url: '/healthz' });
    expect(healthRes.statusCode).toBe(404);
    expect(healthRes.body).not.toBe(indexHtmlContent);

    const metricsRes = await app.inject({ method: 'GET', url: '/metrics' });
    expect(metricsRes.statusCode).toBe(404);
    expect(metricsRes.body).not.toBe(indexHtmlContent);

    // 5. Non-GET requests (e.g. POST) to SPA route do not return index.html
    const postRes = await app.inject({ method: 'POST', url: '/categories' });
    expect(postRes.statusCode).toBe(404);
    expect(postRes.body).not.toBe(indexHtmlContent);

    await app.close();
  });

  it('(s2) missing dir logs a warning, serves nothing, and app still builds successfully', async () => {
    const missingDir = path.join(os.tmpdir(), 'nonexistent-tickets-static-dir-' + Date.now());
    const app = Fastify();

    // Calling installStatic with missing directory must not throw
    expect(() => installStatic(app, missingDir)).not.toThrow();

    // App must still build and start without error
    await expect(app.ready()).resolves.toBeDefined();

    // Missing dir means nothing is served
    const res = await app.inject({ method: 'GET', url: '/categories' });
    expect(res.statusCode).toBe(404);
    expect(res.body).not.toContain('<title>Nakara Tickets</title>');

    await app.close();
  });
});
