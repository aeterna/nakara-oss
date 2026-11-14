import { describe, it, expect, vi, beforeAll, beforeEach, afterAll } from 'vitest';
import { eq } from 'drizzle-orm';
import { openTestDb } from '@nakara-tickets/db/test-support';
import {
  guilds,
  guildSettings,
  categories,
  tickets,
} from '@nakara-tickets/db';
import { autoCloseJob } from '../src/jobs/auto-close.js';
import type { JobContext } from '../src/worker.js';

describe('a1 auto-close job acceptance tests', () => {
  const GUILD_ID = '100000000000000001';
  const OPENER_ID = '200000000000000001';

  let testEnv: Awaited<ReturnType<typeof openTestDb>>;
  let testDb: any;
  let catWithAutoCloseId: string;
  let catWithoutAutoCloseId: string;

  beforeAll(async () => {
    testEnv = await openTestDb();
    testDb = testEnv.db;
  });

  afterAll(async () => {
    await testEnv.close();
  });

  beforeEach(async () => {
    await testEnv.reset();

    // 1. Seed guild
    await testDb.insert(guilds).values({
      guild_id: GUILD_ID,
      name: 'Test Guild',
    });

    // 2. Seed guild settings: warn at 12 hours
    await testDb.insert(guildSettings).values({
      guild_id: GUILD_ID,
      locale: 'th',
      auto_close_warn_hours: 12,
    });

    // 3. Category with auto_close_hours = 24
    const [catA] = await testDb
      .insert(categories)
      .values({
        guild_id: GUILD_ID,
        name: 'Auto-Close Support',
        mode: 'thread',
        parent_channel_id: '300000000000000001',
        auto_close_hours: 24,
      })
      .returning();
    catWithAutoCloseId = catA.id;

    // 4. Category without auto_close_hours (null)
    const [catB] = await testDb
      .insert(categories)
      .values({
        guild_id: GUILD_ID,
        name: 'No-Auto Support',
        mode: 'thread',
        parent_channel_id: '300000000000000002',
        auto_close_hours: null,
      })
      .returning();
    catWithoutAutoCloseId = catB.id;
  });

  it('a1-1: warns once at the threshold and does not repeat warning without activity', async () => {
    const now = Date.now();
    // 13 hours inactive: >= (24 - 12) hours and < 24 hours
    const thirteenHoursAgo = new Date(now - 13 * 3600 * 1000);

    const [t1] = await testDb
      .insert(tickets)
      .values({
        guild_id: GUILD_ID,
        category_id: catWithAutoCloseId,
        number: 1,
        status: 'open',
        opener_id: OPENER_ID,
        channel_id: '400000000000000001',
        created_at: thirteenHoursAgo,
        last_activity_at: thirteenHoursAgo,
        auto_close_warned_at: null,
      })
      .returning();

    const mockDiscord = {
      sendMessage: vi.fn().mockResolvedValue({ id: 'msg-1' }),
      editMessage: vi.fn(),
      deleteMessage: vi.fn(),
      createDM: vi.fn(),
      patchChannel: vi.fn().mockResolvedValue({}),
    };

    const ctx: JobContext = {
      db: testDb,
      config: {} as any,
      discord: mockDiscord as any,
      log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    };

    // First run: should trigger warning
    await autoCloseJob.run(ctx);

    expect(mockDiscord.sendMessage).toHaveBeenCalledTimes(1);
    expect(mockDiscord.sendMessage).toHaveBeenCalledWith(
      '400000000000000001',
      expect.objectContaining({ content: expect.any(String) })
    );

    const [updated] = await testDb
      .select()
      .from(tickets)
      .where(eq(tickets.id, t1.id));
    expect(updated.auto_close_warned_at).not.toBeNull();
    expect(updated.status).toBe('open');

    // Second run: already warned, should NOT warn again (warn once at threshold)
    mockDiscord.sendMessage.mockClear();
    await autoCloseJob.run(ctx);
    expect(mockDiscord.sendMessage).not.toHaveBeenCalled();
  });

  it('a1-2: activity after warning resets auto_close_warned_at', async () => {
    const now = Date.now();
    const fifteenHoursAgo = new Date(now - 15 * 3600 * 1000);
    const fourteenHoursAgo = new Date(now - 14 * 3600 * 1000);

    // Ticket warned 14 hours ago
    const [t1] = await testDb
      .insert(tickets)
      .values({
        guild_id: GUILD_ID,
        category_id: catWithAutoCloseId,
        number: 2,
        status: 'open',
        opener_id: OPENER_ID,
        channel_id: '400000000000000002',
        created_at: fifteenHoursAgo,
        last_activity_at: fourteenHoursAgo,
        auto_close_warned_at: fourteenHoursAgo,
      })
      .returning();

    // Now newer activity occurs 1 hour ago (> warned_at)
    const oneHourAgo = new Date(now - 1 * 3600 * 1000);
    await testDb
      .update(tickets)
      .set({ last_activity_at: oneHourAgo })
      .where(eq(tickets.id, t1.id));

    const mockDiscord = {
      sendMessage: vi.fn().mockResolvedValue({ id: 'msg-1' }),
      editMessage: vi.fn(),
      deleteMessage: vi.fn(),
      createDM: vi.fn(),
      patchChannel: vi.fn().mockResolvedValue({}),
    };

    const ctx: JobContext = {
      db: testDb,
      config: {} as any,
      discord: mockDiscord as any,
      log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    };

    await autoCloseJob.run(ctx);

    const [updated] = await testDb
      .select()
      .from(tickets)
      .where(eq(tickets.id, t1.id));
    // auto_close_warned_at must be reset to null
    expect(updated.auto_close_warned_at).toBeNull();
    // 1 hour inactive is < 12 hours, so no new warning
    expect(mockDiscord.sendMessage).not.toHaveBeenCalled();
  });

  it('a1-3: closes at the limit and patches channel for threads', async () => {
    const now = Date.now();
    // 25 hours inactive: >= auto_close_hours (24)
    const twentyFiveHoursAgo = new Date(now - 25 * 3600 * 1000);

    const [t1] = await testDb
      .insert(tickets)
      .values({
        guild_id: GUILD_ID,
        category_id: catWithAutoCloseId,
        number: 3,
        status: 'open',
        opener_id: OPENER_ID,
        channel_id: '400000000000000003',
        created_at: twentyFiveHoursAgo,
        last_activity_at: twentyFiveHoursAgo,
        auto_close_warned_at: new Date(now - 13 * 3600 * 1000),
      })
      .returning();

    const mockDiscord = {
      sendMessage: vi.fn().mockResolvedValue({ id: 'msg-1' }),
      editMessage: vi.fn(),
      deleteMessage: vi.fn(),
      createDM: vi.fn(),
      patchChannel: vi.fn().mockResolvedValue({}),
    };

    const ctx: JobContext = {
      db: testDb,
      config: {} as any,
      discord: mockDiscord as any,
      log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    };

    await autoCloseJob.run(ctx);

    const [updated] = await testDb
      .select()
      .from(tickets)
      .where(eq(tickets.id, t1.id));
    expect(updated.status).toBe('closed');
    expect(updated.close_reason).toBe('auto-close');
    expect(updated.closed_at).not.toBeNull();

    // Check message sent and thread patched
    expect(mockDiscord.sendMessage).toHaveBeenCalledWith(
      '400000000000000003',
      expect.objectContaining({ content: expect.any(String) })
    );
    expect(mockDiscord.patchChannel).toHaveBeenCalledWith(
      '400000000000000003',
      { archived: true, locked: true }
    );
  });

  it('a1-4: category without auto_close_hours is untouched', async () => {
    const now = Date.now();
    const hundredHoursAgo = new Date(now - 100 * 3600 * 1000);

    const [t1] = await testDb
      .insert(tickets)
      .values({
        guild_id: GUILD_ID,
        category_id: catWithoutAutoCloseId,
        number: 4,
        status: 'open',
        opener_id: OPENER_ID,
        channel_id: '400000000000000004',
        created_at: hundredHoursAgo,
        last_activity_at: hundredHoursAgo,
        auto_close_warned_at: null,
      })
      .returning();

    const mockDiscord = {
      sendMessage: vi.fn().mockResolvedValue({ id: 'msg-1' }),
      editMessage: vi.fn(),
      deleteMessage: vi.fn(),
      createDM: vi.fn(),
      patchChannel: vi.fn().mockResolvedValue({}),
    };

    const ctx: JobContext = {
      db: testDb,
      config: {} as any,
      discord: mockDiscord as any,
      log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    };

    await autoCloseJob.run(ctx);

    const [updated] = await testDb
      .select()
      .from(tickets)
      .where(eq(tickets.id, t1.id));
    expect(updated.status).toBe('open');
    expect(updated.auto_close_warned_at).toBeNull();
    expect(mockDiscord.sendMessage).not.toHaveBeenCalled();
    expect(mockDiscord.patchChannel).not.toHaveBeenCalled();
  });

  it('a1-5: discord null still closes ticket without throwing', async () => {
    const now = Date.now();
    const twentyFiveHoursAgo = new Date(now - 25 * 3600 * 1000);

    const [t1] = await testDb
      .insert(tickets)
      .values({
        guild_id: GUILD_ID,
        category_id: catWithAutoCloseId,
        number: 5,
        status: 'open',
        opener_id: OPENER_ID,
        channel_id: '400000000000000005',
        created_at: twentyFiveHoursAgo,
        last_activity_at: twentyFiveHoursAgo,
        auto_close_warned_at: null,
      })
      .returning();

    const ctx: JobContext = {
      db: testDb,
      config: {} as any,
      discord: null,
      log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    };

    await expect(autoCloseJob.run(ctx)).resolves.not.toThrow();

    const [updated] = await testDb
      .select()
      .from(tickets)
      .where(eq(tickets.id, t1.id));
    expect(updated.status).toBe('closed');
    expect(updated.close_reason).toBe('auto-close');
  });
});
