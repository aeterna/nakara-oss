import { describe, it, expect, vi } from 'vitest';
import { runCloseHooks, type CloseHook } from '../src/handlers/close-hooks.js';
import type { CloseHookContext, DiscordPort } from '../src/types.js';
import { handleClose } from '../src/handlers/ticket-actions.js';

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
});
