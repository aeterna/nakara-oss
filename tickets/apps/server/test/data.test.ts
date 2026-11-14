import { describe, it, expect, vi, beforeAll, beforeEach, afterAll } from 'vitest';
import Fastify from 'fastify';
import { createHash } from 'node:crypto';
import { openTestDb, type TestDbHandle } from '@nakara-tickets/db/test-support';
import {
  guilds,
  guildSettings,
  categories,
  tickets,
  messages,
  sessions,
} from '@nakara-tickets/db';
import { installSession } from '../src/session.js';
import dataRoutes from '../src/routes/data.js';
import type { TicketsConfig } from '../src/config.js';
import { sealBytes } from '@nakara-tickets/core';

describe('data routes (p4)', () => {
  let testEnv: TestDbHandle;
  let db: any;
  let app: ReturnType<typeof Fastify>;

  const GUILD_ALLOWED = '111111111111111111';
  const USER_STAFF = '222222222222222222';
  const USER_REGULAR = '333333333333333333';
  const DATA_KEY = Buffer.alloc(32, 5);

  const mockConfig: TicketsConfig = {
    ROLE: 'all',
    PORT: 8080,
    DATABASE_URL: 'postgres://localhost:5432/mock',
    TICKETS_DATA_KEY: DATA_KEY,
    DISCORD_TOKEN: 'mock-bot-token',
    DISCORD_APP_ID: '123456789012345678',
    DISCORD_CLIENT_SECRET: 'mock-client-secret',
    PUBLIC_ORIGIN: 'http://localhost:8080',
    ALLOWED_GUILD_IDS: [GUILD_ALLOWED],
    STORAGE_DIR: '/tmp/tickets',
  };

  beforeAll(async () => {
    testEnv = await openTestDb();
    db = testEnv.db;
  });

  beforeEach(async () => {
    await testEnv.reset();

    await db.insert(guilds).values({
      guild_id: GUILD_ALLOWED,
      name: 'Test Guild',
    });

    await db.insert(guildSettings).values({
      guild_id: GUILD_ALLOWED,
      retention_days: 90,
    });

    app = Fastify();
    app.decorate('config', mockConfig);
    app.decorate('db', db);
    await installSession(app, { config: mockConfig, db });
    await app.register(dataRoutes);
    await app.ready();

    // Stub global fetch for Discord API calls (staff check)
    vi.stubGlobal('fetch', vi.fn().mockImplementation(async (url: string) => {
      const urlStr = String(url);
      if (urlStr.includes(`/guilds/${GUILD_ALLOWED}/members/${USER_STAFF}`)) {
        return {
          ok: true,
          status: 200,
          json: async () => ({
            roles: ['staff-role-id'],
            user: { id: USER_STAFF, username: 'staffuser' },
          }),
        };
      }
      if (urlStr.includes(`/guilds/${GUILD_ALLOWED}/roles`)) {
        return {
          ok: true,
          status: 200,
          json: async () => [
            { id: GUILD_ALLOWED, name: '@everyone', permissions: '0' },
            { id: 'staff-role-id', name: 'Staff', permissions: String(1n << 5n) }, // MANAGE_GUILD
          ],
        };
      }
      return { ok: false, status: 404, json: async () => ({}) };
    }));
  });

  afterAll(async () => {
    await testEnv.close();
  });

  async function createSession(userId: string, rawToken: string, csrf: string) {
    const tokenHash = createHash('sha256').update(rawToken).digest('hex');
    await db.insert(sessions).values({
      user_id: userId,
      token_hash: tokenHash,
      csrf_hash: csrf,
      expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
    });
  }

  // Acceptance test p4:
  // p4 route deleteMeData without CSRF → 403.
  it('p4: route deleteMeData without CSRF → 403', async () => {
    const rawToken = 'regular-session-token-32b';
    const csrf = 'valid-csrf-token-123';
    await createSession(USER_REGULAR, rawToken, csrf);

    // 1. Without cookie -> 401
    const resNoCookie = await app.inject({
      method: 'DELETE',
      url: '/api/v1/me/data',
    });
    expect(resNoCookie.statusCode).toBe(401);

    // 2. With cookie, but NO CSRF header -> 403
    const resNoCsrf = await app.inject({
      method: 'DELETE',
      url: '/api/v1/me/data',
      headers: {
        cookie: `nt_session=${rawToken}`,
      },
    });
    expect(resNoCsrf.statusCode).toBe(403);
    expect(resNoCsrf.json().code).toBe('csrf');

    // 3. With wrong CSRF header -> 403
    const resWrongCsrf = await app.inject({
      method: 'DELETE',
      url: '/api/v1/me/data',
      headers: {
        cookie: `nt_session=${rawToken}`,
        'x-csrf-token': 'wrong-csrf',
      },
    });
    expect(resWrongCsrf.statusCode).toBe(403);
    expect(resWrongCsrf.json().code).toBe('csrf');

    // 4. With valid cookie and matching CSRF -> 200 and returns counts
    const resValid = await app.inject({
      method: 'DELETE',
      url: '/api/v1/me/data',
      headers: {
        cookie: `nt_session=${rawToken}`,
        'x-csrf-token': csrf,
      },
    });
    expect(resValid.statusCode).toBe(200);
    const body = resValid.json();
    expect(body.counts).toBeDefined();
    expect(body.counts.messages).toBe(0);
    expect(body.counts.attachments).toBe(0);
  });

  it('getExport requires staff and sets Content-Disposition header', async () => {
    const staffToken = 'staff-token-32b';
    const staffCsrf = 'staff-csrf-123';
    await createSession(USER_STAFF, staffToken, staffCsrf);

    const regularToken = 'regular-token-32b';
    const regularCsrf = 'regular-csrf-123';
    await createSession(USER_REGULAR, regularToken, regularCsrf);

    // Seed some data to export
    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: GUILD_ALLOWED,
        name: 'Billing',
        parent_channel_id: '555555555555555555',
      })
      .returning();

    const [tkt] = await db
      .insert(tickets)
      .values({
        guild_id: GUILD_ALLOWED,
        number: 1,
        category_id: cat.id,
        opener_id: USER_REGULAR,
        channel_id: '666666666666666666',
      })
      .returning();

    await db.insert(messages).values({
      id: 'msg-exp-route',
      guild_id: GUILD_ALLOWED,
      ticket_id: tkt.id,
      author_id: USER_REGULAR,
      author_name: 'Regular',
      content_enc: sealBytes(DATA_KEY, Buffer.from('Export route message content')),
    });

    // 1. Regular user -> 403 forbidden
    const resForbidden = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${GUILD_ALLOWED}/export`,
      headers: {
        cookie: `nt_session=${regularToken}`,
      },
    });
    expect(resForbidden.statusCode).toBe(403);

    // 2. Staff user -> 200 with Content-Disposition
    const resExport = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${GUILD_ALLOWED}/export`,
      headers: {
        cookie: `nt_session=${staffToken}`,
      },
    });
    expect(resExport.statusCode).toBe(200);
    expect(resExport.headers['content-disposition']).toBe(
      `attachment; filename="nakara-tickets-${GUILD_ALLOWED}.json"`,
    );

    const exported = resExport.json();
    expect(exported.tickets.length).toBe(1);
    expect(exported.tickets[0].messages[0].content).toBe('Export route message content');
  });
});
