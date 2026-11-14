import { describe, it, expect, beforeAll, beforeEach, afterAll } from 'vitest';
import * as schema from '@nakara-tickets/db';
import { openTestDb } from '@nakara-tickets/db/test-support';
import { buildApp } from '../src/app.js';
import type { TicketsConfig } from '../src/config.js';

describe('actions API acceptance tests (g2)', () => {
  let testEnv: Awaited<ReturnType<typeof openTestDb>>;
  let db: any;
  let config: TicketsConfig;
  const guildId = '123456789012345678';
  let serverId: string;
  let ticketId: string;

  beforeAll(async () => {
    testEnv = await openTestDb();
    db = testEnv.db;
  });

  beforeEach(async () => {
    await testEnv.reset();

    config = {
      ROLE: 'all',
      PORT: 8080,
      DATABASE_URL: 'postgres://test',
      TICKETS_DATA_KEY: Buffer.alloc(32, 7),
      DISCORD_TOKEN: 'test-token',
      DISCORD_APP_ID: '123456789012345678',
      DISCORD_CLIENT_SECRET: 'test-secret',
      PUBLIC_ORIGIN: 'http://localhost:8080',
      ALLOWED_GUILD_IDS: [guildId],
      STORAGE_DIR: '/data/files',
    };

    await db.insert(schema.guilds).values({
      guild_id: guildId,
      name: 'Test Guild',
    });

    const [server] = await db
      .insert(schema.gameServers)
      .values({
        guild_id: guildId,
        name: 'Main Server',
        secret_enc: 'enc-secret',
        confirmed: true,
        revoked: false,
      })
      .returning();
    serverId = server.id;

    const [category] = await db
      .insert(schema.categories)
      .values({
        guild_id: guildId,
        name: 'In-Game Support',
        parent_channel_id: '123456789012345678',
        game_server_id: serverId,
      })
      .returning();

    const [ticket] = await db
      .insert(schema.tickets)
      .values({
        guild_id: guildId,
        number: 1,
        category_id: category.id,
        opener_id: '999888777666555444',
        channel_id: '123456789012345678',
      })
      .returning();
    ticketId = ticket.id;
  });

  afterAll(async () => {
    await testEnv.close();
  });

  function createTestApp() {
    const app = buildApp({ db, config });
    app.decorate('requireStaff', async (req: any) => {
      req.user = { id: 'staff-999', username: 'StaffTester' };
      req.guildId = req.params?.guildId || guildId;
    });
    return app;
  }

  it('(g2) repeat-confirm: second give_item within 10 min → 409, with confirmRepeat → 202, different item → 202', async () => {
    const app = createTestApp();

    const postAction = async (payload: any) => {
      return app.inject({
        method: 'POST',
        url: `/api/v1/guilds/${guildId}/tickets/${ticketId}/actions`,
        headers: { 'content-type': 'application/json' },
        payload,
      });
    };

    // 1. First give_item → 202 Queued
    const res1 = await postAction({
      action: 'player.give_item',
      params: { item: 'bandage', count: 2 },
    });
    expect(res1.statusCode).toBe(202);
    const body1 = res1.json();
    expect(body1.action).toBe('player.give_item');
    expect(body1.status).toBe('queued');
    expect(body1.params).toEqual({ item: 'bandage', count: 2 });

    // 2. Second give_item with same item within 10 min without confirmRepeat → 409 repeat_confirm
    const res2 = await postAction({
      action: 'player.give_item',
      params: { item: 'bandage', count: 2 },
    });
    expect(res2.statusCode).toBe(409);
    const body2 = res2.json();
    expect(body2.code).toBe('repeat_confirm');

    // 3. Second give_item with same item within 10 min with confirmRepeat: true → 202 Queued
    const res3 = await postAction({
      action: 'player.give_item',
      params: { item: 'bandage', count: 2 },
      confirmRepeat: true,
    });
    expect(res3.statusCode).toBe(202);
    const body3 = res3.json();
    expect(body3.action).toBe('player.give_item');
    expect(body3.status).toBe('queued');

    // 4. give_item with different item within 10 min → 202 Queued
    const res4 = await postAction({
      action: 'player.give_item',
      params: { item: 'water', count: 1 },
    });
    expect(res4.statusCode).toBe(202);
    const body4 = res4.json();
    expect(body4.action).toBe('player.give_item');
    expect(body4.params).toEqual({ item: 'water', count: 1 });
  });

  it('validates known actions and custom actions', async () => {
    const app = createTestApp();

    const postAction = async (payload: any) => {
      return app.inject({
        method: 'POST',
        url: `/api/v1/guilds/${guildId}/tickets/${ticketId}/actions`,
        headers: { 'content-type': 'application/json' },
        payload,
      });
    };

    // player.teleport requires params.spot
    const teleBad = await postAction({ action: 'player.teleport', params: {} });
    expect(teleBad.statusCode).toBe(400);

    const teleGood = await postAction({ action: 'player.teleport', params: { spot: 'hospital' } });
    expect(teleGood.statusCode).toBe(202);

    // player.revive requires no params
    const reviveGood = await postAction({ action: 'player.revive' });
    expect(reviveGood.statusCode).toBe(202);

    // player.info requires no params
    const infoGood = await postAction({ action: 'player.info' });
    expect(infoGood.statusCode).toBe(202);

    // Custom action with valid name and params <= 16 keys → 202
    const customGood = await postAction({
      action: 'custom.set_weather',
      params: { weather: 'extrasunny' },
    });
    expect(customGood.statusCode).toBe(202);

    // Custom action with invalid name pattern → 400
    const customBadName = await postAction({
      action: 'INVALID ACTION!',
      params: { weather: 'extrasunny' },
    });
    expect(customBadName.statusCode).toBe(400);

    // Custom action with > 16 keys → 400
    const tooManyKeys: Record<string, number> = {};
    for (let i = 0; i < 17; i++) {
      tooManyKeys[`key_${i}`] = i;
    }
    const customTooManyKeys = await postAction({
      action: 'custom.many_keys',
      params: tooManyKeys,
    });
    expect(customTooManyKeys.statusCode).toBe(400);
  });
});
