import { describe, it, expect, vi, beforeAll, beforeEach, afterAll } from 'vitest';
import { eq } from 'drizzle-orm';
import { openTestDb, type TestDbHandle } from '@nakara-tickets/db/test-support';
import { guilds, guildSettings, categories, tickets, messages } from '@nakara-tickets/db';
import { handleDeleteMyData } from '../src/handlers/data.js';
import { handleInteraction } from '../src/gateway.js';
import { sealBytes } from '@nakara-tickets/core';

describe('discord data handlers', () => {
  let testEnv: TestDbHandle;
  let db: any;
  const GUILD_ID = '111111111111111111';
  const OTHER_GUILD = '222222222222222222';
  const USER_ID = '333333333333333333';
  const dataKey = Buffer.alloc(32, 3);

  beforeAll(async () => {
    testEnv = await openTestDb();
    db = testEnv.db;
  });

  beforeEach(async () => {
    await testEnv.reset();

    await db.insert(guilds).values([
      { guild_id: GUILD_ID, name: 'Discord Test Guild' },
      { guild_id: OTHER_GUILD, name: 'Other Guild' },
    ]);

    await db.insert(guildSettings).values([
      { guild_id: GUILD_ID, locale: 'en' },
      { guild_id: OTHER_GUILD, locale: 'en' },
    ]);
  });

  afterAll(async () => {
    await testEnv.close();
  });

  it('slash command shows ephemeral confirm button nt:delme:confirm', async () => {
    const mockPort: any = {
      replyEphemeral: vi.fn(),
    };

    const interaction: any = {
      guildId: GUILD_ID,
      user: { id: USER_ID },
      isButton: () => false,
      commandName: 'ticket',
      options: {
        getSubcommand: () => 'delete-my-data',
      },
    };

    await handleDeleteMyData(mockPort, db, interaction);

    expect(mockPort.replyEphemeral).toHaveBeenCalledTimes(1);
    const callArgs = mockPort.replyEphemeral.mock.calls[0][1];
    expect(callArgs.components).toBeDefined();
    const actionRow = callArgs.components[0];
    const button = actionRow.components[0];
    expect(button.customId || button.custom_id).toBe('nt:delme:confirm');
  });

  it('clicking nt:delme:confirm deletes user data in that guild only and edits reply', async () => {
    // Seed ticket and message in GUILD_ID
    const [cat1] = await db
      .insert(categories)
      .values({
        guild_id: GUILD_ID,
        name: 'General',
        parent_channel_id: '444444444444444444',
      })
      .returning();

    const [tkt1] = await db
      .insert(tickets)
      .values({
        guild_id: GUILD_ID,
        number: 1,
        category_id: cat1.id,
        opener_id: USER_ID,
        channel_id: '555555555555555555',
      })
      .returning();

    await db.insert(messages).values({
      id: 'msg-dc-1',
      guild_id: GUILD_ID,
      ticket_id: tkt1.id,
      author_id: USER_ID,
      author_name: 'User',
      content_enc: sealBytes(dataKey, Buffer.from('guild 1 message')),
    });

    // Seed ticket and message in OTHER_GUILD
    const [cat2] = await db
      .insert(categories)
      .values({
        guild_id: OTHER_GUILD,
        name: 'General 2',
        parent_channel_id: '666666666666666666',
      })
      .returning();

    const [tkt2] = await db
      .insert(tickets)
      .values({
        guild_id: OTHER_GUILD,
        number: 1,
        category_id: cat2.id,
        opener_id: USER_ID,
        channel_id: '777777777777777777',
      })
      .returning();

    await db.insert(messages).values({
      id: 'msg-dc-2',
      guild_id: OTHER_GUILD,
      ticket_id: tkt2.id,
      author_id: USER_ID,
      author_name: 'User',
      content_enc: sealBytes(dataKey, Buffer.from('guild 2 message')),
    });

    const mockPort: any = {
      deferReply: vi.fn(),
      editReply: vi.fn(),
    };

    const buttonInteraction: any = {
      guildId: GUILD_ID,
      user: { id: USER_ID },
      isButton: () => true,
      customId: 'nt:delme:confirm',
      deferred: false,
    };

    await handleDeleteMyData(mockPort, db, buttonInteraction);

    // Verify reply updated
    expect(mockPort.deferReply).toHaveBeenCalled();
    expect(mockPort.editReply).toHaveBeenCalled();

    // Verify messages in GUILD_ID deleted
    const g1Messages = await db.select().from(messages).where(eq(messages.guild_id, GUILD_ID));
    expect(g1Messages.length).toBe(0);

    // Verify messages in OTHER_GUILD retained
    const g2Messages = await db.select().from(messages).where(eq(messages.guild_id, OTHER_GUILD));
    expect(g2Messages.length).toBe(1);
  });

  it('gateway routes nt:delme:confirm button interaction to handleDeleteMyData', async () => {
    const mockPort: any = {
      deferReply: vi.fn(),
      editReply: vi.fn(),
    };

    const deps: any = {
      db,
      allowedGuildIds: [GUILD_ID],
      log: { error: vi.fn(), info: vi.fn(), warn: vi.fn() },
    };

    const interaction: any = {
      guildId: GUILD_ID,
      user: { id: USER_ID },
      isButton: () => true,
      customId: 'nt:delme:confirm',
      deferred: false,
    };

    await handleInteraction(mockPort, deps, interaction);

    expect(mockPort.deferReply).toHaveBeenCalled();
    expect(mockPort.editReply).toHaveBeenCalled();
  });
});
