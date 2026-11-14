import { describe, it, expect, vi, beforeAll, beforeEach, afterAll } from 'vitest';
import { openTestDb } from '@nakara-tickets/db/test-support';
import { guilds, categories, tickets, tags } from '@nakara-tickets/db';
import { handleTagCommand, handleTagAutocomplete } from '../src/handlers/tag.js';
import type { DiscordPort } from '../src/types.js';

describe('a4 /tag handler acceptance tests', () => {
  const GUILD_ID = '111111111111111111';
  const OPENER_ID = '222222222222222222';
  const STAFF_ID = '333333333333333333';
  const NON_STAFF_ID = '444444444444444444';
  const STAFF_ROLE_ID = '555555555555555555';
  const CHANNEL_ID = '666666666666666666';

  let testEnv: Awaited<ReturnType<typeof openTestDb>>;
  let testDb: any;
  let categoryId: string;
  let ticketId: string;

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
      name: 'Nakara City RP',
    });

    // 2. Seed category with staff role
    const [cat] = await testDb
      .insert(categories)
      .values({
        guild_id: GUILD_ID,
        name: 'General Support',
        mode: 'thread',
        parent_channel_id: '777777777777777777',
        staff_role_ids: [STAFF_ROLE_ID],
      })
      .returning();
    categoryId = cat.id;

    // 3. Seed ticket
    const [t1] = await testDb
      .insert(tickets)
      .values({
        guild_id: GUILD_ID,
        category_id: categoryId,
        number: 42,
        status: 'open',
        opener_id: OPENER_ID,
        channel_id: CHANNEL_ID,
      })
      .returning();
    ticketId = t1.id;

    // 4. Seed a tag
    await testDb.insert(tags).values({
      guild_id: GUILD_ID,
      name: 'welcome',
      body: 'Hello {user}! I am {staff} for ticket #{ticket} in {server}. Unknown {flag} stays.',
    });
  });

  it('a4-1: non-staff user is refused and no message is posted', async () => {
    const mockPort: Partial<DiscordPort> = {
      sendMessage: vi.fn(),
      deferReply: vi.fn().mockResolvedValue(undefined),
      editReply: vi.fn().mockResolvedValue(undefined),
      replyEphemeral: vi.fn().mockResolvedValue(undefined),
    };

    const nonStaffInteraction = {
      guildId: GUILD_ID,
      channelId: CHANNEL_ID,
      user: { id: NON_STAFF_ID },
      member: {
        user: { id: NON_STAFF_ID },
        roles: [],
        permissions: { bitfield: 0n },
      },
      memberPermissions: 0n,
      memberRoleIds: [],
      options: {
        getString: vi.fn().mockReturnValue('welcome'),
        get: vi.fn().mockReturnValue({ value: 'welcome' }),
      },
      deferred: false,
      deferReply: vi.fn().mockResolvedValue(undefined),
      editReply: vi.fn().mockResolvedValue(undefined),
      reply: vi.fn().mockResolvedValue(undefined),
    };

    await handleTagCommand(mockPort as DiscordPort, testDb, nonStaffInteraction);

    // Should NOT post the tag message into the channel
    expect(mockPort.sendMessage).not.toHaveBeenCalled();

    // Should inform the user of staff restriction
    const editReplyCalls = (mockPort.editReply as any).mock.calls;
    const directEditCalls = nonStaffInteraction.editReply.mock.calls;
    const hasRefusalMessage =
      editReplyCalls.some((call: any[]) => typeof call[1] === 'object' && call[1]?.content) ||
      directEditCalls.some((call: any[]) => typeof call[0] === 'object' && call[0]?.content);
    expect(hasRefusalMessage).toBe(true);
  });

  it('a4-2: substitutes variables, limits allowed_mentions to opener, and posts in channel', async () => {
    const mockPort: Partial<DiscordPort> = {
      sendMessage: vi.fn().mockResolvedValue({ id: 'sent-msg-id' }),
      deferReply: vi.fn().mockResolvedValue(undefined),
      editReply: vi.fn().mockResolvedValue(undefined),
    };

    const staffInteraction = {
      guildId: GUILD_ID,
      channelId: CHANNEL_ID,
      user: { id: STAFF_ID },
      member: {
        user: { id: STAFF_ID },
        roles: [STAFF_ROLE_ID],
        permissions: { bitfield: 0n },
      },
      memberPermissions: 0n,
      memberRoleIds: [STAFF_ROLE_ID],
      options: {
        getString: vi.fn().mockReturnValue('welcome'),
        get: vi.fn().mockReturnValue({ value: 'welcome' }),
      },
      deferred: true,
      deferReply: vi.fn().mockResolvedValue(undefined),
      editReply: vi.fn().mockResolvedValue(undefined),
    };

    await handleTagCommand(mockPort as DiscordPort, testDb, staffInteraction);

    expect(mockPort.sendMessage).toHaveBeenCalledTimes(1);
    const [channelId, payload] = (mockPort.sendMessage as any).mock.calls[0];
    expect(channelId).toBe(CHANNEL_ID);

    // Variable substitutions:
    // {user} -> <@OPENER_ID>
    // {staff} -> <@STAFF_ID>
    // {ticket} -> 42
    // {server} -> Nakara City RP
    // {flag} -> {flag} (unknown left as is)
    expect(payload.content).toBe(
      `Hello <@${OPENER_ID}>! I am <@${STAFF_ID}> for ticket #42 in Nakara City RP. Unknown {flag} stays.`
    );

    // Mentions limited with allowed_mentions: { users: [opener] }
    const allowedMentions = payload.allowed_mentions ?? payload.allowedMentions;
    expect(allowedMentions).toBeDefined();
    expect(allowedMentions.users).toEqual([OPENER_ID]);
  });

  it('a4-3: autocomplete filters by prefix and limits to 25 items', async () => {
    // Seed 28 tags matching prefix 'test-' and 3 tags with 'info-'
    const tagsToInsert = [];
    for (let i = 1; i <= 28; i++) {
      const numStr = String(i).padStart(2, '0');
      tagsToInsert.push({
        guild_id: GUILD_ID,
        name: `test-tag-${numStr}`,
        body: `Body ${numStr}`,
      });
    }
    tagsToInsert.push(
      { guild_id: GUILD_ID, name: 'info-one', body: 'Info 1' },
      { guild_id: GUILD_ID, name: 'info-two', body: 'Info 2' },
      { guild_id: GUILD_ID, name: 'info-three', body: 'Info 3' }
    );
    await testDb.insert(tags).values(tagsToInsert);

    // 1. Query 'test': should return 25 items max
    const respondMock1 = vi.fn().mockResolvedValue(undefined);
    const interaction1 = {
      guildId: GUILD_ID,
      options: {
        getFocused: vi.fn().mockReturnValue('test'),
      },
      respond: respondMock1,
    };

    await handleTagAutocomplete(testDb, interaction1);
    expect(respondMock1).toHaveBeenCalledTimes(1);
    const choices1 = respondMock1.mock.calls[0][0];
    expect(choices1.length).toBe(25);
    expect(choices1.every((c: any) => c.name.startsWith('test-tag-'))).toBe(true);

    // 2. Query 'info': should return exactly 3 items
    const respondMock2 = vi.fn().mockResolvedValue(undefined);
    const interaction2 = {
      guildId: GUILD_ID,
      options: {
        getFocused: vi.fn().mockReturnValue('info'),
      },
      respond: respondMock2,
    };

    await handleTagAutocomplete(testDb, interaction2);
    expect(respondMock2).toHaveBeenCalledTimes(1);
    const choices2 = respondMock2.mock.calls[0][0];
    expect(choices2.length).toBe(3);
    expect(choices2.map((c: any) => c.name)).toEqual(['info-one', 'info-three', 'info-two']);

    // 3. Query 'nomatch': should return 0 items
    const respondMock3 = vi.fn().mockResolvedValue(undefined);
    const interaction3 = {
      guildId: GUILD_ID,
      options: {
        getFocused: vi.fn().mockReturnValue('nomatch'),
      },
      respond: respondMock3,
    };

    await handleTagAutocomplete(testDb, interaction3);
    expect(respondMock3).toHaveBeenCalledTimes(1);
    const choices3 = respondMock3.mock.calls[0][0];
    expect(choices3).toEqual([]);
  });
});
