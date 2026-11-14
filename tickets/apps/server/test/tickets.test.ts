import { describe, it, expect, vi, beforeAll, beforeEach, afterAll } from 'vitest';
import Fastify from 'fastify';
import { createHash } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openTestDb } from '@nakara-tickets/db/test-support';
import { guilds, categories, tickets, messages, attachments, sessions } from '@nakara-tickets/db';
import { sealBytes } from '@nakara-tickets/core';
import { installSession } from '../src/session.js';
import { createStorage } from '../src/storage.js';
import routes from '../src/routes/index.js';
import type { TicketsConfig } from '../src/config.js';

describe('Tickets API routes (acceptance tests t4 & t5)', () => {
  const GUILD_A = '111111111111111111';
  const GUILD_B = '222222222222222222';
  const USER_STAFF = '333333333333333333';
  const ROLE_STAFF = '444444444444444444';
  const SESSION_TOKEN = 'tickets-test-session-token';
  const CSRF_TOKEN = 'tickets-test-csrf-token';
  const testKey = Buffer.alloc(32, 4);

  let tempDir: string;
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
    tempDir = mkdtempSync(join(tmpdir(), 'tickets-api-test-'));

    const mockConfig: TicketsConfig = {
      ROLE: 'all',
      PORT: 8080,
      DATABASE_URL: 'postgres://localhost:5432/mock',
      TICKETS_DATA_KEY: testKey,
      DISCORD_TOKEN: 'mock-bot-token',
      DISCORD_APP_ID: '123456789012345678',
      DISCORD_CLIENT_SECRET: 'mock-client-secret',
      PUBLIC_ORIGIN: 'http://localhost:8080',
      ALLOWED_GUILD_IDS: [GUILD_A, GUILD_B],
      STORAGE_DIR: tempDir,
    };

    // 1. Seed guilds & categories
    await testDb.insert(guilds).values([
      { guild_id: GUILD_A, name: 'Guild A' },
      { guild_id: GUILD_B, name: 'Guild B' },
    ]);

    await testDb.insert(categories).values([
      {
        id: '11111111-1111-1111-1111-111111111111',
        guild_id: GUILD_A,
        name: 'Support A',
        staff_role_ids: [ROLE_STAFF],
        mode: 'thread',
        parent_channel_id: '999999999999999999',
      },
      {
        id: '22222222-2222-2222-2222-222222222222',
        guild_id: GUILD_B,
        name: 'Support B',
        staff_role_ids: [ROLE_STAFF],
        mode: 'thread',
        parent_channel_id: '888888888888888888',
      },
    ]);

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

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
    vi.restoreAllMocks();
  });

  it('t4: tickets list scoped by guild (other guilds ticket absent), cursor works', async () => {
    const catAId = '11111111-1111-1111-1111-111111111111';
    const catBId = '22222222-2222-2222-2222-222222222222';

    // Insert 3 tickets in Guild A
    const tA1 = await testDb.insert(tickets).values({
      guild_id: GUILD_A,
      category_id: catAId,
      number: 1,
      status: 'open',
      opener_id: '1001',
      channel_id: '2001',
      created_at: new Date('2026-01-01T10:00:00Z'),
    }).returning();

    const tA2 = await testDb.insert(tickets).values({
      guild_id: GUILD_A,
      category_id: catAId,
      number: 2,
      status: 'open',
      opener_id: '1002',
      channel_id: '2002',
      created_at: new Date('2026-01-01T11:00:00Z'),
    }).returning();

    const tA3 = await testDb.insert(tickets).values({
      guild_id: GUILD_A,
      category_id: catAId,
      number: 3,
      status: 'open',
      opener_id: '1003',
      channel_id: '2003',
      created_at: new Date('2026-01-01T12:00:00Z'),
    }).returning();

    // Insert 1 ticket in Guild B
    const tB1 = await testDb.insert(tickets).values({
      guild_id: GUILD_B,
      category_id: catBId,
      number: 100,
      status: 'open',
      opener_id: '9999',
      channel_id: '8888',
      created_at: new Date('2026-01-01T13:00:00Z'),
    }).returning();

    // Request list for Guild A with limit=2
    const resPage1 = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${GUILD_A}/tickets?limit=2`,
      cookies: { nt_session: SESSION_TOKEN },
    });

    expect(resPage1.statusCode).toBe(200);
    const dataPage1 = resPage1.json();
    expect(dataPage1.items).toHaveLength(2);

    // Verify Guild B ticket is absent
    const numbersPage1 = dataPage1.items.map((t: any) => t.number);
    expect(numbersPage1).not.toContain(100);
    // Newest first -> number 3, then number 2
    expect(numbersPage1).toEqual([3, 2]);
    expect(dataPage1.next).toBeTruthy();

    // Request second page with cursor
    const resPage2 = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${GUILD_A}/tickets?limit=2&cursor=${encodeURIComponent(dataPage1.next)}`,
      cookies: { nt_session: SESSION_TOKEN },
    });

    expect(resPage2.statusCode).toBe(200);
    const dataPage2 = resPage2.json();
    expect(dataPage2.items).toHaveLength(1);
    expect(dataPage2.items[0].number).toBe(1);
  });

  it('t5: attachment row with content_type text/html served as application/octet-stream', async () => {
    const catAId = '11111111-1111-1111-1111-111111111111';

    const [ticket] = await testDb.insert(tickets).values({
      guild_id: GUILD_A,
      category_id: catAId,
      number: 10,
      status: 'open',
      opener_id: '1001',
      channel_id: '2001',
    }).returning();

    // Put a test file in storage
    const storageKey = `${GUILD_A}/${ticket.id}/attachment-uuid-1`;
    const storage = createStorage({
      STORAGE_DIR: tempDir,
      TICKETS_DATA_KEY: testKey,
    });

    const fileContent = Buffer.from('<html><body>Exploit?</body></html>', 'utf8');
    await storage.put(storageKey, fileContent, 'text/html');

    // Insert attachment row with content_type 'text/html'
    const [att] = await testDb.insert(attachments).values({
      id: '33333333-3333-3333-3333-333333333333',
      guild_id: GUILD_A,
      ticket_id: ticket.id,
      filename: 'payload.html',
      content_type: 'text/html',
      size: fileContent.length,
      sha256: createHash('sha256').update(fileContent).digest('hex'),
      stored: true,
      storage_key: storageKey,
    }).returning();

    // Fetch attachment via GET /api/v1/guilds/:guildId/attachments/:attachmentId
    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${GUILD_A}/attachments/${att.id}`,
      cookies: { nt_session: SESSION_TOKEN },
    });

    expect(res.statusCode).toBe(200);

    // Assert Content-Type is NEVER text/html, but application/octet-stream
    const contentType = res.headers['content-type'];
    expect(contentType).not.toContain('text/html');
    expect(contentType).toBe('application/octet-stream');

    // Assert headers
    expect(res.headers['content-disposition']).toContain('attachment');
    expect(res.headers['x-content-type-options']).toBe('nosniff');

    // Assert content is returned
    expect(res.rawPayload.equals(fileContent)).toBe(true);
  });

  it('transitions ticket: claim, close, reopen', async () => {
    const catAId = '11111111-1111-1111-1111-111111111111';

    const [ticket] = await testDb.insert(tickets).values({
      guild_id: GUILD_A,
      category_id: catAId,
      number: 20,
      status: 'open',
      opener_id: '1001',
      channel_id: '2001',
    }).returning();

    // 1. Claim
    const resClaim = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/tickets/${ticket.id}/claim`,
      cookies: { nt_session: SESSION_TOKEN },
      headers: { 'X-CSRF-Token': CSRF_TOKEN },
    });
    expect(resClaim.statusCode).toBe(200);
    expect(resClaim.json().status).toBe('claimed');
    expect(resClaim.json().claimerId).toBe(USER_STAFF);

    // 2. Close
    const resClose = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/tickets/${ticket.id}/close`,
      cookies: { nt_session: SESSION_TOKEN },
      headers: { 'X-CSRF-Token': CSRF_TOKEN },
      payload: { reason: 'Resolved' },
    });
    expect(resClose.statusCode).toBe(200);
    expect(resClose.json().status).toBe('closed');
    expect(resClose.json().closeReason).toBe('Resolved');

    // 3. Reopen
    const resReopen = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/tickets/${ticket.id}/reopen`,
      cookies: { nt_session: SESSION_TOKEN },
      headers: { 'X-CSRF-Token': CSRF_TOKEN },
    });
    expect(resReopen.statusCode).toBe(200);
    expect(resReopen.json().status).toBe('open');
    expect(resReopen.json().reopenedCount).toBe(1);
  });
});
