import { describe, it, expect, beforeAll, beforeEach, afterAll, vi } from 'vitest';
import { openTestDb, type TestDbHandle } from '@nakara-tickets/db/test-support';
import { guilds, guildSettings, categories, tickets, ratings, inGuild } from '@nakara-tickets/db';
import { eq } from 'drizzle-orm';
import { ratingOnClose, handleRatingButton, handleRatingModal } from '../src/handlers/rating.js';
import type { DiscordPort, CloseHookContext } from '../src/types.js';

describe('rating handlers (acceptance tests s3, s4)', () => {
  let testDb: TestDbHandle;

  beforeAll(async () => {
    testDb = await openTestDb();
  });

  afterAll(async () => {
    await testDb.close();
  });

  beforeEach(async () => {
    await testDb.reset();
  });

  it('s3: opener rates once (second → refused), non-opener refused, feedback stored, staff_id = claimer', async () => {
    const db = testDb.db;
    const guildId = 'guild-100';
    const openerId = 'opener-user-1';
    const claimerId = 'staff-claimer-1';
    const nonOpenerId = 'random-user-2';

    // Seed guild & category
    await db.insert(guilds).values({ guild_id: guildId, name: 'Rating Test Guild' });
    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: guildId,
        name: 'Support',
        parent_channel_id: 'chan-cat',
        mode: 'thread',
      })
      .returning();

    // Seed ticket with claimer
    const [ticket] = await db
      .insert(tickets)
      .values({
        guild_id: guildId,
        number: 101,
        category_id: cat.id,
        opener_id: openerId,
        claimer_id: claimerId,
        channel_id: 'thread-101',
        status: 'closed',
      })
      .returning();

    const mockPort: DiscordPort = {
      createPrivateThread: vi.fn(),
      addMember: vi.fn(),
      sendMessage: vi.fn(),
      editMessage: vi.fn(),
      showModal: vi.fn(),
      replyEphemeral: vi.fn(),
      deferReply: vi.fn(),
      editReply: vi.fn(),
      lockAndArchiveThread: vi.fn(),
    };

    // 1. Non-opener clicks button -> refused with ephemeral message
    const nonOpenerInteraction = {
      guildId,
      customId: `nt:rate:${ticket.id}:5`,
      user: { id: nonOpenerId },
    };

    await handleRatingButton(mockPort, db, nonOpenerInteraction);

    expect(mockPort.showModal).not.toHaveBeenCalled();
    expect(mockPort.replyEphemeral).toHaveBeenCalledTimes(1);

    vi.clearAllMocks();

    // 2. Opener clicks button -> modal is shown
    const openerInteraction = {
      guildId,
      customId: `nt:rate:${ticket.id}:5`,
      user: { id: openerId },
    };

    await handleRatingButton(mockPort, db, openerInteraction);

    expect(mockPort.showModal).toHaveBeenCalledTimes(1);
    const modalCall = (mockPort.showModal as any).mock.calls[0][1];
    expect(modalCall.customId).toBe(`nt:ratefb:${ticket.id}:5`);
    expect(modalCall.components).toBeDefined();

    vi.clearAllMocks();

    // 3. Opener submits modal -> feedback stored, staff_id = claimer
    const modalSubmitInteraction = {
      guildId,
      customId: `nt:ratefb:${ticket.id}:5`,
      user: { id: openerId },
      fields: {
        getTextInputValue: (id: string) => {
          if (id === 'feedback' || id === 'nt:feedback') return 'Wonderful help, thanks!';
          return '';
        },
      },
    };

    await handleRatingModal(mockPort, db, modalSubmitInteraction);

    expect(mockPort.replyEphemeral).toHaveBeenCalledTimes(1);

    // Verify database record
    const storedRatings = await db
      .select()
      .from(ratings)
      .where(eq(ratings.ticket_id, ticket.id));

    expect(storedRatings).toHaveLength(1);
    expect(storedRatings[0].user_id).toBe(openerId);
    expect(storedRatings[0].staff_id).toBe(claimerId);
    expect(storedRatings[0].score).toBe(5);
    expect(storedRatings[0].feedback).toBe('Wonderful help, thanks!');

    vi.clearAllMocks();

    // 4. Second rating attempt by opener -> refused
    await handleRatingButton(mockPort, db, openerInteraction);

    expect(mockPort.showModal).not.toHaveBeenCalled();
    expect(mockPort.replyEphemeral).toHaveBeenCalledTimes(1);

    // Attempt second modal submission -> refused, no second rating inserted
    await handleRatingModal(mockPort, db, modalSubmitInteraction);

    const ratingsAfter = await db
      .select()
      .from(ratings)
      .where(eq(ratings.ticket_id, ticket.id));
    expect(ratingsAfter).toHaveLength(1);
  });

  it('s4: ratingOnClose with rating_dm: DM 50007 swallowed, channel message still posted; rating_dm false → no DM', async () => {
    const db = testDb.db;
    const guildId = 'guild-dm-test';

    await db.insert(guilds).values({ guild_id: guildId, name: 'DM Test Guild' });
    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: guildId,
        name: 'General',
        parent_channel_id: 'chan-general',
        mode: 'thread',
      })
      .returning();

    const [ticket] = await db
      .insert(tickets)
      .values({
        guild_id: guildId,
        number: 201,
        category_id: cat.id,
        opener_id: 'opener-dm-user',
        claimer_id: 'staff-1',
        channel_id: 'chan-201',
        status: 'closed',
      })
      .returning();

    // Case 1: rating_dm = true, DM throws Discord 50007 (Cannot send messages to this user)
    const err50007 = new Error('Cannot send messages to this user');
    (err50007 as any).code = 50007;

    const sendDM = vi.fn().mockRejectedValue(err50007);
    const sendMessage = vi.fn().mockResolvedValue({ id: 'msg-channel' });

    const mockPort: DiscordPort & { sendDM: any } = {
      createPrivateThread: vi.fn(),
      addMember: vi.fn(),
      sendMessage,
      sendDM,
      editMessage: vi.fn(),
      showModal: vi.fn(),
      replyEphemeral: vi.fn(),
      deferReply: vi.fn(),
      editReply: vi.fn(),
      lockAndArchiveThread: vi.fn(),
    };

    const ctx: CloseHookContext = {
      port: mockPort,
      db,
      dataKey: Buffer.alloc(32),
      ticket,
      category: cat,
      guildSettings: { rating_dm: true, locale: 'en' },
      actorId: 'staff-1',
      log: {
        info: vi.fn(),
        warn: vi.fn(),
        error: vi.fn(),
      },
    };

    // ratingOnClose should NOT throw when 50007 happens
    await expect(ratingOnClose(ctx)).resolves.not.toThrow();

    // Verify channel message posted with 5 buttons
    expect(sendMessage).toHaveBeenCalledTimes(1);
    expect(sendMessage).toHaveBeenCalledWith(
      ticket.channel_id,
      expect.objectContaining({
        components: expect.arrayContaining([
          expect.objectContaining({
            components: expect.arrayContaining([
              expect.objectContaining({ customId: `nt:rate:${ticket.id}:1` }),
              expect.objectContaining({ customId: `nt:rate:${ticket.id}:5` }),
            ]),
          }),
        ]),
      })
    );

    // Verify DM was attempted
    expect(sendDM).toHaveBeenCalledTimes(1);
    expect(sendDM).toHaveBeenCalledWith(
      ticket.opener_id,
      expect.objectContaining({
        components: expect.anything(),
      })
    );

    // Verify 50007 error was swallowed silently (not logged as error)
    expect(ctx.log.error).not.toHaveBeenCalled();

    vi.clearAllMocks();

    // Case 2: rating_dm = false -> channel message posted, NO DM sent
    ctx.guildSettings.rating_dm = false;

    await ratingOnClose(ctx);

    expect(sendMessage).toHaveBeenCalledTimes(1);
    expect(sendDM).not.toHaveBeenCalled();

    vi.clearAllMocks();

    // Case 3: A rating already exists -> send nothing (no channel message, no DM)
    await db.insert(ratings).values({
      guild_id: guildId,
      ticket_id: ticket.id,
      user_id: ticket.opener_id,
      score: 5,
    });

    await ratingOnClose(ctx);
    expect(sendMessage).not.toHaveBeenCalled();
    expect(sendDM).not.toHaveBeenCalled();
  });
});
