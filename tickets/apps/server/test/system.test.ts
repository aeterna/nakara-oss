import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import Fastify from 'fastify';
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

  it('(w3-1) healthz 200/up with a working pglite db', async () => {
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
    expect(body.ok).toBe(true);
    expect(body.db).toBe('up');
    expect(body.gateway).toBe('connected');
    expect(body.version).toBeDefined();
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
  });

  it('(w3-3) metrics contains the four series and no snowflake', async () => {
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
      { guild_id: guildId, category_id: cat.id, number: 1, opener_id: '111111111111111111', status: 'open' },
      { guild_id: guildId, category_id: cat.id, number: 2, opener_id: '222222222222222222', status: 'claimed' },
      { guild_id: guildId, category_id: cat.id, number: 3, opener_id: '333333333333333333', status: 'closed' },
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

    const res = await app.inject({
      method: 'GET',
      url: '/metrics',
    });

    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('text/plain; version=0.0.4');

    const text = res.payload;

    // Check all four series
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
  });
});
