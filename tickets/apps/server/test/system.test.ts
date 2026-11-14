import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import Fastify from 'fastify';
import { writeFileSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openTestDb } from '@nakara-tickets/db/test-support';
import { tickets, gameServers, categories, guilds } from '@nakara-tickets/db';
import systemRoute from '../src/routes/system.js';
import type { GatewayStatus } from '../src/types.js';

describe('system routes (w3)', () => {
  let testEnv: Awaited<ReturnType<typeof openTestDb>>;
  let db: any;

  beforeAll(async () => {
    testEnv = await openTestDb();
    db = testEnv.db;
  });

  afterAll(async () => {
    await testEnv.close();
  });

  it('(w3-1) healthz 200/up with a working pglite db returns only { ok, db, gateway, version }', async () => {
    const app = Fastify();
    let currentGatewayStatus: GatewayStatus = 'connected';
    app.decorate('db', db);
    app.decorate('gateway', { status: () => currentGatewayStatus });
    await app.register(systemRoute);

    const res = await app.inject({
      method: 'GET',
      url: '/healthz',
    });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body).toEqual({
      ok: true,
      db: 'up',
      gateway: 'connected',
      version: expect.any(String),
    });
    // Strict verify: only these 4 keys, no counts
    expect(Object.keys(body).sort()).toEqual(['db', 'gateway', 'ok', 'version'].sort());
  });

  it('(w3-2) healthz 503/down with a db whose query throws', async () => {
    const brokenDb = {
      execute: async () => {
        throw new Error('connection refused');
      },
    };

    const app = Fastify();
    app.decorate('db', brokenDb as any);
    app.decorate('gateway', { status: () => 'standby' });
    await app.register(systemRoute);

    const res = await app.inject({
      method: 'GET',
      url: '/healthz',
    });

    expect(res.statusCode).toBe(503);
    const body = res.json();
    expect(body.ok).toBe(false);
    expect(body.db).toBe('down');
    expect(body.gateway).toBe('standby');
    expect(body.version).toBeDefined();
    expect(Object.keys(body).sort()).toEqual(['db', 'gateway', 'ok', 'version'].sort());
  });

  it('(w3-3) metrics requires Authorization: Bearer <METRICS_TOKEN> when set, else 404', async () => {
    await testEnv.reset();

    const guildId = '123456789012345678';
    await db.insert(guilds).values({ guild_id: guildId, name: 'Metric Guild' });

    // Insert categories and tickets
    const [cat] = await db.insert(categories).values({
      guild_id: guildId,
      name: 'General',
      parent_channel_id: '123456789012345678',
    }).returning();

    await db.insert(tickets).values([
      { guild_id: guildId, category_id: cat.id, number: 1, opener_id: '111111111111111111', channel_id: '100000000000000001', status: 'open' },
      { guild_id: guildId, category_id: cat.id, number: 2, opener_id: '222222222222222222', channel_id: '100000000000000002', status: 'claimed' },
      { guild_id: guildId, category_id: cat.id, number: 3, opener_id: '333333333333333333', channel_id: '100000000000000003', status: 'closed' },
    ]);

    // Insert game server seen recently
    await db.insert(gameServers).values([
      {
        guild_id: guildId,
        name: 'Server 1',
        secret_enc: Buffer.alloc(16),
        last_seen_at: new Date(),
      },
      {
        guild_id: guildId,
        name: 'Server 2 (offline)',
        secret_enc: Buffer.alloc(16),
        last_seen_at: new Date(Date.now() - 200 * 1000), // > 90 s ago
      },
    ]);

    const app = Fastify();
    app.decorate('db', db);
    app.decorate('gateway', { status: () => 'connected' });
    await app.register(systemRoute);

    const oldToken = process.env.METRICS_TOKEN;
    const oldTokenFile = process.env.METRICS_TOKEN_FILE;
    delete process.env.METRICS_TOKEN;
    delete process.env.METRICS_TOKEN_FILE;

    try {
      // 1. Without env METRICS_TOKEN -> 404
      const res404 = await app.inject({
        method: 'GET',
        url: '/metrics',
      });
      expect(res404.statusCode).toBe(404);

      // 2. With env METRICS_TOKEN set
      process.env.METRICS_TOKEN = 'secret-metrics-token-123';

      // 2a. Request without token -> 401
      const resNoAuth = await app.inject({
        method: 'GET',
        url: '/metrics',
      });
      expect(resNoAuth.statusCode).toBe(401);

      // 2b. Request with wrong token -> 401
      const resWrongAuth = await app.inject({
        method: 'GET',
        url: '/metrics',
        headers: {
          authorization: 'Bearer wrong-token',
        },
      });
      expect(resWrongAuth.statusCode).toBe(401);

      // 2c. Request with correct token -> 200 with all 4 series
      const resOk = await app.inject({
        method: 'GET',
        url: '/metrics',
        headers: {
          authorization: 'Bearer secret-metrics-token-123',
        },
      });
      expect(resOk.statusCode).toBe(200);
      expect(resOk.headers['content-type']).toContain('text/plain; version=0.0.4');

      const text = resOk.payload;
      expect(text).toContain('nakara_tickets_up 1');
      expect(text).toMatch(/nakara_tickets_tickets\{status="open"\} 1/);
      expect(text).toMatch(/nakara_tickets_tickets\{status="claimed"\} 1/);
      expect(text).toMatch(/nakara_tickets_tickets\{status="closed"\} 1/);
      expect(text).toMatch(/nakara_tickets_game_servers_online 1/);
      expect(text).toMatch(/nakara_tickets_gateway_connected 1/);

      // Verify NO snowflake or guild name appears in labels
      expect(text).not.toContain(guildId);
      expect(text).not.toContain('Metric Guild');
      expect(text).not.toContain('111111111111111111');

      // 3. Test METRICS_TOKEN_FILE support
      delete process.env.METRICS_TOKEN;
      const tmpFilePath = join(tmpdir(), `metrics-token-${Date.now()}.txt`);
      writeFileSync(tmpFilePath, 'file-metrics-token-456\n', 'utf8');
      process.env.METRICS_TOKEN_FILE = tmpFilePath;

      try {
        const resFileOk = await app.inject({
          method: 'GET',
          url: '/metrics',
          headers: {
            authorization: 'Bearer file-metrics-token-456',
          },
        });
        expect(resFileOk.statusCode).toBe(200);
      } finally {
        try {
          unlinkSync(tmpFilePath);
        } catch {}
      }
    } finally {
      if (oldToken !== undefined) {
        process.env.METRICS_TOKEN = oldToken;
      } else {
        delete process.env.METRICS_TOKEN;
      }
      if (oldTokenFile !== undefined) {
        process.env.METRICS_TOKEN_FILE = oldTokenFile;
      } else {
        delete process.env.METRICS_TOKEN_FILE;
      }
    }
  });

  it('(w3-4) metrics bearer check accepts only the exact token after a single "Bearer " prefix', async () => {
    const app = Fastify();
    app.decorate('db', db);
    app.decorate('gateway', { status: () => 'connected' });
    await app.register(systemRoute);

    const oldToken = process.env.METRICS_TOKEN;
    const oldTokenFile = process.env.METRICS_TOKEN_FILE;
    delete process.env.METRICS_TOKEN_FILE;
    process.env.METRICS_TOKEN = 'metrics-token-abc';

    const send = (authorization?: string) =>
      app.inject({
        method: 'GET',
        url: '/metrics',
        headers: authorization === undefined ? {} : { authorization },
      });

    try {
      // Near misses that a naive or non-exact comparison could let through
      expect((await send('Bearer metrics-token-ab')).statusCode).toBe(401); // strict prefix of the token
      expect((await send('Bearer metrics-token-abcd')).statusCode).toBe(401); // token with a suffix
      expect((await send('Bearer metrics-token-xyz')).statusCode).toBe(401); // same length, different value
      expect((await send('metrics-token-abc')).statusCode).toBe(401); // token without the Bearer scheme
      expect((await send('Bearer  metrics-token-abc')).statusCode).toBe(401); // extra space after scheme
      expect((await send('Bearer ')).statusCode).toBe(401); // empty token
      expect((await send()).statusCode).toBe(401); // no header

      // Exact match still works
      expect((await send('Bearer metrics-token-abc')).statusCode).toBe(200);
    } finally {
      if (oldToken !== undefined) {
        process.env.METRICS_TOKEN = oldToken;
      } else {
        delete process.env.METRICS_TOKEN;
      }
      if (oldTokenFile !== undefined) {
        process.env.METRICS_TOKEN_FILE = oldTokenFile;
      } else {
        delete process.env.METRICS_TOKEN_FILE;
      }
    }
  });
});
