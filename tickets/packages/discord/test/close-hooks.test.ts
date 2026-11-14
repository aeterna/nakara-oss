import { describe, it, expect, vi, beforeAll, beforeEach, afterAll } from 'vitest';
import { eq } from 'drizzle-orm';
import { openTestDb } from '@nakara-tickets/db/test-support';
import { guilds, guildSettings, categories, tickets } from '@nakara-tickets/db';
import { runCloseHooks, type CloseHook } from '../src/handlers/close-hooks.js';
import type { CloseHookContext, DiscordPort } from '../src/types.js';
import { handleClose } from '../src/handlers/ticket-actions.js';
import { startGateway } from '../src/gateway.js';

describe('close hooks (x1)', () => {
  it('calls both hooks once and handles a rejecting hook without stopping the other', async () => {
    const errorLog: any[] = [];
    const mockCtx: CloseHookContext = {
      port: {} as DiscordPort,
      db: {} as any,
      dataKey: Buffer.alloc(32),
      ticket: { id: 'ticket-1', guild_id: 'guild-1', channel_id: 'chan-1' },
      category: { id: 'cat-1' },
      guildSettings: { locale: 'en' },
      actorId: 'user-1',
      log: {
        info: vi.fn(),
        warn: vi.fn(),
        error: vi.fn((...args) => errorLog.push(args)),
      },
    };

    let hook1Called = 0;
    let hook2Called = 0;

    const hook1: CloseHook = async (ctx) => {
      hook1Called++;
      throw new Error('archive failed');
    };

    const hook2: CloseHook = async (ctx) => {
      hook2Called++;
    };

    const results = await runCloseHooks(mockCtx, [hook1, hook2]);

    expect(hook1Called).toBe(1);
    expect(hook2Called).toBe(1);
    expect(results).toHaveLength(2);
    expect(results[0].status).toBe('rejected');
    expect(results[1].status).toBe('fulfilled');
    expect(mockCtx.log.error).toHaveBeenCalled();
  });

  it('handleClose calls close hooks without blocking reply, rejecting hook does not stop reply', async () => {
    const mockPort: DiscordPort = {
      createPrivateThread: vi.fn(),
      addMember: vi.fn(),
      sendMessage: vi.fn().mockResolvedValue({ id: 'msg-1' }),
      editMessage: vi.fn(),
      showModal: vi.fn(),
      replyEphemeral: vi.fn(),
      deferReply: vi.fn().mockResolvedValue(undefined),
      editReply: vi.fn().mockResolvedValue(undefined),
      lockAndArchiveThread: vi.fn().mockResolvedValue(undefined),
    };

    const mockDb: any = {
      select: vi.fn().mockReturnValue({
        from: vi.fn().mockReturnValue({
          where: vi.fn().mockReturnValue({
            limit: vi.fn().mockResolvedValue([
              { id: 'ticket-1', guild_id: 'guild-1', channel_id: 'chan-1', category_id: 'cat-1', status: 'open' },
            ]),
          }),
        }),
      }),
      transaction: vi.fn().mockImplementation(async (cb) => {
        return cb({
          select: vi.fn().mockReturnValue({
            from: vi.fn().mockReturnValue({
              where: vi.fn().mockReturnValue({
                for: vi.fn().mockReturnValue({
                  limit: vi.fn().mockResolvedValue([
                    { id: 'ticket-1', guild_id: 'guild-1', channel_id: 'chan-1', category_id: 'cat-1', status: 'open', reopened_count: 0 },
                  ]),
                }),
              }),
            }),
          }),
          update: vi.fn().mockReturnValue({
            set: vi.fn().mockReturnValue({
              where: vi.fn().mockReturnValue({
                returning: vi.fn().mockResolvedValue([
                  { id: 'ticket-1', status: 'closed' },
                ]),
              }),
            }),
          }),
          insert: vi.fn().mockReturnValue({
            values: vi.fn().mockResolvedValue({}),
          }),
        });
      }),
    };

    const mockInteraction: any = {
      guildId: 'guild-1',
      channelId: 'chan-1',
      user: { id: 'user-1' },
      memberPermissions: 8n, // Administrator / staff
    };

    const mockDeps = {
      dataKey: Buffer.alloc(32),
      log: {
        info: vi.fn(),
        warn: vi.fn(),
        error: vi.fn(),
      },
    };

    await expect(
      handleClose(mockPort, mockDb, mockInteraction, 'ticket-1', 'resolved', mockDeps)
    ).resolves.not.toThrow();

    expect(mockPort.deferReply).toHaveBeenCalledWith(mockInteraction, { ephemeral: true });
    expect(mockPort.editReply).toHaveBeenCalled();
  });

  it('startGateway rejects when dataKey is missing (no fallback key)', async () => {
    const depsWithoutKey: any = {
      token: 'test-token',
      appId: 'test-app',
      allowedGuildIds: ['guild-1'],
      db: {} as any,
      pool: { connect: vi.fn() },
      log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    };

    await expect(
      startGateway(depsWithoutKey)
    ).rejects.toThrow('dataKey is required');
  });
});

describe('GatewayHandle.closeHooks status gate (N2)', () => {
  const GUILD_ID = '123456789012345678';
  let testEnv: Awaited<ReturnType<typeof openTestDb>>;
  let testDb: any;

  beforeAll(async () => {
    testEnv = await openTestDb();
    testDb = testEnv.db;
  });

  afterAll(async () => {
    await testEnv.close();
  });

  beforeEach(async () => {
    await testEnv.reset();
  });

  async function seedTicket(status: 'open' | 'claimed' | 'closed', number: number) {
    await testDb.insert(guilds).values({ guild_id: GUILD_ID, name: 'Gate Guild' });
    await testDb.insert(guildSettings).values({ guild_id: GUILD_ID, locale: 'en' });
    const [cat] = await testDb.insert(categories).values({
      guild_id: GUILD_ID,
      name: 'Support',
      mode: 'thread',
      parent_channel_id: '999999999999999999',
    }).returning();
    const [ticket] = await testDb.insert(tickets).values({
      guild_id: GUILD_ID,
      category_id: cat.id,
      number,
      status,
      opener_id: '111111111111111111',
      channel_id: '555555555555555555',
    }).returning();
    return ticket;
  }

  // Minimal discord.js-like client: every channel fetch yields an empty thread
  function makeClient() {
    const channel = {
      messages: { fetch: vi.fn().mockResolvedValue(new Map()) },
      setLocked: vi.fn().mockResolvedValue(undefined),
      setArchived: vi.fn().mockResolvedValue(undefined),
    };
    return {
      client: {
        on: vi.fn(),
        login: vi.fn(),
        channels: { fetch: vi.fn().mockResolvedValue(channel) },
      },
      channel,
    };
  }

  function makeDeps(client: any) {
    return {
      token: 'test-token',
      appId: 'test-app',
      allowedGuildIds: [GUILD_ID],
      db: testDb,
      pool: { connect: vi.fn().mockRejectedValue(new Error('no lock in test')) },
      dataKey: Buffer.alloc(32, 9),
      client,
      log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    } as any;
  }

  it('N2: closeHooks does nothing for a ticket that is not closed (no hooks, no lock/archive)', async () => {
    const ticket = await seedTicket('open', 1);
    const { client, channel } = makeClient();
    const handle = await startGateway(makeDeps(client));

    try {
      await handle.closeHooks(GUILD_ID, ticket.id, 'system');
    } finally {
      await handle.stop();
    }

    const [row] = await testDb.select().from(tickets).where(eq(tickets.id, ticket.id));
    expect(row.archived_at).toBeNull();
    expect(client.channels.fetch).not.toHaveBeenCalled();
    expect(channel.setArchived).not.toHaveBeenCalled();
  });

  it('N2 control: closeHooks runs the archive hook for a closed ticket', async () => {
    const ticket = await seedTicket('closed', 2);
    const { client, channel } = makeClient();
    const handle = await startGateway(makeDeps(client));

    try {
      await handle.closeHooks(GUILD_ID, ticket.id, 'system');
    } finally {
      await handle.stop();
    }

    const [row] = await testDb.select().from(tickets).where(eq(tickets.id, ticket.id));
    expect(row.archived_at).not.toBeNull();
    expect(channel.setArchived).toHaveBeenCalledWith(true);
  });
});
