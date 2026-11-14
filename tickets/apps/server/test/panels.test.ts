import { describe, it, expect, vi, beforeAll, beforeEach, afterAll } from 'vitest';
import Fastify from 'fastify';
import { eq, inArray } from 'drizzle-orm';
import { createHash } from 'node:crypto';
import { sessions, guilds, categories, panels } from '@nakara-tickets/db';
import { openTestDb } from '@nakara-tickets/db/test-support';
import { installSession } from '../src/session.js';
import { clearStaffCache } from '../src/staff.js';
import routes from '../src/routes/index.js';
import type { TicketsConfig } from '../src/config.js';
import { buildPanelMessage } from '../src/panel-message.js';

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

describe('panels acceptance tests', () => {
  const GUILD_A = '111111111111111111';
  const GUILD_B = '222222222222222222';
  const USER_STAFF = '333333333333333333';
  const ROLE_STAFF = '444444444444444444';
  const CHANNEL_ID = '555555555555555555';
  const SESSION_TOKEN = 'panels-test-session-token';
  const CSRF_TOKEN = 'panels-test-csrf-token';

  let catA1Id: string;
  let catA2Id: string;
  let catB1Id: string;

  const mockConfig: TicketsConfig = {
    ROLE: 'all',
    PORT: 8080,
    DATABASE_URL: 'postgres://localhost:5432/mock',
    TICKETS_DATA_KEY: Buffer.alloc(32, 4),
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

  // Discord mock spies
  const mockSendMessage = vi.fn();
  const mockEditMessage = vi.fn();
  const mockDeleteMessage = vi.fn();

  beforeAll(async () => {
    testEnv = await openTestDb();
    testDb = testEnv.db;
  });

  beforeEach(async () => {
    await testEnv.reset();
    clearStaffCache();
    vi.clearAllMocks();

    // Default mock behavior
    mockSendMessage.mockResolvedValue({ id: 'discord-msg-new-123' });
    mockEditMessage.mockResolvedValue({ id: 'discord-msg-edited-123' });
    mockDeleteMessage.mockResolvedValue(undefined);

    // Seed guilds
    await testDb.insert(guilds).values([
      { guild_id: GUILD_A, name: 'Guild A' },
      { guild_id: GUILD_B, name: 'Guild B' },
    ]);

    // Seed categories in Guild A and Guild B
    const [c1] = await testDb.insert(categories).values({
      guild_id: GUILD_A,
      name: 'Support A1',
      parent_channel_id: CHANNEL_ID,
    }).returning();
    catA1Id = c1.id;

    const [c2] = await testDb.insert(categories).values({
      guild_id: GUILD_A,
      name: 'Billing A2',
      parent_channel_id: CHANNEL_ID,
    }).returning();
    catA2Id = c2.id;

    const [cb] = await testDb.insert(categories).values({
      guild_id: GUILD_B,
      name: 'Guild B Category',
      parent_channel_id: CHANNEL_ID,
    }).returning();
    catB1Id = cb.id;

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
    app.decorate('discord', {
      sendMessage: mockSendMessage,
      editMessage: mockEditMessage,
      deleteMessage: mockDeleteMessage,
      createDM: vi.fn(),
    });
    await installSession(app, { config: mockConfig, db: testDb });
    await app.register(routes);
    await app.ready();

    // Stub global fetch for Discord API calls (staff check)
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

  // Acceptance test n1
  it('n1 buildPanelMessage: 7 buttons -> rows of 5 + 2, custom ids nt:open:<id>, embed fields mapped', () => {
    const buttons = [
      { categoryId: '11111111-1111-1111-1111-111111111111', label: 'Btn 1', style: 'primary' as const },
      { categoryId: '22222222-2222-2222-2222-222222222222', label: 'Btn 2', style: 'secondary' as const },
      { categoryId: '33333333-3333-3333-3333-333333333333', label: 'Btn 3', style: 'success' as const },
      { categoryId: '44444444-4444-4444-4444-444444444444', label: 'Btn 4', style: 'danger' as const },
      { categoryId: '55555555-5555-5555-5555-555555555555', label: 'Btn 5', emoji: '🎫' },
      { categoryId: '66666666-6666-6666-6666-666666666666', label: 'Btn 6' },
      { categoryId: '77777777-7777-7777-7777-777777777777', label: 'Btn 7' },
    ];

    const panel = {
      channelId: CHANNEL_ID,
      embed: {
        title: 'Support Desk',
        description: 'Need help? Click below.',
        color: 0x5865f2,
        footer: 'Nakara Tickets',
        imageUrl: 'https://example.com/image.png',
      },
      kind: 'buttons',
      buttons,
    };

    const msg = buildPanelMessage(panel);

    // Embed fields mapped
    expect(msg.embeds).toBeDefined();
    expect(msg.embeds.length).toBe(1);
    expect(msg.embeds[0].title).toBe('Support Desk');
    expect(msg.embeds[0].description).toBe('Need help? Click below.');
    expect(msg.embeds[0].color).toBe(0x5865f2);
    expect(msg.embeds[0].footer?.text).toBe('Nakara Tickets');
    expect(msg.embeds[0].image?.url).toBe('https://example.com/image.png');

    // Components: 7 buttons -> rows of 5 + 2
    expect(msg.components).toBeDefined();
    expect(msg.components.length).toBe(2);
    expect(msg.components[0].type).toBe(1); // ActionRow
    expect(msg.components[0].components.length).toBe(5);
    expect(msg.components[1].type).toBe(1); // ActionRow
    expect(msg.components[1].components.length).toBe(2);

    // Custom IDs format: nt:open:<id>
    expect(msg.components[0].components[0].custom_id).toBe('nt:open:11111111-1111-1111-1111-111111111111');
    expect(msg.components[0].components[0].type).toBe(2); // Button
    expect(msg.components[0].components[0].label).toBe('Btn 1');
    expect(msg.components[0].components[0].style).toBe(1); // Primary

    expect(msg.components[0].components[1].style).toBe(2); // Secondary
    expect(msg.components[0].components[2].style).toBe(3); // Success
    expect(msg.components[0].components[3].style).toBe(4); // Danger

    expect(msg.components[0].components[4].emoji).toEqual({ name: '🎫' });
    expect(msg.components[1].components[0].custom_id).toBe('nt:open:66666666-6666-6666-6666-666666666666');
    expect(msg.components[1].components[1].custom_id).toBe('nt:open:77777777-7777-7777-7777-777777777777');
  });

  // Acceptance test n2
  it('n2 create with a category of another guild -> 422; title 257 chars -> 400', async () => {
    // 1. Create with category of another guild -> 422
    const crossGuildRes = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/panels`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
        'content-type': 'application/json',
      },
      payload: {
        channelId: CHANNEL_ID,
        embed: {
          title: 'Panel Title',
        },
        kind: 'buttons',
        buttons: [
          { categoryId: catB1Id, label: 'Cross Guild Category' },
        ],
      },
    });
    expect(crossGuildRes.statusCode).toBe(422);
    expect(crossGuildRes.json().code).toBe('invalid_category');

    // 2. Title 257 chars -> 400
    const longTitle = 'A'.repeat(257);
    const longTitleRes = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/panels`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
        'content-type': 'application/json',
      },
      payload: {
        channelId: CHANNEL_ID,
        embed: {
          title: longTitle,
        },
        kind: 'buttons',
        buttons: [
          { categoryId: catA1Id, label: 'Support' },
        ],
      },
    });
    expect(longTitleRes.statusCode).toBe(400);
    expect(longTitleRes.json().code).toBe('invalid');

    // 3. Positive control: valid title <= 256 and valid guild category -> 201
    const validRes = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/panels`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
        'content-type': 'application/json',
      },
      payload: {
        channelId: CHANNEL_ID,
        embed: {
          title: 'Valid Panel',
          description: 'Valid Description',
        },
        kind: 'buttons',
        buttons: [
          { categoryId: catA1Id, label: 'Support' },
        ],
      },
    });
    expect(validRes.statusCode).toBe(201);
    expect(validRes.json().id).toBeDefined();
    expect(validRes.json().channelId).toBe(CHANNEL_ID);
  });

  // Acceptance test n3
  it('n3 send without message_id calls sendMessage and stores the id; with one calls editMessage; edit 404 falls back to send', async () => {
    // 1. Create a panel without message_id
    const createRes = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/panels`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
        'content-type': 'application/json',
      },
      payload: {
        channelId: CHANNEL_ID,
        embed: {
          title: 'Send Test Panel',
        },
        kind: 'buttons',
        buttons: [
          { categoryId: catA1Id, label: 'Open Ticket' },
        ],
      },
    });
    expect(createRes.statusCode).toBe(201);
    const panel = createRes.json();
    expect(panel.messageId).toBeNull();

    // 2. Send without message_id -> calls sendMessage and stores the returned id
    mockSendMessage.mockResolvedValueOnce({ id: 'msg-initial-111' });
    const sendRes1 = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/panels/${panel.id}/send`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
    });
    expect(sendRes1.statusCode).toBe(200);
    expect(mockSendMessage).toHaveBeenCalledTimes(1);
    expect(mockSendMessage).toHaveBeenCalledWith(CHANNEL_ID, expect.objectContaining({
      embeds: expect.any(Array),
      components: expect.any(Array),
    }));
    expect(mockEditMessage).not.toHaveBeenCalled();
    expect(sendRes1.json().messageId).toBe('msg-initial-111');

    // Verify stored in DB
    const [row1] = await testDb.select().from(panels).where(eq(panels.id, panel.id));
    expect(row1.message_id).toBe('msg-initial-111');

    // 3. Send with message_id -> calls editMessage
    mockEditMessage.mockResolvedValueOnce({ id: 'msg-initial-111' });
    const sendRes2 = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/panels/${panel.id}/send`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
    });
    expect(sendRes2.statusCode).toBe(200);
    expect(mockEditMessage).toHaveBeenCalledTimes(1);
    expect(mockEditMessage).toHaveBeenCalledWith(CHANNEL_ID, 'msg-initial-111', expect.any(Object));

    // 4. Edit 404 falls back to sendMessage and stores new id
    const notFoundError = new Error('Unknown Message');
    (notFoundError as any).status = 404;
    (notFoundError as any).code = '10008';
    mockEditMessage.mockRejectedValueOnce(notFoundError);
    mockSendMessage.mockResolvedValueOnce({ id: 'msg-fallback-222' });

    const sendRes3 = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/panels/${panel.id}/send`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
    });
    expect(sendRes3.statusCode).toBe(200);
    expect(mockEditMessage).toHaveBeenCalledTimes(2);
    expect(mockSendMessage).toHaveBeenCalledTimes(2);
    expect(sendRes3.json().messageId).toBe('msg-fallback-222');

    // Verify updated message_id stored in DB
    const [row2] = await testDb.select().from(panels).where(eq(panels.id, panel.id));
    expect(row2.message_id).toBe('msg-fallback-222');
  });

  // Acceptance test n4
  it('n4 delete ignores Discord 404', async () => {
    // 1. Create a panel with a message_id in DB
    const [inserted] = await testDb.insert(panels).values({
      guild_id: GUILD_A,
      channel_id: CHANNEL_ID,
      message_id: 'msg-to-delete-404',
      embed: { title: 'To Delete' },
      kind: 'buttons',
      buttons: [{ categoryId: catA1Id, label: 'Ticket' }],
    }).returning();

    // Mock deleteMessage to throw 404
    const notFoundError = new Error('Unknown Message');
    (notFoundError as any).status = 404;
    (notFoundError as any).code = '10008';
    mockDeleteMessage.mockRejectedValueOnce(notFoundError);

    // 2. Call DELETE endpoint
    const delRes = await app.inject({
      method: 'DELETE',
      url: `/api/v1/guilds/${GUILD_A}/panels/${inserted.id}`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
    });

    expect(delRes.statusCode).toBe(204);
    expect(mockDeleteMessage).toHaveBeenCalledWith(CHANNEL_ID, 'msg-to-delete-404');

    // 3. Verify row was deleted from database
    const rows = await testDb.select().from(panels).where(eq(panels.id, inserted.id));
    expect(rows.length).toBe(0);
  });

  it('GET and PUT /api/v1/guilds/:guildId/panels are guild-isolated', async () => {
    // Create panel in Guild A
    const postRes = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${GUILD_A}/panels`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
        'content-type': 'application/json',
      },
      payload: {
        channelId: CHANNEL_ID,
        embed: { title: 'Guild A Panel' },
        kind: 'buttons',
        buttons: [{ categoryId: catA1Id, label: 'Btn' }],
      },
    });
    expect(postRes.statusCode).toBe(201);
    const panelA = postRes.json();

    // Guild A list contains panel
    const listRes = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${GUILD_A}/panels`,
      headers: { cookie: `nt_session=${SESSION_TOKEN}` },
    });
    expect(listRes.statusCode).toBe(200);
    expect(listRes.json().length).toBe(1);
    expect(listRes.json()[0].id).toBe(panelA.id);

    // Guild B route cannot update Guild A panel -> 404
    const putRes = await app.inject({
      method: 'PUT',
      url: `/api/v1/guilds/${GUILD_B}/panels/${panelA.id}`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
        'content-type': 'application/json',
      },
      payload: {
        channelId: CHANNEL_ID,
        embed: { title: 'Hacked Panel' },
        kind: 'buttons',
        buttons: [{ categoryId: catB1Id, label: 'Btn' }],
      },
    });
    expect(putRes.statusCode).toBe(404);

    // Guild B route cannot delete Guild A panel -> 404
    const delRes = await app.inject({
      method: 'DELETE',
      url: `/api/v1/guilds/${GUILD_B}/panels/${panelA.id}`,
      headers: {
        cookie: `nt_session=${SESSION_TOKEN}`,
        'x-csrf-token': CSRF_TOKEN,
      },
    });
    expect(delRes.statusCode).toBe(404);
  });
});
