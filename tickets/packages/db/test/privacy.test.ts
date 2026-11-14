import { describe, it, expect, beforeAll, beforeEach, afterAll, vi } from 'vitest';
import { eq, and } from 'drizzle-orm';
import { openTestDb, type TestDbHandle } from '../test-support/pglite.js';
import {
  guilds,
  guildSettings,
  categories,
  tickets,
  messages,
  attachments,
  ratings,
  dataRequests,
  auditLog,
  gameServers,
  sessions,
  tags,
  blocks,
  panels,
} from '../src/schema.js';
import {
  deleteUserData,
  exportGuild,
  purgeExpired,
} from '../src/queries/privacy.js';
import { sealBytes } from '@nakara-tickets/core';

describe('privacy db queries (p1, p2, p3)', () => {
  let testEnv: TestDbHandle;
  let db: any;
  const dataKey = Buffer.alloc(32, 7);

  const GUILD_1 = '100000000000000001';
  const GUILD_2 = '100000000000000002';
  const USER_A = '200000000000000001';
  const USER_B = '200000000000000002';

  beforeAll(async () => {
    testEnv = await openTestDb();
    db = testEnv.db;
  });

  beforeEach(async () => {
    await testEnv.reset();

    // Seed guilds
    await db.insert(guilds).values([
      { guild_id: GUILD_1, name: 'Guild One' },
      { guild_id: GUILD_2, name: 'Guild Two' },
    ]);

    await db.insert(guildSettings).values([
      { guild_id: GUILD_1, retention_days: 90 },
      { guild_id: GUILD_2, retention_days: 30 },
    ]);
  });

  afterAll(async () => {
    await testEnv.close();
  });

  // Acceptance test p1:
  // p1 delete removes only that user's rows, in all guilds (web) or one guild (Discord),
  // keeps other users; tickets keep existing with 'deleted'.
  it('p1: delete removes only that user rows, in one guild or all guilds, keeps other users; tickets keep existing with deleted', async () => {
    // Setup category
    const [cat1] = await db
      .insert(categories)
      .values({
        guild_id: GUILD_1,
        name: 'Support 1',
        parent_channel_id: '300000000000000001',
      })
      .returning();

    const [cat2] = await db
      .insert(categories)
      .values({
        guild_id: GUILD_2,
        name: 'Support 2',
        parent_channel_id: '300000000000000002',
      })
      .returning();

    // Tickets in Guild 1
    const [ticketA1] = await db
      .insert(tickets)
      .values({
        guild_id: GUILD_1,
        number: 1,
        category_id: cat1.id,
        opener_id: USER_A,
        claimer_id: USER_B,
        channel_id: '400000000000000001',
        status: 'open',
      })
      .returning();

    const [ticketB1] = await db
      .insert(tickets)
      .values({
        guild_id: GUILD_1,
        number: 2,
        category_id: cat1.id,
        opener_id: USER_B,
        claimer_id: USER_A,
        channel_id: '400000000000000002',
        status: 'claimed',
      })
      .returning();

    // Tickets in Guild 2
    const [ticketA2] = await db
      .insert(tickets)
      .values({
        guild_id: GUILD_2,
        number: 1,
        category_id: cat2.id,
        opener_id: USER_A,
        claimer_id: null,
        channel_id: '400000000000000003',
        status: 'open',
      })
      .returning();

    // Messages
    const [msgA1] = await db
      .insert(messages)
      .values({
        id: 'msg-a-1',
        guild_id: GUILD_1,
        ticket_id: ticketA1.id,
        author_id: USER_A,
        author_name: 'User A',
        content_enc: sealBytes(dataKey, Buffer.from('hello from A in g1')),
      })
      .returning();

    const [msgB1] = await db
      .insert(messages)
      .values({
        id: 'msg-b-1',
        guild_id: GUILD_1,
        ticket_id: ticketA1.id,
        author_id: USER_B,
        author_name: 'User B',
        content_enc: sealBytes(dataKey, Buffer.from('hello from B in g1')),
      })
      .returning();

    const [msgA2] = await db
      .insert(messages)
      .values({
        id: 'msg-a-2',
        guild_id: GUILD_2,
        ticket_id: ticketA2.id,
        author_id: USER_A,
        author_name: 'User A',
        content_enc: sealBytes(dataKey, Buffer.from('hello from A in g2')),
      })
      .returning();

    // Attachments
    await db.insert(attachments).values([
      {
        guild_id: GUILD_1,
        ticket_id: ticketA1.id,
        message_id: msgA1.id,
        filename: 'att-a1.png',
        size: 1024,
        sha256: 'a'.repeat(64),
        stored: true,
        storage_key: 'g1/att-a1.png',
      },
      {
        guild_id: GUILD_1,
        ticket_id: ticketA1.id,
        message_id: msgB1.id,
        filename: 'att-b1.png',
        size: 2048,
        sha256: 'b'.repeat(64),
        stored: true,
        storage_key: 'g1/att-b1.png',
      },
      {
        guild_id: GUILD_2,
        ticket_id: ticketA2.id,
        message_id: msgA2.id,
        filename: 'att-a2.png',
        size: 512,
        sha256: 'c'.repeat(64),
        stored: true,
        storage_key: 'g2/att-a2.png',
      },
    ]);

    // Ratings
    await db.insert(ratings).values([
      {
        guild_id: GUILD_1,
        ticket_id: ticketA1.id,
        user_id: USER_A,
        score: 5,
        feedback: 'great',
      },
      {
        guild_id: GUILD_1,
        ticket_id: ticketB1.id,
        user_id: USER_B,
        score: 4,
        feedback: 'good',
      },
      {
        guild_id: GUILD_2,
        ticket_id: ticketA2.id,
        user_id: USER_A,
        score: 3,
        feedback: 'ok',
      },
    ]);

    // Mock storage to verify attachment object deletion
    const mockStorage = {
      delete: vi.fn(),
    };

    // 1. Delete USER_A in GUILD_1 only (Discord single guild delete)
    const countsGuild1 = await deleteUserData(db, GUILD_1, USER_A, mockStorage);
    expect(countsGuild1.messages).toBe(1);
    expect(countsGuild1.attachments).toBe(1);
    expect(countsGuild1.ratings).toBe(1);
    expect(mockStorage.delete).toHaveBeenCalledWith('g1/att-a1.png');
    expect(mockStorage.delete).not.toHaveBeenCalledWith('g1/att-b1.png');
    expect(mockStorage.delete).not.toHaveBeenCalledWith('g2/att-a2.png');

    // In GUILD_1:
    // USER_A's message msgA1 is gone; USER_B's message msgB1 remains
    const g1Messages = await db.select().from(messages).where(eq(messages.guild_id, GUILD_1));
    expect(g1Messages.map((m: any) => m.id)).toEqual(['msg-b-1']);

    // USER_A's attachment in GUILD_1 is gone; USER_B's attachment remains
    const g1Attachments = await db.select().from(attachments).where(eq(attachments.guild_id, GUILD_1));
    expect(g1Attachments.map((a: any) => a.filename)).toEqual(['att-b1.png']);

    // USER_A's rating in GUILD_1 is gone; USER_B's rating remains
    const g1Ratings = await db.select().from(ratings).where(eq(ratings.guild_id, GUILD_1));
    expect(g1Ratings.map((r: any) => r.user_id)).toEqual([USER_B]);

    // Tickets in GUILD_1 keep existing, but USER_A's opener_id/claimer_id replaced by 'deleted'
    const [updatedTicketA1] = await db.select().from(tickets).where(eq(tickets.id, ticketA1.id));
    expect(updatedTicketA1.opener_id).toBe('deleted');
    expect(updatedTicketA1.claimer_id).toBe(USER_B);

    const [updatedTicketB1] = await db.select().from(tickets).where(eq(tickets.id, ticketB1.id));
    expect(updatedTicketB1.opener_id).toBe(USER_B);
    expect(updatedTicketB1.claimer_id).toBe('deleted');

    // USER_A's rows in GUILD_2 are still intact
    const g2MessagesBefore = await db.select().from(messages).where(eq(messages.guild_id, GUILD_2));
    expect(g2MessagesBefore.length).toBe(1);

    // 2. Delete USER_A across ALL guilds (guildId = null, web delete)
    const countsAll = await deleteUserData(db, null, USER_A, mockStorage);
    expect(countsAll.messages).toBe(1); // the one in guild 2
    expect(countsAll.attachments).toBe(1);
    expect(countsAll.ratings).toBe(1);
    expect(mockStorage.delete).toHaveBeenCalledWith('g2/att-a2.png');

    // In GUILD_2: USER_A's rows are now gone
    const g2MessagesAfter = await db.select().from(messages).where(eq(messages.guild_id, GUILD_2));
    expect(g2MessagesAfter.length).toBe(0);

    const [updatedTicketA2] = await db.select().from(tickets).where(eq(tickets.id, ticketA2.id));
    expect(updatedTicketA2.opener_id).toBe('deleted');

    // USER_B's data is still completely intact in GUILD_1
    const finalG1Messages = await db.select().from(messages).where(eq(messages.guild_id, GUILD_1));
    expect(finalG1Messages.length).toBe(1);
    expect(finalG1Messages[0].author_id).toBe(USER_B);

    // Verify data_requests row written
    const reqs = await db.select().from(dataRequests);
    expect(reqs.length).toBeGreaterThanOrEqual(1);
    expect(reqs.some((r: any) => r.kind === 'delete' && r.status === 'done')).toBe(true);

    // Verify audit_log row written without user id in message/detail
    const audits = await db.select().from(auditLog);
    expect(audits.length).toBeGreaterThanOrEqual(1);
    for (const audit of audits) {
      const detailStr = JSON.stringify(audit.detail ?? {});
      expect(detailStr).not.toContain(USER_A);
      if (audit.target) {
        expect(audit.target).not.toContain(USER_A);
      }
    }
  });

  // Acceptance test p2:
  // p2 export has no secret_enc, no session/csrf, messages decrypted.
  it('p2: export has no secret_enc, no session/csrf, messages decrypted', async () => {
    // Seed category, panel, tag, block, rating, game_server, session
    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: GUILD_1,
        name: 'Technical',
        parent_channel_id: '300000000000000001',
      })
      .returning();

    await db.insert(panels).values({
      guild_id: GUILD_1,
      channel_id: '300000000000000001',
      embed: { title: 'Support' },
      kind: 'buttons',
      buttons: [{ categoryId: cat.id, label: 'Get Help' }],
    });

    await db.insert(tags).values({
      guild_id: GUILD_1,
      name: 'rules',
      body: 'Please read the server rules.',
    });

    await db.insert(blocks).values({
      guild_id: GUILD_1,
      user_id: USER_B,
      reason: 'spam',
      created_by: USER_A,
    });

    // Game server with secret_enc
    await db.insert(gameServers).values({
      guild_id: GUILD_1,
      name: 'Roleplay Server 1',
      secret_enc: Buffer.from('super-secret-key-bytes'),
    });

    // Session row with csrf_hash
    await db.insert(sessions).values({
      user_id: USER_A,
      token_hash: 'secret-token-hash-12345',
      csrf_hash: 'secret-csrf-hash-67890',
      expires_at: new Date(Date.now() + 86400000),
    });

    // Ticket and encrypted message
    const [tkt] = await db
      .insert(tickets)
      .values({
        guild_id: GUILD_1,
        number: 42,
        category_id: cat.id,
        opener_id: USER_A,
        channel_id: '400000000000000001',
        status: 'open',
      })
      .returning();

    await db.insert(messages).values({
      id: 'msg-exp-1',
      guild_id: GUILD_1,
      ticket_id: tkt.id,
      author_id: USER_A,
      author_name: 'User A',
      content_enc: sealBytes(dataKey, Buffer.from('Top secret decrypted message body')),
    });

    await db.insert(ratings).values({
      guild_id: GUILD_1,
      ticket_id: tkt.id,
      user_id: USER_A,
      score: 5,
      feedback: 'Excellent assistance',
    });

    // Run exportGuild
    const exportResult = await exportGuild(db, dataKey, GUILD_1);
    const exportJson = JSON.stringify(exportResult);

    // Assertions for p2:
    // 1. No secret_enc anywhere
    expect(exportJson).not.toContain('secret_enc');
    expect(exportJson).not.toContain('super-secret-key-bytes');

    // 2. No session or csrf hashes anywhere
    expect(exportJson).not.toContain('token_hash');
    expect(exportJson).not.toContain('csrf_hash');
    expect(exportJson).not.toContain('secret-token-hash');
    expect(exportJson).not.toContain('secret-csrf-hash');
    expect((exportResult as any).sessions).toBeUndefined();

    // 3. Messages decrypted
    expect(exportResult.tickets).toBeDefined();
    expect(exportResult.tickets.length).toBe(1);
    const exportedTicket = exportResult.tickets[0];
    expect(exportedTicket.messages).toBeDefined();
    expect(exportedTicket.messages.length).toBe(1);
    expect(exportedTicket.messages[0].content).toBe('Top secret decrypted message body');
    expect(exportedTicket.messages[0].content_enc).toBeUndefined();

    // 4. Other collections included
    expect(exportResult.guild.name).toBe('Guild One');
    expect(exportResult.settings.retention_days).toBe(90);
    expect(exportResult.categories.length).toBe(1);
    expect(exportResult.panels.length).toBe(1);
    expect(exportResult.tags.length).toBe(1);
    expect(exportResult.blocks.length).toBe(1);
    expect(exportResult.ratings.length).toBe(1);
  });

  // Acceptance test p3:
  // p3 purgeExpired removes a ticket closed 91 days ago with retention 90 and keeps one closed 89 days ago and an open one.
  it('p3: purgeExpired removes a ticket closed 91 days ago with retention 90 and keeps one closed 89 days ago and an open one', async () => {
    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: GUILD_1,
        name: 'Support',
        parent_channel_id: '300000000000000001',
      })
      .returning();

    const now = new Date('2026-11-14T12:00:00Z');
    const msInDay = 24 * 60 * 60 * 1000;

    const closed91DaysAgo = new Date(now.getTime() - 91 * msInDay);
    const closed89DaysAgo = new Date(now.getTime() - 89 * msInDay);

    // Ticket 1: closed 91 days ago (should be purged)
    const [ticket91] = await db
      .insert(tickets)
      .values({
        guild_id: GUILD_1,
        number: 101,
        category_id: cat.id,
        opener_id: USER_A,
        channel_id: '400000000000000001',
        status: 'closed',
        closed_at: closed91DaysAgo,
      })
      .returning();

    await db.insert(messages).values({
      id: 'msg-91',
      guild_id: GUILD_1,
      ticket_id: ticket91.id,
      author_id: USER_A,
      author_name: 'User A',
      content_enc: sealBytes(dataKey, Buffer.from('old message')),
    });

    await db.insert(attachments).values({
      guild_id: GUILD_1,
      ticket_id: ticket91.id,
      filename: 'old.png',
      size: 100,
      sha256: '9'.repeat(64),
      stored: true,
      storage_key: 'g1/old.png',
    });

    // Ticket 2: closed 89 days ago (should be kept)
    const [ticket89] = await db
      .insert(tickets)
      .values({
        guild_id: GUILD_1,
        number: 102,
        category_id: cat.id,
        opener_id: USER_A,
        channel_id: '400000000000000002',
        status: 'closed',
        closed_at: closed89DaysAgo,
      })
      .returning();

    await db.insert(messages).values({
      id: 'msg-89',
      guild_id: GUILD_1,
      ticket_id: ticket89.id,
      author_id: USER_A,
      author_name: 'User A',
      content_enc: sealBytes(dataKey, Buffer.from('recent message')),
    });

    // Ticket 3: open ticket (should be kept)
    const [ticketOpen] = await db
      .insert(tickets)
      .values({
        guild_id: GUILD_1,
        number: 103,
        category_id: cat.id,
        opener_id: USER_A,
        channel_id: '400000000000000003',
        status: 'open',
        closed_at: null,
      })
      .returning();

    await db.insert(messages).values({
      id: 'msg-open',
      guild_id: GUILD_1,
      ticket_id: ticketOpen.id,
      author_id: USER_A,
      author_name: 'User A',
      content_enc: sealBytes(dataKey, Buffer.from('open ticket message')),
    });

    const mockStorage = {
      delete: vi.fn(),
    };

    // Run purgeExpired
    const counts = await purgeExpired(db, now, mockStorage);
    expect(counts.tickets).toBe(1);
    expect(counts.messages).toBe(1);
    expect(counts.attachments).toBe(1);
    expect(mockStorage.delete).toHaveBeenCalledWith('g1/old.png');

    // Ticket 91 days ago is purged
    const remainingTickets = await db.select().from(tickets);
    const ticketIds = remainingTickets.map((t: any) => t.id);
    expect(ticketIds).not.toContain(ticket91.id);
    expect(ticketIds).toContain(ticket89.id);
    expect(ticketIds).toContain(ticketOpen.id);

    // Messages of ticket 91 are purged; ticket 89 and open messages remain
    const remainingMessages = await db.select().from(messages);
    const msgIds = remainingMessages.map((m: any) => m.id);
    expect(msgIds).not.toContain('msg-91');
    expect(msgIds).toContain('msg-89');
    expect(msgIds).toContain('msg-open');
  });
});
