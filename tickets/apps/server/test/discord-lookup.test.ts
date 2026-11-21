import { describe, it, expect, vi, beforeAll, beforeEach, afterAll } from 'vitest';
import Fastify from 'fastify';
import { guilds } from '@nakara-tickets/db';
import { openTestDb } from '@nakara-tickets/db/test-support';
import { installSession } from '../src/session.js';
import { clearStaffCache } from '../src/staff.js';
import routes from '../src/routes/index.js';
import type { TicketsConfig } from '../src/config.js';
import { createTestSession } from './helpers/session.js';
import { clearDiscordLookupCache } from '../src/routes/discord-lookup.js';

vi.mock('@nakara-tickets/core', async (importOriginal) => {
  const orig = await importOriginal<Record<string, any>>();
  const isStaff = orig.isStaff ?? (({ permissions, roleIds, staffRoleIds }: { permissions: bigint; roleIds: string[]; staffRoleIds: string[] }) => {
    const ADMINISTRATOR = 1n << 3n;
    const MANAGE_GUILD = 1n << 5n;
    if ((permissions & ADMINISTRATOR) !== 0n || (permissions & MANAGE_GUILD) !== 0n) return true;
    const staffSet = new Set(staffRoleIds);
    return roleIds.some((r) => staffSet.has(r));
  });
  return { ...orig, isStaff };
});

describe('discord-lookup routes', () => {
  const GUILD_A = '111111111111111111';
  const USER_STAFF = '333333333333333333';
  const USER_NON_STAFF = '999999999999999999';
  const ROLE_STAFF = '444444444444444444';
  let staffCookie: string;
  let nonStaffCookie: string;
  let testEnv: any;
  let app: ReturnType<typeof Fastify>;

  const mockChannels = vi.fn();
  const mockRoles = vi.fn();
  const mockMember = vi.fn();

  beforeAll(async () => {
    testEnv = await openTestDb();
  });
  afterAll(async () => {
    await testEnv.close();
  });

  beforeEach(async () => {
    await testEnv.reset();
    clearStaffCache();
    clearDiscordLookupCache();
    vi.clearAllMocks();
    await testEnv.db.insert(guilds).values({ guild_id: GUILD_A, name: 'Guild A' });

    const cfg: TicketsConfig = {
      ROLE: 'all', PORT: 8080, DATABASE_URL: 'postgres://localhost:5432/mock',
      TICKETS_DATA_KEY: Buffer.alloc(32, 5), DISCORD_TOKEN: 'mock-bot-token',
      DISCORD_APP_ID: '123456789012345678', DISCORD_CLIENT_SECRET: 'sec',
      PUBLIC_ORIGIN: 'http://localhost:8080', ALLOWED_GUILD_IDS: [GUILD_A], STORAGE_DIR: '/tmp',
    };
    ({ cookie: staffCookie } = await createTestSession(testEnv.db, cfg, { userId: USER_STAFF, username: 'staff' }));
    ({ cookie: nonStaffCookie } = await createTestSession(testEnv.db, cfg, { userId: USER_NON_STAFF, username: 'user' }));

    app = Fastify();
    app.decorate('config', cfg);
    app.decorate('db', testEnv.db);
    app.decorate('discord', { listGuildChannels: mockChannels, listGuildRoles: mockRoles, getGuildMember: mockMember });
    await installSession(app, { config: cfg, db: testEnv.db });
    await app.register(routes);
    await app.ready();

    vi.stubGlobal('fetch', vi.fn().mockImplementation(async (url: string) => {
      const u = String(url);
      if (u.includes(`/members/${USER_STAFF}`)) return { ok: true, status: 200, json: async () => ({ roles: [ROLE_STAFF], user: { id: USER_STAFF, username: 's' } }) };
      if (u.includes(`/members/${USER_NON_STAFF}`)) return { ok: true, status: 200, json: async () => ({ roles: [], user: { id: USER_NON_STAFF, username: 'u' } }) };
      if (u.includes('/roles')) return { ok: true, status: 200, json: async () => [{ id: GUILD_A, permissions: '0' }, { id: ROLE_STAFF, permissions: String(1n << 5n) }] };
      return { ok: true, status: 200, json: async () => ({}) };
    }));
  });

  it('filters channels and sorts by position', async () => {
    mockChannels.mockResolvedValue([
      { id: 'c-voice', name: 'voice', type: 2, position: 1 },
      { id: 'c-forum', name: 'forum', type: 15, position: 20, parent_id: 'c-cat' },
      { id: 'c-cat', name: 'cat', type: 4, position: 0 },
      { id: 'c-text', name: 'text', type: 0, position: 10, parent_id: 'c-cat' },
      { id: 'c-ann', name: 'ann', type: 5, position: 5 },
    ]);
    const res = await app.inject({ method: 'GET', url: `/api/v1/guilds/${GUILD_A}/discord/channels`, headers: { cookie: staffCookie } });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual([
      { id: 'c-cat', name: 'cat', type: 4, parentId: null, position: 0 },
      { id: 'c-ann', name: 'ann', type: 5, parentId: null, position: 5 },
      { id: 'c-text', name: 'text', type: 0, parentId: 'c-cat', position: 10 },
      { id: 'c-forum', name: 'forum', type: 15, parentId: 'c-cat', position: 20 },
    ]);
  });

  it('filters roles without @everyone or managed, highest position first', async () => {
    mockRoles.mockResolvedValue([
      { id: GUILD_A, name: '@everyone', color: 0, position: 0, managed: false },
      { id: 'r-bot', name: 'BotRole', color: 100, position: 15, managed: true },
      { id: 'r-mod', name: 'Mod', color: 255, position: 5, managed: false },
      { id: 'r-admin', name: 'Admin', color: 16711680, position: 25, managed: false },
    ]);
    const res = await app.inject({ method: 'GET', url: `/api/v1/guilds/${GUILD_A}/discord/roles`, headers: { cookie: staffCookie } });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual([
      { id: 'r-admin', name: 'Admin', color: 16711680, position: 25 },
      { id: 'r-mod', name: 'Mod', color: 255, position: 5 },
    ]);
  });

  it('enforces staff-only 401 and 403', async () => {
    const r1 = await app.inject({ method: 'GET', url: `/api/v1/guilds/${GUILD_A}/discord/channels` });
    expect(r1.statusCode).toBe(401);
    const r2 = await app.inject({ method: 'GET', url: `/api/v1/guilds/${GUILD_A}/discord/channels`, headers: { cookie: nonStaffCookie } });
    expect(r2.statusCode).toBe(403);
  });

  it('cache hit makes no second fetch', async () => {
    mockChannels.mockResolvedValue([{ id: 'c1', name: 't', type: 0, position: 1 }]);
    mockRoles.mockResolvedValue([{ id: 'r1', name: 'r', color: 0, position: 1, managed: false }]);
    for (let i = 0; i < 2; i++) {
      await app.inject({ method: 'GET', url: `/api/v1/guilds/${GUILD_A}/discord/channels`, headers: { cookie: staffCookie } });
      await app.inject({ method: 'GET', url: `/api/v1/guilds/${GUILD_A}/discord/roles`, headers: { cookie: staffCookie } });
    }
    expect(mockChannels).toHaveBeenCalledTimes(1);
    expect(mockRoles).toHaveBeenCalledTimes(1);
  });

  it('returns 502 discord_unavailable without token on Discord error', async () => {
    mockChannels.mockRejectedValue(new Error('Discord error with token mock-bot-token'));
    const res = await app.inject({ method: 'GET', url: `/api/v1/guilds/${GUILD_A}/discord/channels`, headers: { cookie: staffCookie } });
    expect(res.statusCode).toBe(502);
    expect(res.json().code).toBe('discord_unavailable');
    expect(res.json().message).not.toContain('mock-bot-token');
    expect(res.json().message).toContain('[REDACTED]');
  });

  describe('members', () => {
    const M1 = '100000000000000001';
    const M2 = '100000000000000002';
    const M3 = '100000000000000003';
    const members = (ids: string[], cookie = staffCookie) =>
      app.inject({
        method: 'GET',
        url: `/api/v1/guilds/${GUILD_A}/discord/members?ids=${ids.join(',')}`,
        headers: { cookie },
      });

    it('enforces staff-only 401 and 403', async () => {
      const r1 = await app.inject({ method: 'GET', url: `/api/v1/guilds/${GUILD_A}/discord/members?ids=${M1}` });
      expect(r1.statusCode).toBe(401);
      const r2 = await members([M1], nonStaffCookie);
      expect(r2.statusCode).toBe(403);
      expect(mockMember).not.toHaveBeenCalled();
    });

    it('returns 400 invalid_ids for a malformed id and for more than 50 unique ids', async () => {
      const bad = await members(['abc']);
      expect(bad.statusCode).toBe(400);
      expect(bad.json().code).toBe('invalid_ids');

      const fiftyOne = Array.from({ length: 51 }, (_, i) => `10000000000000000${String(i).padStart(2, '0')}`);
      const tooMany = await members(fiftyOne);
      expect(tooMany.statusCode).toBe(400);
      expect(tooMany.json().code).toBe('invalid_ids');
      expect(mockMember).not.toHaveBeenCalled();
    });

    it('counts duplicate ids once, so 50 unique ids plus a repeat are accepted', async () => {
      mockMember.mockImplementation(async (_g: string, id: string) => ({ user: { id, username: 'x' } }));
      const fifty = Array.from({ length: 50 }, (_, i) => `10000000000000000${String(i).padStart(2, '0')}`);
      const res = await members([...fifty, fifty[0]]);
      expect(res.statusCode).toBe(200);
      expect(res.json()).toHaveLength(50);
      expect(mockMember).toHaveBeenCalledTimes(50);
    });

    it('answers nick, then global_name, then username', async () => {
      mockMember.mockImplementation(async (_g: string, id: string) => {
        if (id === M1) return { nick: 'Nick One', user: { id: M1, username: 'u1', global_name: 'Global One' } };
        if (id === M2) return { user: { id: M2, username: 'u2', global_name: 'Global Two' } };
        return { user: { id: M3, username: 'user_three' } };
      });
      const res = await members([M1, M2, M3]);
      expect(res.statusCode).toBe(200);
      expect(res.json()).toEqual([
        { id: M1, name: 'Nick One' },
        { id: M2, name: 'Global Two' },
        { id: M3, name: 'user_three' },
      ]);
    });

    it('serves a repeated lookup from the cache without a second Discord fetch', async () => {
      mockMember.mockResolvedValue({ nick: 'Cached', user: { id: M1, username: 'c' } });
      for (let i = 0; i < 2; i++) {
        const res = await members([M1]);
        expect(res.json()).toEqual([{ id: M1, name: 'Cached' }]);
      }
      expect(mockMember).toHaveBeenCalledTimes(1);
    });

    it('leaves out a 404 member and caches the miss', async () => {
      mockMember.mockImplementation(async (_g: string, id: string) => {
        if (id === M2) throw Object.assign(new Error('Unknown Member'), { status: 404 });
        return { user: { id, username: 'one' } };
      });
      for (let i = 0; i < 2; i++) {
        const res = await members([M1, M2]);
        expect(res.json()).toEqual([{ id: M1, name: 'one' }]);
      }
      expect(mockMember.mock.calls.filter(([, id]) => id === M2)).toHaveLength(1);
    });

    it('leaves out only the failing member on another Discord error and does not cache it', async () => {
      let failing = true;
      mockMember.mockImplementation(async (_g: string, id: string) => {
        if (id === M2 && failing) throw Object.assign(new Error('boom'), { status: 500 });
        return { user: { id, username: id === M1 ? 'one' : 'two' } };
      });
      const first = await members([M1, M2]);
      expect(first.statusCode).toBe(200);
      expect(first.json()).toEqual([{ id: M1, name: 'one' }]);

      failing = false;
      const second = await members([M1, M2]);
      expect(second.json()).toEqual([
        { id: M1, name: 'one' },
        { id: M2, name: 'two' },
      ]);
    });
  });
});
