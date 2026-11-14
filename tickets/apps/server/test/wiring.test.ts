import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openTestDb } from '@nakara-tickets/db/test-support';
import { buildApp, installAll } from '../src/app.js';
import type { TicketsConfig } from '../src/config.js';

describe('wiring end to end (w4)', () => {
  let testEnv: Awaited<ReturnType<typeof openTestDb>>;
  let db: any;
  let tempWebDir: string;
  let config: TicketsConfig;

  beforeAll(async () => {
    testEnv = await openTestDb();
    db = testEnv.db;

    tempWebDir = mkdtempSync(join(tmpdir(), 'tickets-web-'));
    writeFileSync(join(tempWebDir, 'index.html'), '<html><body>Hello Nakara</body></html>', 'utf-8');

    config = {
      ROLE: 'all',
      PORT: 8080,
      DATABASE_URL: 'postgres://test',
      TICKETS_DATA_KEY: Buffer.alloc(32, 7),
      DISCORD_TOKEN: 'mock-token',
      DISCORD_APP_ID: '123456789012345678',
      DISCORD_CLIENT_SECRET: 'mock-secret',
      PUBLIC_ORIGIN: 'http://localhost:8080',
      ALLOWED_GUILD_IDS: ['123456789012345678'],
      STORAGE_DIR: '/tmp',
    };
  });

  afterAll(async () => {
    await testEnv.close();
    try {
      rmSync(tempWebDir, { recursive: true, force: true });
    } catch {
      // ignore
    }
  });

  it('(w4) buildApp + installAll wires session, bridge auth, and static files', async () => {
    const app = buildApp({ config, db });
    await installAll(app, { config, db, webDir: tempWebDir });
    await app.ready();

    // 1. GET /api/v1/me without cookie = 401 (session installed)
    const meRes = await app.inject({
      method: 'GET',
      url: '/api/v1/me',
    });
    expect(meRes.statusCode).toBe(401);
    expect(meRes.json().code).toBe('unauthorized');

    // 2. POST /bridge/v1/heartbeat unsigned = 401 (bridge auth installed)
    const heartbeatRes = await app.inject({
      method: 'POST',
      url: '/bridge/v1/heartbeat',
      payload: { players: [] },
    });
    expect(heartbeatRes.statusCode).toBe(401);
    expect(heartbeatRes.json().code).toBe('unauthorized');

    // 3. GET / serves index.html from temp webDir
    const rootRes = await app.inject({
      method: 'GET',
      url: '/',
    });
    expect(rootRes.statusCode).toBe(200);
    expect(rootRes.headers['content-type']).toContain('text/html');
    expect(rootRes.payload).toContain('Hello Nakara');

    await app.close();
  });
});
