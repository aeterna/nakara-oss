import { describe, it, expect, vi, beforeAll, beforeEach, afterEach, afterAll } from 'vitest';
import Fastify from 'fastify';
import { eq } from 'drizzle-orm';
import { openTestDb, type TestDbHandle } from '@nakara-tickets/db/test-support';
import { guilds, categories } from '@nakara-tickets/db';
import { installSession } from '../src/session.js';
import routes from '../src/routes/index.js';
import { clearGuildLookupNegativeCache } from '../src/routes/me.js';
import type { TicketsConfig } from '../src/config.js';
import { createTestSession } from './helpers/session.js';

describe('GET /api/v1/me (guild name resolution)', () => {
  const GUILD_ID = '111111111111111111';
  const USER = '333333333333333333';
  const ROLE = '444444444444444444';
  const config: TicketsConfig = {
    ROLE: 'all', PORT: 8080, DATABASE_URL: 'postgres://localhost/mock',
    TICKETS_DATA_KEY: Buffer.alloc(32, 5), DISCORD_TOKEN: 'mock-bot',
    DISCORD_APP_ID: '123456789012345678', DISCORD_CLIENT_SECRET: 'mock-sec',
    PUBLIC_ORIGIN: 'http://localhost:8080', ALLOWED_GUILD_IDS: [GUILD_ID], STORAGE_DIR: '/tmp',
  };

  let env: TestDbHandle;
  let app: ReturnType<typeof Fastify>;
  let cookie: string;
  let fetchMock: any;

  beforeAll(async () => { env = await openTestDb(); });
  afterAll(async () => { await env.close(); });

  beforeEach(async () => {
    await env.reset();
    clearGuildLookupNegativeCache();
    await env.db.insert(guilds).values({ guild_id: GUILD_ID, name: `Guild ${GUILD_ID}` });
    await env.db.insert(categories).values({
      id: '11111111-1111-1111-1111-111111111111', guild_id: GUILD_ID,
      name: 'General', staff_role_ids: [ROLE], mode: 'thread', parent_channel_id: '999',
    });

    ({ cookie } = await createTestSession(env.db, config, { userId: USER, username: 'staff' }));

    app = Fastify();
    app.decorate('config', config);
    app.decorate('db', env.db);
    await installSession(app, { config, db: env.db });
    await app.register(routes);
    await app.ready();

    fetchMock = vi.fn().mockImplementation(async (url: string) => {
      const u = String(url);
      if (u === `https://discord.com/api/v10/guilds/${GUILD_ID}`) {
        return { ok: true, status: 200, json: async () => ({ id: GUILD_ID, name: 'Real Discord Name' }) };
      }
      if (u.includes('/members/')) {
        return { ok: true, status: 200, json: async () => ({ roles: [ROLE], user: { id: USER } }) };
      }
      if (u.includes('/roles')) {
        return { ok: true, status: 200, json: async () => [{ id: ROLE, permissions: '0' }] };
      }
      return { ok: false, status: 404 };
    });
    vi.stubGlobal('fetch', fetchMock);
  });

  afterEach(() => { vi.restoreAllMocks(); });

  it('placeholder row calls /guilds/{id} once and stores real name; real-name row makes no fetch at all', async () => {
    const res1 = await app.inject({ method: 'GET', url: '/api/v1/me', headers: { cookie } });
    expect(res1.statusCode).toBe(200);
    expect(res1.json().guilds[0].name).toBe('Real Discord Name');

    const [row] = await env.db.select().from(guilds).where(eq(guilds.guild_id, GUILD_ID));
    expect(row.name).toBe('Real Discord Name');

    // Two /guilds/{id} calls on cold request: 1 from checkStaff (reading owner_id) + 1 from me.ts (resolving placeholder name)
    const guildCalls = fetchMock.mock.calls.filter(([u]: [string]) =>
      String(u) === `https://discord.com/api/v10/guilds/${GUILD_ID}`
    );
    expect(guildCalls).toHaveLength(2);

    // Second call: row now has real name in DB and staff status cached -> no fetch at all
    fetchMock.mockClear();
    const res2 = await app.inject({ method: 'GET', url: '/api/v1/me', headers: { cookie } });
    expect(res2.statusCode).toBe(200);
    expect(res2.json().guilds[0].name).toBe('Real Discord Name');
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('real-name row in DB makes no /guilds/{id} Discord call', async () => {
    await env.db.update(guilds).set({ name: 'Existing Guild' }).where(eq(guilds.guild_id, GUILD_ID));
    fetchMock.mockClear();

    const res = await app.inject({ method: 'GET', url: '/api/v1/me', headers: { cookie } });
    expect(res.statusCode).toBe(200);
    expect(res.json().guilds[0].name).toBe('Existing Guild');

    const guildCalls = fetchMock.mock.calls.filter(([u]: [string]) =>
      String(u) === `https://discord.com/api/v10/guilds/${GUILD_ID}`
    );
    expect(guildCalls).toHaveLength(0);
  });

  it('failing lookup records negative cache so second request makes no /guilds/{id} call from me.ts', async () => {
    fetchMock.mockImplementation(async (url: string) => {
      const u = String(url);
      if (u === `https://discord.com/api/v10/guilds/${GUILD_ID}`) {
        return { ok: false, status: 500 };
      }
      if (u.includes('/members/')) {
        return { ok: true, status: 200, json: async () => ({ roles: [ROLE], user: { id: USER } }) };
      }
      if (u.includes('/roles')) {
        return { ok: true, status: 200, json: async () => [{ id: ROLE, permissions: '0' }] };
      }
      return { ok: false, status: 404 };
    });

    const res1 = await app.inject({ method: 'GET', url: '/api/v1/me', headers: { cookie } });
    expect(res1.statusCode).toBe(200);
    expect(res1.json().guilds[0].name).toBe(`Guild ${GUILD_ID}`);

    const guildCalls1 = fetchMock.mock.calls.filter(([u]: [string]) =>
      String(u) === `https://discord.com/api/v10/guilds/${GUILD_ID}`
    );
    expect(guildCalls1).toHaveLength(2);

    fetchMock.mockClear();
    const res2 = await app.inject({ method: 'GET', url: '/api/v1/me', headers: { cookie } });
    expect(res2.statusCode).toBe(200);
    expect(res2.json().guilds[0].name).toBe(`Guild ${GUILD_ID}`);

    const guildCalls2 = fetchMock.mock.calls.filter(([u]: [string]) =>
      String(u) === `https://discord.com/api/v10/guilds/${GUILD_ID}`
    );
    expect(guildCalls2).toHaveLength(0);
  });
});
