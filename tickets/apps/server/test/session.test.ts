import { describe, it, expect, vi, beforeEach } from 'vitest';
import Fastify from 'fastify';
import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
import * as dbSchema from '@nakara-tickets/db';
import { sessions, guilds, categories } from '@nakara-tickets/db';
import { installSession } from '../src/session.js';
import { checkStaff, clearStaffCache } from '../src/staff.js';
import routes from '../src/routes/index.js';
import type { TicketsConfig } from '../src/config.js';

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

vi.mock('@nakara-tickets/db', async (importOriginal) => {
  const orig = await importOriginal<Record<string, any>>();
  class TicketError extends Error {
    readonly code: string;
    constructor(code: string, message?: string) {
      super(message ?? code);
      this.name = 'TicketError';
      this.code = code;
    }
  }

  return {
    ...orig,
    TicketError: orig.TicketError ?? TicketError,
    listCategories: orig.listCategories ?? (async (db: any, guildId: string) => {
      const rows = await db.select().from(orig.categories).where(orig.inGuild(orig.categories, guildId));
      return rows.map((r: any) => ({
        id: r.id,
        name: r.name,
        emoji: r.emoji,
        staffRoleIds: r.staff_role_ids ?? [],
        mode: r.mode,
        parentChannelId: r.parent_channel_id,
        nameTemplate: r.name_template,
        welcomeMessage: r.welcome_message,
        form: r.form,
        autoCloseHours: r.auto_close_hours,
        maxOpenPerUser: r.max_open_per_user,
        gameServerId: r.game_server_id,
        createdAt: r.created_at?.toISOString?.() ?? new Date().toISOString(),
      }));
    }),
    createCategory: orig.createCategory ?? (async (db: any, guildId: string, input: any) => {
      const [inserted] = await db.insert(orig.categories).values({
        guild_id: guildId,
        name: input.name,
        emoji: input.emoji ?? null,
        staff_role_ids: input.staffRoleIds ?? [],
        mode: input.mode ?? 'thread',
        parent_channel_id: input.parentChannelId,
        name_template: input.nameTemplate ?? 'ticket-{number}',
        welcome_message: input.welcomeMessage ?? null,
        form: input.form ?? null,
        auto_close_hours: input.autoCloseHours ?? null,
        max_open_per_user: input.maxOpenPerUser ?? 1,
        game_server_id: input.gameServerId ?? null,
      }).returning();
      return {
        id: inserted.id,
        name: inserted.name,
        emoji: inserted.emoji,
        staffRoleIds: inserted.staff_role_ids ?? [],
        mode: inserted.mode,
        parentChannelId: inserted.parent_channel_id,
        nameTemplate: inserted.name_template,
        welcomeMessage: inserted.welcome_message,
        form: inserted.form,
        autoCloseHours: inserted.auto_close_hours,
        maxOpenPerUser: inserted.maxOpenPerUser ?? inserted.max_open_per_user,
        gameServerId: inserted.game_server_id,
        createdAt: inserted.created_at?.toISOString?.() ?? new Date().toISOString(),
      };
    }),
  };
});

async function createTestDb() {
  const pglite = new PGlite();
  const migrationPath = resolve(import.meta.dirname, '../../../packages/db/migrations/0000_init.sql');
  const sql = readFileSync(migrationPath, 'utf8');
  for (const statement of sql.split('--> statement-breakpoint')) {
    const trimmed = statement.trim();
    if (trimmed) {
      await pglite.query(trimmed);
    }
  }
  return drizzle(pglite, { schema: dbSchema });
}

describe('session & staff acceptance tests', () => {
  const GUILD_ALLOWED = '111111111111111111';
  const GUILD_NOT_ALLOWED = '999999999999999999';
  const USER_STAFF = '222222222222222222';
  const USER_NON_STAFF = '333333333333333333';

  const mockConfig: TicketsConfig = {
    ROLE: 'all',
    PORT: 8080,
    DATABASE_URL: 'postgres://localhost:5432/mock',
    TICKETS_DATA_KEY: Buffer.alloc(32, 1),
    DISCORD_TOKEN: 'mock-bot-token',
    DISCORD_APP_ID: '123456789012345678',
    DISCORD_CLIENT_SECRET: 'mock-client-secret',
    PUBLIC_ORIGIN: 'http://localhost:8080',
    ALLOWED_GUILD_IDS: [GUILD_ALLOWED],
    STORAGE_DIR: '/tmp/tickets',
  };

  let testDb: any;
  let app: ReturnType<typeof Fastify>;

  beforeEach(async () => {
    clearStaffCache();
    testDb = await createTestDb();

    // Seed guild
    await testDb.insert(guilds).values({
      guild_id: GUILD_ALLOWED,
      name: 'Allowed Test Guild',
    });

    app = Fastify();
    app.decorate('config', mockConfig);
    app.decorate('db', testDb);
    await installSession(app, { config: mockConfig, db: testDb });
    await app.register(routes);
    await app.ready();

    // Stub global fetch for Discord API calls
    vi.stubGlobal('fetch', vi.fn().mockImplementation(async (url: string) => {
      const urlStr = String(url);
      if (urlStr.includes(`/guilds/${GUILD_ALLOWED}/members/${USER_STAFF}`)) {
        return {
          ok: true,
          status: 200,
          json: async () => ({
            roles: ['role-staff'],
            user: { id: USER_STAFF, username: 'staffuser', avatar: null },
          }),
        };
      }
      if (urlStr.includes(`/guilds/${GUILD_ALLOWED}/members/${USER_NON_STAFF}`)) {
        return {
          ok: true,
          status: 200,
          json: async () => ({
            roles: ['role-member'],
            user: { id: USER_NON_STAFF, username: 'regularuser', avatar: null },
          }),
        };
      }
      if (urlStr.includes(`/guilds/${GUILD_ALLOWED}/roles`)) {
        return {
          ok: true,
          status: 200,
          json: async () => [
            { id: GUILD_ALLOWED, name: '@everyone', permissions: '0' },
            { id: 'role-staff', name: 'Staff', permissions: String(1n << 5n) }, // MANAGE_GUILD
            { id: 'role-member', name: 'Member', permissions: '0' },
          ],
        };
      }
      return {
        ok: false,
        status: 404,
        json: async () => ({ message: 'Not found' }),
      };
    }));
  });

  async function createSession(userId: string, rawToken: string, csrf: string) {
    const tokenHash = createHash('sha256').update(rawToken).digest('hex');
    await testDb.insert(sessions).values({
      user_id: userId,
      token_hash: tokenHash,
      csrf_hash: csrf,
      expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
    });
  }

  it('(a1) no cookie → 401', async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${GUILD_ALLOWED}/categories`,
    });
    expect(res.statusCode).toBe(401);
    expect(res.json().code).toBe('unauthorized');

    const meRes = await app.inject({
      method: 'GET',
      url: '/api/v1/me',
    });
    expect(meRes.statusCode).toBe(401);
  });

  it('(a2) valid session, not staff → 403', async () => {
    const rawToken = 'regular-user-session-token-32b-base64url';
    const csrf = 'regular-csrf-token';
    await createSession(USER_NON_STAFF, rawToken, csrf);

    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${GUILD_ALLOWED}/categories`,
      headers: {
        cookie: `nt_session=${rawToken}`,
      },
    });
    expect(res.statusCode).toBe(403);
    expect(res.json().code).toBe('forbidden');
  });

  it('(a3) staff, guild not in allowlist → 403', async () => {
    const rawToken = 'staff-user-session-token-32b-base64url';
    const csrf = 'staff-csrf-token';
    await createSession(USER_STAFF, rawToken, csrf);

    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${GUILD_NOT_ALLOWED}/categories`,
      headers: {
        cookie: `nt_session=${rawToken}`,
      },
    });
    expect(res.statusCode).toBe(403);
    expect(res.json().code).toBe('forbidden');
  });

  it('(a4) POST without CSRF → 403, with → 201', async () => {
    const rawToken = 'staff-user-csrf-test-token-base64url';
    const csrf = 'valid-csrf-token-12345';
    await createSession(USER_STAFF, rawToken, csrf);

    const validBody = {
      name: 'Support',
      staffRoleIds: ['role-staff'],
      mode: 'thread',
      parentChannelId: '123456789012345678',
    };

    // 1. Without CSRF header -> 403 csrf
    const resNoCsrf = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_ALLOWED}/categories`,
      headers: {
        cookie: `nt_session=${rawToken}`,
        'content-type': 'application/json',
      },
      payload: validBody,
    });
    expect(resNoCsrf.statusCode).toBe(403);
    expect(resNoCsrf.json().code).toBe('csrf');

    // 2. With wrong CSRF header -> 403 csrf
    const resWrongCsrf = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_ALLOWED}/categories`,
      headers: {
        cookie: `nt_session=${rawToken}`,
        'x-csrf-token': 'wrong-csrf-token',
        'content-type': 'application/json',
      },
      payload: validBody,
    });
    expect(resWrongCsrf.statusCode).toBe(403);
    expect(resWrongCsrf.json().code).toBe('csrf');

    // 3. With matching CSRF header -> 201
    const resWithCsrf = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_ALLOWED}/categories`,
      headers: {
        cookie: `nt_session=${rawToken}`,
        'x-csrf-token': csrf,
        'content-type': 'application/json',
      },
      payload: validBody,
    });
    expect(resWithCsrf.statusCode).toBe(201);
    expect(resWithCsrf.json().name).toBe('Support');
  });

  it('(a8) checkStaff cached (second call does not fetch)', async () => {
    const fetchSpy = vi.fn().mockImplementation(async (url: string) => {
      const urlStr = String(url);
      if (urlStr.includes(`/guilds/${GUILD_ALLOWED}/members/${USER_STAFF}`)) {
        return {
          ok: true,
          status: 200,
          json: async () => ({
            roles: ['role-staff'],
            user: { id: USER_STAFF },
          }),
        };
      }
      if (urlStr.includes(`/guilds/${GUILD_ALLOWED}/roles`)) {
        return {
          ok: true,
          status: 200,
          json: async () => [
            { id: GUILD_ALLOWED, name: '@everyone', permissions: '0' },
            { id: 'role-staff', name: 'Staff', permissions: String(1n << 5n) },
          ],
        };
      }
      return { ok: false, status: 404, json: async () => ({}) };
    });

    const isStaffFirst = await checkStaff(
      { token: 'bot-token', fetchImpl: fetchSpy as any },
      GUILD_ALLOWED,
      USER_STAFF,
      ['role-staff']
    );
    expect(isStaffFirst).toBe(true);
    const callCountAfterFirst = fetchSpy.mock.calls.length;
    expect(callCountAfterFirst).toBeGreaterThan(0);

    // Second call with same guildId and userId should return cached result without fetching
    const isStaffSecond = await checkStaff(
      { token: 'bot-token', fetchImpl: fetchSpy as any },
      GUILD_ALLOWED,
      USER_STAFF,
      ['role-staff']
    );
    expect(isStaffSecond).toBe(true);
    expect(fetchSpy.mock.calls.length).toBe(callCountAfterFirst);
  });
});
