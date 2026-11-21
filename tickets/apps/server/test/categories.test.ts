import { describe, it, expect, vi, beforeAll, beforeEach, afterAll } from 'vitest';
import Fastify from 'fastify';
import { eq } from 'drizzle-orm';
import * as dbSchema from '@nakara-tickets/db';
import { guilds, categories, tickets, gameServers } from '@nakara-tickets/db';
import { openTestDb } from '@nakara-tickets/db/test-support';
import { installSession } from '../src/session.js';
import { clearStaffCache } from '../src/staff.js';
import routes from '../src/routes/index.js';
import type { TicketsConfig } from '../src/config.js';
import { createTestSession } from './helpers/session.js';

vi.mock('@nakara-tickets/core', async (importOriginal) => {
  const orig = await importOriginal<Record<string, any>>();
  const isStaff = orig.isStaff ?? (({ permissions, roleIds, staffRoleIds }: { permissions: bigint; roleIds: string[]; staffRoleIds: string[] }) => {
    const ADMINISTRATOR = 1n << 3n;
    const MANAGE_GUILD = 1n << 5n;
    if ((permissions & ADMINISTRATOR) !== 0n || (permissions & MANAGE_GUILD) !== 0n) return true;
    const staffSet = new Set(staffRoleIds);
    return roleIds.some((r) => staffSet.has(r));
  });
  return {
    ...orig,
    isStaff,
  };
});

describe('categories acceptance tests', () => {
  const GUILD_A = '111111111111111111';
  const GUILD_B = '222222222222222222';
  const USER_STAFF = '333333333333333333';
  const ROLE_STAFF = '444444444444444444';
  let cookie: string;
  let csrf: string;

  const mockConfig: TicketsConfig = {
    ROLE: 'all',
    PORT: 8080,
    DATABASE_URL: 'postgres://localhost:5432/mock',
    TICKETS_DATA_KEY: Buffer.alloc(32, 3),
    DISCORD_TOKEN: 'mock-bot-token',
    DISCORD_APP_ID: '123456789012345678',
    DISCORD_CLIENT_SECRET: 'mock-client-secret',
    PUBLIC_ORIGIN: 'http://localhost:8080',
    ALLOWED_GUILD_IDS: [GUILD_A, GUILD_B],
    STORAGE_DIR: '/tmp/tickets',
  };

  let testEnv: Awaited<ReturnType<typeof openTestDb>>;
  let testDb: any;
  let app: ReturnType<typeof Fastify>;

  beforeAll(async () => {
    testEnv = await openTestDb();
    testDb = testEnv.db;
  });

  beforeEach(async () => {
    await testEnv.reset();
    clearStaffCache();

    // Seed guilds
    await testDb.insert(guilds).values([
      { guild_id: GUILD_A, name: 'Guild A' },
      { guild_id: GUILD_B, name: 'Guild B' },
    ]);

    // Seed session
    ({ cookie, csrf } = await createTestSession(testDb, mockConfig, {
      userId: USER_STAFF,
      username: 'staffuser',
    }));

    app = Fastify();
    app.decorate('config', mockConfig);
    app.decorate('db', testDb);
    await installSession(app, { config: mockConfig, db: testDb });
    await app.register(routes);
    await app.ready();

    // Stub global fetch for Discord API calls (staff in both guilds)
    vi.stubGlobal('fetch', vi.fn().mockImplementation(async (url: string) => {
      const urlStr = String(url);
      if (urlStr.includes('/members/')) {
        return {
          ok: true,
          status: 200,
          json: async () => ({
            roles: [ROLE_STAFF],
            user: { id: USER_STAFF, username: 'staffuser', avatar: null },
          }),
        };
      }
      if (urlStr.includes('/roles')) {
        const guildId = urlStr.includes(GUILD_A) ? GUILD_A : GUILD_B;
        return {
          ok: true,
          status: 200,
          json: async () => [
            { id: guildId, name: '@everyone', permissions: '0' },
            { id: ROLE_STAFF, name: 'Staff', permissions: String(1n << 5n) }, // MANAGE_GUILD
          ],
        };
      }
      return { ok: false, status: 404, json: async () => ({}) };
    }));
  });

  afterAll(async () => {
    await testEnv.close();
  });

  it('GET /api/v1/guilds/:guildId/categories returns categories for guild', async () => {
    const postRes = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/categories`,
      headers: {
        cookie,
        'x-csrf-token': csrf,
        'content-type': 'application/json',
      },
      payload: {
        name: 'Billing',
        staffRoleIds: [ROLE_STAFF],
        mode: 'thread',
        parentChannelId: '123456789012345678',
      },
    });
    expect(postRes.statusCode).toBe(201);
    const createdCat = postRes.json();
    expect(createdCat.name).toBe('Billing');
    expect(createdCat.parentChannelId).toBe('123456789012345678');
    expect(createdCat.staffRoleIds).toEqual([ROLE_STAFF]);
    expect(createdCat.mode).toBe('thread');
    expect(createdCat.nameTemplate).toBe('ticket-{number}');
    expect(createdCat.maxOpenPerUser).toBe(1);
    expect(createdCat.gameServerId).toBeNull();
    expect(createdCat.createdAt).toBeDefined();
    expect(createdCat).not.toHaveProperty('parent_channel_id');
    expect(createdCat).not.toHaveProperty('staff_role_ids');

    const getRes = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${GUILD_A}/categories`,
      headers: {
        cookie,
      },
    });
    expect(getRes.statusCode).toBe(200);
    const list = getRes.json();
    expect(Array.isArray(list)).toBe(true);
    expect(list.length).toBe(1);
    expect(list[0].name).toBe('Billing');
    expect(list[0].parentChannelId).toBe('123456789012345678');
    expect(list[0].staffRoleIds).toEqual([ROLE_STAFF]);
    expect(list[0].gameServerId).toBeNull();
    expect(list[0]).not.toHaveProperty('parent_channel_id');
    expect(list[0]).not.toHaveProperty('staff_role_ids');
  });

  it('(a5) category of guild A not reachable via guild B → 404', async () => {
    // 1. Create a category under Guild A
    const postRes = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/categories`,
      headers: {
        cookie,
        'x-csrf-token': csrf,
        'content-type': 'application/json',
      },
      payload: {
        name: 'Guild A Secret Category',
        staffRoleIds: [ROLE_STAFF],
        mode: 'thread',
        parentChannelId: '123456789012345678',
      },
    });
    expect(postRes.statusCode).toBe(201);
    const catA = postRes.json();
    const catAId = catA.id;

    // 2. Attempt to update category of Guild A using Guild B route → 404
    const putRes = await app.inject({
      method: 'PUT',
      url: `/api/v1/guilds/${GUILD_B}/categories/${catAId}`,
      headers: {
        cookie,
        'x-csrf-token': csrf,
        'content-type': 'application/json',
      },
      payload: {
        name: 'Hacked Name',
        staffRoleIds: [ROLE_STAFF],
        mode: 'thread',
        parentChannelId: '123456789012345678',
      },
    });
    expect(putRes.statusCode).toBe(404);
    expect(putRes.json().code).toBe('not_found');

    // 3. Attempt to delete category of Guild A using Guild B route → 404
    const delRes = await app.inject({
      method: 'DELETE',
      url: `/api/v1/guilds/${GUILD_B}/categories/${catAId}`,
      headers: {
        cookie,
        'x-csrf-token': csrf,
      },
    });
    expect(delRes.statusCode).toBe(404);
    expect(delRes.json().code).toBe('not_found');
  });

  it('PUT and DELETE /api/v1/guilds/:guildId/categories/:categoryId works and handles 409 limit', async () => {
    // Create category
    const postRes = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/categories`,
      headers: {
        cookie,
        'x-csrf-token': csrf,
        'content-type': 'application/json',
      },
      payload: {
        name: 'Technical',
        staffRoleIds: [ROLE_STAFF],
        mode: 'thread',
        parentChannelId: '123456789012345678',
      },
    });
    const cat = postRes.json();

    // Update category
    const putRes = await app.inject({
      method: 'PUT',
      url: `/api/v1/guilds/${GUILD_A}/categories/${cat.id}`,
      headers: {
        cookie,
        'x-csrf-token': csrf,
        'content-type': 'application/json',
      },
      payload: {
        name: 'Technical Support',
        staffRoleIds: [ROLE_STAFF],
        mode: 'channel',
        parentChannelId: '123456789012345678',
      },
    });
    expect(putRes.statusCode).toBe(200);
    const updated = putRes.json();
    expect(updated.name).toBe('Technical Support');
    expect(updated.mode).toBe('channel');
    expect(updated.parentChannelId).toBe('123456789012345678');
    expect(updated.staffRoleIds).toEqual([ROLE_STAFF]);
    expect(updated).not.toHaveProperty('parent_channel_id');
    expect(updated).not.toHaveProperty('staff_role_ids');

    // Attach a ticket to this category to test 409 on delete
    await testDb.insert(tickets).values({
      guild_id: GUILD_A,
      number: 1,
      category_id: cat.id,
      opener_id: USER_STAFF,
      channel_id: '999999999999999999',
    });

    // Attempt delete when referenced by tickets -> 409
    const delConflictRes = await app.inject({
      method: 'DELETE',
      url: `/api/v1/guilds/${GUILD_A}/categories/${cat.id}`,
      headers: {
        cookie,
        'x-csrf-token': csrf,
      },
    });
    expect(delConflictRes.statusCode).toBe(409);
    expect(delConflictRes.json().code).toBe('conflict');

    // Remove referencing ticket
    await testDb.delete(tickets).where(eq(tickets.category_id, cat.id));

    // Delete category cleanly -> 204
    const delCleanRes = await app.inject({
      method: 'DELETE',
      url: `/api/v1/guilds/${GUILD_A}/categories/${cat.id}`,
      headers: {
        cookie,
        'x-csrf-token': csrf,
      },
    });
    expect(delCleanRes.statusCode).toBe(204);
  });

  it('PUT with nulls clears emoji, welcomeMessage and autoCloseHours', async () => {
    const postRes = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/categories`,
      headers: { cookie, 'x-csrf-token': csrf, 'content-type': 'application/json' },
      payload: {
        name: 'Clearable Category',
        emoji: '🎫',
        welcomeMessage: 'Hello Welcome',
        autoCloseHours: 48,
        staffRoleIds: [ROLE_STAFF],
        mode: 'thread',
        parentChannelId: '123456789012345678',
      },
    });
    expect(postRes.statusCode).toBe(201);
    const cat = postRes.json();
    expect(cat.emoji).toBe('🎫');
    expect(cat.welcomeMessage).toBe('Hello Welcome');
    expect(cat.autoCloseHours).toBe(48);

    const putRes = await app.inject({
      method: 'PUT',
      url: `/api/v1/guilds/${GUILD_A}/categories/${cat.id}`,
      headers: { cookie, 'x-csrf-token': csrf, 'content-type': 'application/json' },
      payload: {
        name: 'Clearable Category',
        emoji: null,
        welcomeMessage: null,
        autoCloseHours: null,
        staffRoleIds: [ROLE_STAFF],
        mode: 'thread',
        parentChannelId: '123456789012345678',
      },
    });
    expect(putRes.statusCode).toBe(200);
    const updated = putRes.json();
    expect(updated.emoji).toBeNull();
    expect(updated.welcomeMessage).toBeNull();
    expect(updated.autoCloseHours).toBeNull();

    const [dbRow] = await testDb.select().from(categories).where(eq(categories.id, cat.id));
    expect(dbRow.emoji).toBeNull();
    expect(dbRow.welcome_message).toBeNull();
    expect(dbRow.auto_close_hours).toBeNull();
  });

  it('rejects gameServerId from another guild or non-existent server with 400', async () => {
    const [serverB] = await testDb.insert(gameServers).values({
      guild_id: GUILD_B,
      name: 'Guild B Server',
      secret_enc: Buffer.from('secret-b'),
    }).returning();

    const postRes = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/categories`,
      headers: { cookie, 'x-csrf-token': csrf, 'content-type': 'application/json' },
      payload: {
        name: 'Cross Guild Server Category',
        staffRoleIds: [ROLE_STAFF],
        mode: 'thread',
        parentChannelId: '123456789012345678',
        gameServerId: serverB.id,
      },
    });
    expect(postRes.statusCode).toBe(400);
    expect(postRes.json()).toEqual({ code: 'invalid', message: 'unknown game server' });

    const validPost = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/categories`,
      headers: { cookie, 'x-csrf-token': csrf, 'content-type': 'application/json' },
      payload: {
        name: 'Valid Category',
        staffRoleIds: [ROLE_STAFF],
        mode: 'thread',
        parentChannelId: '123456789012345678',
      },
    });
    const validCat = validPost.json();

    const putRes = await app.inject({
      method: 'PUT',
      url: `/api/v1/guilds/${GUILD_A}/categories/${validCat.id}`,
      headers: { cookie, 'x-csrf-token': csrf, 'content-type': 'application/json' },
      payload: {
        name: 'Valid Category',
        staffRoleIds: [ROLE_STAFF],
        mode: 'thread',
        parentChannelId: '123456789012345678',
        gameServerId: serverB.id,
      },
    });
    expect(putRes.statusCode).toBe(400);
    expect(putRes.json()).toEqual({ code: 'invalid', message: 'unknown game server' });
  });
});
