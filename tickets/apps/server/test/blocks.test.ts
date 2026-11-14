import { describe, it, expect, vi, beforeAll, beforeEach, afterAll } from 'vitest';
import Fastify from 'fastify';
import { createHash } from 'node:crypto';
import { openTestDb } from '@nakara-tickets/db/test-support';
import { guilds, sessions, blocks } from '@nakara-tickets/db';
import { installSession } from '../src/session.js';
import { clearStaffCache } from '../src/staff.js';
import routes from '../src/routes/index.js';
import type { TicketsConfig } from '../src/config.js';

describe('a3 blocks route acceptance tests', () => {
  const GUILD_A = '111111111111111111';
  const GUILD_B = '222222222222222222';
  const USER_STAFF = '333333333333333333';
  const ROLE_STAFF = '444444444444444444';
  const TARGET_USER_1 = '555555555555555555';
  const SESSION_TOKEN = 'blocks-test-session-token';
  const CSRF_TOKEN = 'blocks-test-csrf-token';

  const mockConfig: TicketsConfig = {
    ROLE: 'all',
    PORT: 8080,
    DATABASE_URL: 'postgres://localhost:5432/mock',
    TICKETS_DATA_KEY: Buffer.alloc(32, 2),
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

  afterAll(async () => {
    await testEnv.close();
  });

  beforeEach(async () => {
    await testEnv.reset();
    clearStaffCache();

    // Seed guilds
    await testDb.insert(guilds).values([
      { guild_id: GUILD_A, name: 'Guild A' },
      { guild_id: GUILD_B, name: 'Guild B' },
    ]);

    // Seed session for staff user
    const tokenHash = createHash('sha256').update(SESSION_TOKEN).digest('hex');
    await testDb.insert(sessions).values({
      user_id: USER_STAFF,
      token_hash: tokenHash,
      csrf_hash: CSRF_TOKEN,
      expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
    });

    // Mock fetch for staff check
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
        return {
          ok: true,
          status: 200,
          json: async () => [
            { id: ROLE_STAFF, name: 'Staff', permissions: String(1n << 3n) }, // Admin
          ],
        };
      }
      if (urlStr.includes('/users/')) {
        return {
          ok: true,
          status: 200,
          json: async () => ({ id: USER_STAFF, username: 'staffuser', avatar: null }),
        };
      }
      return { ok: false, status: 404 };
    }));

    app = Fastify();
    app.decorate('config', mockConfig);
    app.decorate('db', testDb);
    await installSession(app, { config: mockConfig, db: testDb });
    await app.register(routes);
    await app.ready();
  });

  it('a3-1: create block and reject duplicate with 409', async () => {
    // 1. Create block in Guild A
    const resCreate = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/blocks`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
      payload: {
        userId: TARGET_USER_1,
        reason: 'Spamming tickets repeatedly',
      },
    });

    expect(resCreate.statusCode).toBe(201);
    const created = JSON.parse(resCreate.body);
    expect(created.userId ?? created.user_id).toBe(TARGET_USER_1);
    expect(created.reason).toBe('Spamming tickets repeatedly');

    // 2. Duplicate block in the same guild -> 409
    const resDup = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/blocks`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
      payload: {
        userId: TARGET_USER_1,
        reason: 'Another reason',
      },
    });

    expect(resDup.statusCode).toBe(409);
    const err = JSON.parse(resDup.body);
    expect(err.code).toBe('conflict');
  });

  it('a3-2: rejects invalid userId or overly long reason with 400', async () => {
    // Invalid snowflake (not 17-20 digits)
    const resBadUser = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/blocks`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
      payload: {
        userId: 'not-a-snowflake',
        reason: 'Valid reason',
      },
    });
    expect(resBadUser.statusCode).toBe(400);

    // Reason > 500 characters
    const resLongReason = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/blocks`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
      payload: {
        userId: TARGET_USER_1,
        reason: 'x'.repeat(501),
      },
    });
    expect(resLongReason.statusCode).toBe(400);
  });

  it('a3-3: blocks are guild scoped and list/delete behave correctly', async () => {
    // 1. Block user in Guild A
    await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/blocks`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
      payload: {
        userId: TARGET_USER_1,
        reason: 'Blocked in Guild A',
      },
    });

    // 2. Block same user in Guild B -> should succeed (201)
    const resGuildB = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_B}/blocks`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
      payload: {
        userId: TARGET_USER_1,
        reason: 'Blocked in Guild B',
      },
    });
    expect(resGuildB.statusCode).toBe(201);

    // 3. List Guild A -> contains 1 block
    const resListA = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${GUILD_A}/blocks`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
      },
    });
    expect(resListA.statusCode).toBe(200);
    const listA = JSON.parse(resListA.body);
    expect(listA.length).toBe(1);
    expect(listA[0].reason).toBe('Blocked in Guild A');

    // 4. Delete block in Guild A
    const resDel = await app.inject({
      method: 'DELETE',
      url: `/api/v1/guilds/${GUILD_A}/blocks/${TARGET_USER_1}`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
    });
    expect(resDel.statusCode).toBe(204);

    // 5. Verify Guild A block is gone, Guild B still remains
    const resListA2 = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${GUILD_A}/blocks`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
      },
    });
    expect(JSON.parse(resListA2.body).length).toBe(0);

    const resListB2 = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${GUILD_B}/blocks`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
      },
    });
    expect(JSON.parse(resListB2.body).length).toBe(1);
  });
});
