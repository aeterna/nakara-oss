import { describe, it, expect, vi, beforeAll, beforeEach, afterAll } from 'vitest';
import Fastify from 'fastify';
import { createHash } from 'node:crypto';
import { openTestDb } from '@nakara-tickets/db/test-support';
import { guilds, sessions, tags } from '@nakara-tickets/db';
import { installSession } from '../src/session.js';
import { clearStaffCache } from '../src/staff.js';
import routes from '../src/routes/index.js';
import type { TicketsConfig } from '../src/config.js';

describe('a2 tags route acceptance tests', () => {
  const GUILD_A = '111111111111111111';
  const GUILD_B = '222222222222222222';
  const USER_STAFF = '333333333333333333';
  const ROLE_STAFF = '444444444444444444';
  const SESSION_TOKEN = 'tags-test-session-token';
  const CSRF_TOKEN = 'tags-test-csrf-token';

  const mockConfig: TicketsConfig = {
    ROLE: 'all',
    PORT: 8080,
    DATABASE_URL: 'postgres://localhost:5432/mock',
    TICKETS_DATA_KEY: Buffer.alloc(32, 1),
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

  it('a2-1: create tag and prevent duplicate name with 409', async () => {
    // 1. Create tag in Guild A
    const resCreate = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/tags`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
      payload: {
        name: 'rules-general',
        content: 'Please follow the general server rules {user}.',
      },
    });

    expect(resCreate.statusCode).toBe(201);
    const created = JSON.parse(resCreate.body);
    expect(created.name).toBe('rules-general');
    expect(created.id).toBeDefined();

    // 2. Duplicate tag name in the same guild -> 409
    const resDup = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/tags`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
      payload: {
        name: 'rules-general',
        content: 'Different content.',
      },
    });

    expect(resDup.statusCode).toBe(409);
    const err = JSON.parse(resDup.body);
    expect(err.code).toBe('conflict');
  });

  it('a2-2: rejects bad tag names with 400', async () => {
    // Uppercase characters not allowed by pattern ^[a-z0-9-]{1,32}$
    const resUpper = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/tags`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
      payload: {
        name: 'INVALID_NAME',
        content: 'Content',
      },
    });
    expect(resUpper.statusCode).toBe(400);

    // Empty name
    const resEmpty = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/tags`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
      payload: {
        name: '',
        content: 'Content',
      },
    });
    expect(resEmpty.statusCode).toBe(400);

    // Name too long (>32 chars)
    const resTooLong = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/tags`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
      payload: {
        name: 'a'.repeat(33),
        content: 'Content',
      },
    });
    expect(resTooLong.statusCode).toBe(400);

    // Body too long (>2000 chars)
    const resBodyTooLong = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/tags`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
      payload: {
        name: 'long-body',
        content: 'x'.repeat(2001),
      },
    });
    expect(resBodyTooLong.statusCode).toBe(400);
  });

  it('a2-3: tags are guild scoped (same name allowed in different guild, list only own guild)', async () => {
    // 1. Create in Guild A
    await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/tags`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
      payload: {
        name: 'welcome-tag',
        content: 'Welcome to Guild A {user}',
      },
    });

    // 2. Create same tag name in Guild B -> should SUCCEED (201)
    const resGuildB = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_B}/tags`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
      payload: {
        name: 'welcome-tag',
        content: 'Welcome to Guild B {user}',
      },
    });
    expect(resGuildB.statusCode).toBe(201);

    // 3. List Guild A tags -> only contains Guild A tag
    const resListA = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${GUILD_A}/tags`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
      },
    });
    expect(resListA.statusCode).toBe(200);
    const tagsA = JSON.parse(resListA.body);
    expect(tagsA.length).toBe(1);
    expect(tagsA[0].content).toContain('Guild A');

    // 4. List Guild B tags -> only contains Guild B tag
    const resListB = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${GUILD_B}/tags`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
      },
    });
    expect(resListB.statusCode).toBe(200);
    const tagsB = JSON.parse(resListB.body);
    expect(tagsB.length).toBe(1);
    expect(tagsB[0].content).toContain('Guild B');
  });

  it('a2-4: updates and deletes tag correctly', async () => {
    // Create tag
    const resCreate = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/tags`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
      payload: {
        name: 'my-tag',
        content: 'Initial text',
      },
    });
    const tagId = JSON.parse(resCreate.body).id;

    // Update tag
    const resUpdate = await app.inject({
      method: 'PUT',
      url: `/api/v1/guilds/${GUILD_A}/tags/${tagId}`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
      payload: {
        name: 'my-tag-renamed',
        content: 'Updated text {user}',
      },
    });
    expect(resUpdate.statusCode).toBe(200);
    const updated = JSON.parse(resUpdate.body);
    expect(updated.name).toBe('my-tag-renamed');

    // Delete tag
    const resDel = await app.inject({
      method: 'DELETE',
      url: `/api/v1/guilds/${GUILD_A}/tags/${tagId}`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
    });
    expect(resDel.statusCode).toBe(204);

    // Verify deleted
    const resList = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${GUILD_A}/tags`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
      },
    });
    expect(JSON.parse(resList.body).length).toBe(0);
  });
});
