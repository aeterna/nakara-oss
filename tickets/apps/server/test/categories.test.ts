import { describe, it, expect, vi, beforeEach } from 'vitest';
import Fastify from 'fastify';
import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
import * as dbSchema from '@nakara-tickets/db';
import { sessions, guilds, categories, tickets } from '@nakara-tickets/db';
import { installSession } from '../src/session.js';
import { clearStaffCache } from '../src/staff.js';
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

  function toApiCategory(r: any) {
    return {
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
    };
  }

  return {
    ...orig,
    TicketError: orig.TicketError ?? TicketError,
    listCategories: orig.listCategories ?? (async (db: any, guildId: string) => {
      const rows = await db.select().from(orig.categories).where(orig.inGuild(orig.categories, guildId));
      return rows.map(toApiCategory);
    }),
    getCategory: orig.getCategory ?? (async (db: any, guildId: string, id: string) => {
      const [r] = await db.select().from(orig.categories).where(
        orig.and ? orig.and(orig.eq(orig.categories.guild_id, guildId), orig.eq(orig.categories.id, id))
          : orig.eq(orig.categories.id, id)
      );
      if (!r || r.guild_id !== guildId) {
        throw new (orig.TicketError ?? TicketError)('not_found', 'Category not found');
      }
      return toApiCategory(r);
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
      return toApiCategory(inserted);
    }),
    updateCategory: orig.updateCategory ?? (async (db: any, guildId: string, id: string, patch: any) => {
      const [existing] = await db.select().from(orig.categories).where(orig.eq(orig.categories.id, id));
      if (!existing || existing.guild_id !== guildId) {
        throw new (orig.TicketError ?? TicketError)('not_found', 'Category not found');
      }
      const values: any = {};
      if (patch.name !== undefined) values.name = patch.name;
      if (patch.emoji !== undefined) values.emoji = patch.emoji;
      if (patch.staffRoleIds !== undefined) values.staff_role_ids = patch.staffRoleIds;
      if (patch.mode !== undefined) values.mode = patch.mode;
      if (patch.parentChannelId !== undefined) values.parent_channel_id = patch.parentChannelId;
      if (patch.nameTemplate !== undefined) values.name_template = patch.nameTemplate;
      if (patch.welcomeMessage !== undefined) values.welcome_message = patch.welcomeMessage;
      if (patch.form !== undefined) values.form = patch.form;
      if (patch.autoCloseHours !== undefined) values.auto_close_hours = patch.autoCloseHours;
      if (patch.maxOpenPerUser !== undefined) values.max_open_per_user = patch.maxOpenPerUser;
      if (patch.gameServerId !== undefined) values.game_server_id = patch.gameServerId;

      const [updated] = await db.update(orig.categories)
        .set(values)
        .where(orig.eq(orig.categories.id, id))
        .returning();
      return toApiCategory(updated);
    }),
    deleteCategory: orig.deleteCategory ?? (async (db: any, guildId: string, id: string) => {
      const [existing] = await db.select().from(orig.categories).where(orig.eq(orig.categories.id, id));
      if (!existing || existing.guild_id !== guildId) {
        throw new (orig.TicketError ?? TicketError)('not_found', 'Category not found');
      }
      // Check if tickets reference this category
      const ticketRefs = await db.select().from(orig.tickets).where(orig.eq(orig.tickets.category_id, id));
      if (ticketRefs.length > 0) {
        throw new (orig.TicketError ?? TicketError)('limit', 'Cannot delete category with tickets');
      }
      await db.delete(orig.categories).where(orig.eq(orig.categories.id, id));
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

describe('categories acceptance tests', () => {
  const GUILD_A = '111111111111111111';
  const GUILD_B = '222222222222222222';
  const USER_STAFF = '333333333333333333';
  const SESSION_TOKEN = 'categories-test-session-token';
  const CSRF_TOKEN = 'categories-test-csrf-token';

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

  let testDb: any;
  let app: ReturnType<typeof Fastify>;

  beforeEach(async () => {
    clearStaffCache();
    testDb = await createTestDb();

    // Seed guilds
    await testDb.insert(guilds).values([
      { guild_id: GUILD_A, name: 'Guild A' },
      { guild_id: GUILD_B, name: 'Guild B' },
    ]);

    // Seed session
    const tokenHash = createHash('sha256').update(SESSION_TOKEN).digest('hex');
    await testDb.insert(sessions).values({
      user_id: USER_STAFF,
      token_hash: tokenHash,
      csrf_hash: CSRF_TOKEN,
      expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
    });

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
            roles: ['role-staff'],
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
            { id: 'role-staff', name: 'Staff', permissions: String(1n << 5n) }, // MANAGE_GUILD
          ],
        };
      }
      return { ok: false, status: 404, json: async () => ({}) };
    }));
  });

  it('GET /api/v1/guilds/:guildId/categories returns categories for guild', async () => {
    const postRes = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/categories`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
        'content-type': 'application/json',
      },
      payload: {
        name: 'Billing',
        staffRoleIds: ['role-staff'],
        mode: 'thread',
        parentChannelId: '123456789012345678',
      },
    });
    expect(postRes.statusCode).toBe(201);

    const getRes = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${GUILD_A}/categories`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
      },
    });
    expect(getRes.statusCode).toBe(200);
    const list = getRes.json();
    expect(Array.isArray(list)).toBe(true);
    expect(list.length).toBe(1);
    expect(list[0].name).toBe('Billing');
  });

  it('(a5) category of guild A not reachable via guild B → 404', async () => {
    // 1. Create a category under Guild A
    const postRes = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/categories`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
        'content-type': 'application/json',
      },
      payload: {
        name: 'Guild A Secret Category',
        staffRoleIds: ['role-staff'],
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
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
        'content-type': 'application/json',
      },
      payload: {
        name: 'Hacked Name',
        staffRoleIds: ['role-staff'],
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
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
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
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
        'content-type': 'application/json',
      },
      payload: {
        name: 'Technical',
        staffRoleIds: ['role-staff'],
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
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
        'content-type': 'application/json',
      },
      payload: {
        name: 'Technical Support',
        staffRoleIds: ['role-staff'],
        mode: 'channel',
        parentChannelId: '123456789012345678',
      },
    });
    expect(putRes.statusCode).toBe(200);
    expect(putRes.json().name).toBe('Technical Support');
    expect(putRes.json().mode).toBe('channel');

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
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
    });
    expect(delConflictRes.statusCode).toBe(409);
    expect(delConflictRes.json().code).toBe('conflict');

    // Remove referencing ticket
    await testDb.delete(tickets).where(dbSchema.eq(tickets.category_id, cat.id));

    // Delete category cleanly -> 204
    const delCleanRes = await app.inject({
      method: 'DELETE',
      url: `/api/v1/guilds/${GUILD_A}/categories/${cat.id}`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
    });
    expect(delCleanRes.statusCode).toBe(204);
  });
});
