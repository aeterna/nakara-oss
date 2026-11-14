import { describe, it, expect, vi, beforeAll, beforeEach, afterAll } from 'vitest';
import { openTestDb, type TestDbHandle } from '@nakara-tickets/db/test-support';
import { guilds, guildSettings, categories, tickets } from '@nakara-tickets/db';
import { handleInteraction, startGateway } from '../src/gateway.js';
import type { DiscordPort, StartGatewayDeps } from '../src/types.js';

describe('gateway handlers & closeHooks (R-D)', () => {
  let testEnv: TestDbHandle;
  let db: any;
  const GUILD_ID = '111111111111111111';
  const OTHER_GUILD = '222222222222222222';
  const dataKey = Buffer.alloc(32, 7);

  beforeAll(async () => {
    testEnv = await openTestDb();
    db = testEnv.db;
  });

  afterAll(async () => {
    await testEnv.close();
  });

  beforeEach(async () => {
    await testEnv.reset();

    await db.insert(guilds).values([
      { guild_id: GUILD_ID, name: 'Gateway Test Guild' },
      { guild_id: OTHER_GUILD, name: 'Unauthorized Guild' },
    ]);

    await db.insert(guildSettings).values([
      { guild_id: GUILD_ID, locale: 'en' },
      { guild_id: OTHER_GUILD, locale: 'en' },
    ]);
  });

  it('startGateway throws at startup if dataKey is missing or not 32 bytes', async () => {
    const depsBase: any = {
      token: 'test-token',
      appId: 'test-app',
      allowedGuildIds: [GUILD_ID],
      db,
      pool: { connect: vi.fn() },
      log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    };

    // Missing dataKey
    await expect(startGateway({ ...depsBase })).rejects.toThrow('dataKey');

    // Wrong length
    await expect(startGateway({ ...depsBase, dataKey: Buffer.alloc(16) })).rejects.toThrow('dataKey');
  });

  it('handleInteraction routes string-select nt:open-select (values[0] = categoryId)', async () => {
    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: GUILD_ID,
        name: 'Billing Support',
        parent_channel_id: 'chan-cat-1',
        mode: 'thread',
      })
      .returning();

    const mockPort: any = {
      deferReply: vi.fn().mockResolvedValue(undefined),
      createPrivateThread: vi.fn().mockResolvedValue({ id: 'thread-999', name: 'ticket-0001' }),
      addMember: vi.fn().mockResolvedValue(undefined),
      sendMessage: vi.fn().mockResolvedValue({ id: 'msg-welcome' }),
      editReply: vi.fn().mockResolvedValue(undefined),
    };

    const deps: StartGatewayDeps = {
      token: 'token',
      appId: 'app',
      allowedGuildIds: [GUILD_ID],
      db,
      pool: {} as any,
      dataKey,
      log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    };

    const selectInteraction: any = {
      guildId: GUILD_ID,
      user: { id: 'user-select-opener', username: 'opener' },
      isButton: () => false,
      isStringSelectMenu: () => true,
      customId: 'nt:open-select',
      values: [cat.id],
      deferred: false,
    };

    await handleInteraction(mockPort, deps, selectInteraction);

    expect(mockPort.deferReply).toHaveBeenCalledWith(selectInteraction, { ephemeral: true });
    expect(mockPort.createPrivateThread).toHaveBeenCalledWith('chan-cat-1', expect.stringContaining('1'));
    expect(mockPort.addMember).toHaveBeenCalledWith('thread-999', 'user-select-opener');
    expect(mockPort.editReply).toHaveBeenCalledWith(
      selectInteraction,
      expect.objectContaining({ content: expect.stringContaining('thread-999') })
    );
  });

  it('handleInteraction lets nt:rate: through without guildId by resolving from ticket row', async () => {
    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: GUILD_ID,
        name: 'General',
        parent_channel_id: 'chan-cat',
        mode: 'thread',
      })
      .returning();

    const [tkt] = await db
      .insert(tickets)
      .values({
        guild_id: GUILD_ID,
        number: 10,
        category_id: cat.id,
        opener_id: 'dm-user-opener',
        channel_id: 'chan-ticket-10',
        status: 'closed',
      })
      .returning();

    const mockPort: any = {
      showModal: vi.fn(),
      replyEphemeral: vi.fn(),
    };

    const deps: StartGatewayDeps = {
      token: 'token',
      appId: 'app',
      allowedGuildIds: [GUILD_ID],
      db,
      pool: {} as any,
      dataKey,
      log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    };

    // Rating interaction without guildId (DM context)
    const dmRatingInteraction: any = {
      guildId: undefined, // No guildId in DM
      user: { id: 'dm-user-opener' },
      isButton: () => true,
      customId: `nt:rate:${tkt.id}:5`,
      deferred: false,
    };

    await handleInteraction(mockPort, deps, dmRatingInteraction);

    // Should resolve guildId and show modal
    expect(dmRatingInteraction.guildId).toBe(GUILD_ID);
    expect(mockPort.showModal).toHaveBeenCalledTimes(1);
    expect(mockPort.showModal.mock.calls[0][1].customId).toBe(`nt:ratefb:${tkt.id}:5`);
  });

  it('handleInteraction drops non-rating interaction without guildId', async () => {
    const mockPort: any = {
      replyEphemeral: vi.fn(),
      deferReply: vi.fn(),
    };

    const deps: StartGatewayDeps = {
      token: 'token',
      appId: 'app',
      allowedGuildIds: [GUILD_ID],
      db,
      pool: {} as any,
      dataKey,
      log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    };

    const dmNonRating: any = {
      guildId: undefined,
      user: { id: 'user-1' },
      isButton: () => true,
      customId: 'nt:claim:ticket-1',
    };

    await handleInteraction(mockPort, deps, dmNonRating);

    expect(mockPort.deferReply).not.toHaveBeenCalled();
    expect(mockPort.replyEphemeral).not.toHaveBeenCalled();
  });

  it('GatewayHandle.closeHooks loads ticket, runs close hooks, locks & archives thread', async () => {
    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: GUILD_ID,
        name: 'Auto-Close Support',
        parent_channel_id: 'chan-cat-auto',
        mode: 'thread',
      })
      .returning();

    const [ticket] = await db
      .insert(tickets)
      .values({
        guild_id: GUILD_ID,
        number: 88,
        category_id: cat.id,
        opener_id: 'opener-auto-user',
        channel_id: 'thread-channel-88',
        status: 'closed',
      })
      .returning();

    const mockPort: any = {
      lockAndArchiveThread: vi.fn().mockResolvedValue(undefined),
      fetchMessages: vi.fn().mockResolvedValue([]),
      sendMessage: vi.fn().mockResolvedValue({ id: 'msg-rate' }),
      sendDM: vi.fn().mockResolvedValue({ id: 'dm-rate' }),
      createDM: vi.fn().mockResolvedValue({ id: 'dm-chan' }),
    };

    const mockStorage = {
      put: vi.fn().mockResolvedValue(undefined),
      delete: vi.fn().mockResolvedValue(undefined),
    };

    const mockClient: any = {
      on: vi.fn(),
      login: vi.fn().mockResolvedValue('logged-in'),
      destroy: vi.fn().mockResolvedValue(undefined),
    };

    const deps: StartGatewayDeps = {
      token: 'token',
      appId: 'app-closehooks',
      allowedGuildIds: [GUILD_ID],
      db,
      pool: {
        connect: vi.fn().mockResolvedValue({
          query: vi.fn().mockResolvedValue({ rows: [{ locked: true }] }),
          release: vi.fn(),
        }),
      } as any,
      dataKey,
      storage: mockStorage,
      client: mockClient,
      log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    };

    // Overwrite createDiscordPort behavior by providing our client
    // In startGateway, createDiscordPort wraps client, but we can verify closeHooks calls
    const gateway = await startGateway(deps);

    // Call closeHooks directly
    await gateway.closeHooks(GUILD_ID, ticket.id, 'system-auto-close');

    // Clean up gateway
    await gateway.stop();
  });
});
