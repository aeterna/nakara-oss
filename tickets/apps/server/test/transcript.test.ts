import { describe, it, expect, vi, beforeAll, beforeEach, afterAll } from 'vitest';
import Fastify from 'fastify';
import { createHash } from 'node:crypto';
import { openTestDb } from '@nakara-tickets/db/test-support';
import { guilds, categories, tickets, messages, sessions } from '@nakara-tickets/db';
import { sealBytes } from '@nakara-tickets/core';
import { installSession } from '../src/session.js';
import routes from '../src/routes/index.js';
import type { TicketsConfig } from '../src/config.js';

describe('Ticket transcript (acceptance test t3)', () => {
  const GUILD_ID = '111111111111111111';
  const USER_STAFF = '222222222222222222';
  const ROLE_STAFF = '333333333333333333';
  const SESSION_TOKEN = 'transcript-test-session-token';
  const CSRF_TOKEN = 'transcript-test-csrf-token';
  const testKey = Buffer.alloc(32, 9);

  const mockConfig: TicketsConfig = {
    ROLE: 'all',
    PORT: 8080,
    DATABASE_URL: 'postgres://localhost:5432/mock',
    TICKETS_DATA_KEY: testKey,
    DISCORD_TOKEN: 'mock-bot-token',
    DISCORD_APP_ID: '123456789012345678',
    DISCORD_CLIENT_SECRET: 'mock-client-secret',
    PUBLIC_ORIGIN: 'http://localhost:8080',
    ALLOWED_GUILD_IDS: [GUILD_ID],
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

    // 1. Seed guild & category
    await testDb.insert(guilds).values({
      guild_id: GUILD_ID,
      name: 'Test Guild',
    });

    const [cat] = await testDb.insert(categories).values({
      guild_id: GUILD_ID,
      name: 'Support',
      staff_role_ids: [ROLE_STAFF],
      mode: 'thread',
      parent_channel_id: '999999999999999999',
    }).returning();

    // 2. Seed session
    const tokenHash = createHash('sha256').update(SESSION_TOKEN).digest('hex');
    await testDb.insert(sessions).values({
      user_id: USER_STAFF,
      token_hash: tokenHash,
      csrf_hash: CSRF_TOKEN,
      expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
    });

    // 3. Setup app
    app = Fastify();
    app.decorate('config', mockConfig);
    app.decorate('db', testDb);
    await installSession(app, { config: mockConfig, db: testDb });
    await app.register(routes);
    await app.ready();

    // Mock fetch for discord checkStaff
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
          json: async () => [{ id: ROLE_STAFF, permissions: '0' }],
        };
      }
      return { ok: false, status: 404 };
    }));
  });

  it('t3: message <script>alert(1)</script> appears escaped, response has no <script, headers present', async () => {
    // 1. Insert ticket
    const [cat] = await testDb.select().from(categories);
    const [ticket] = await testDb.insert(tickets).values({
      guild_id: GUILD_ID,
      category_id: cat.id,
      number: 42,
      status: 'closed',
      opener_id: '444444444444444444',
      channel_id: '555555555555555555',
    }).returning();

    // 2. Insert malicious message
    const maliciousContent = '<script>alert(1)</script>';
    const contentEnc = sealBytes(testKey, Buffer.from(maliciousContent, 'utf8'));

    await testDb.insert(messages).values({
      id: 'msg_malicious_1',
      guild_id: GUILD_ID,
      ticket_id: ticket.id,
      author_id: '444444444444444444',
      author_name: 'Attacker <img src=x onerror=alert(2)>',
      content_enc: contentEnc,
    });

    // 3. Request transcript
    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${GUILD_ID}/tickets/${ticket.id}/transcript`,
      cookies: { nt_session: SESSION_TOKEN },
    });

    expect(res.statusCode).toBe(200);

    // 4. Assert headers
    const contentDisp = res.headers['content-disposition'];
    expect(contentDisp).toBeDefined();
    expect(contentDisp).toContain('attachment');
    expect(contentDisp).toContain('filename="ticket-42.html"');

    const csp = res.headers['content-security-policy'];
    expect(csp).toBeDefined();
    expect(csp).toContain("default-src 'none'");
    expect(csp).toContain("style-src 'unsafe-inline'");
    expect(csp).toContain('img-src data:');

    const nosniff = res.headers['x-content-type-options'];
    expect(nosniff).toBe('nosniff');

    // 5. Assert body has NO <script tag anywhere (case-insensitive)
    const body = res.body;
    expect(body.toLowerCase()).not.toContain('<script');

    // 6. Assert content was HTML-escaped
    expect(body).toContain('&lt;script&gt;alert(1)&lt;/script&gt;');
  });
});
