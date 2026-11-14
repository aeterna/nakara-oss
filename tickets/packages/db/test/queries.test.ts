import { describe, it, expect, beforeAll, beforeEach, afterAll } from 'vitest';
import { eq } from 'drizzle-orm';
import { randomBytes } from 'node:crypto';
import * as schema from '../src/schema.js';
import type { TicketsDb } from '../src/index.js';
import { openTestDb, type TestDbHandle } from '../test-support/pglite.js';
import {
  ensureGuild,
  getSettings,
  updateSettings,
  listCategories,
  getCategory,
  createCategory,
  updateCategory,
  deleteCategory,
  openTicket,
  getTicket,
  getTicketByChannel,
  listTickets,
  transitionTicket,
  appendMessage,
  readMessages,
  TicketError,
} from '../src/index.js';

describe('database queries acceptance tests (pglite)', () => {
  let testDb: TestDbHandle;
  let db: TicketsDb;

  beforeAll(async () => {
    testDb = await openTestDb();
    db = testDb.db;
  });

  beforeEach(async () => {
    await testDb.reset();
  });

  afterAll(async () => {
    await testDb.close();
  });

  it('(q1) two guilds, same category name, listCategories returns only its own', async () => {
    await ensureGuild(db, '111111111111111111', 'Guild 1');
    await ensureGuild(db, '222222222222222222', 'Guild 2');

    const cat1 = await createCategory(db, '111111111111111111', {
      name: 'Support',
      parentChannelId: '999999999999999991',
    });
    const cat2 = await createCategory(db, '222222222222222222', {
      name: 'Support',
      parentChannelId: '999999999999999992',
    });

    const list1 = await listCategories(db, '111111111111111111');
    expect(list1).toHaveLength(1);
    expect(list1[0].id).toBe(cat1.id);
    expect(list1[0].guild_id).toBe('111111111111111111');

    const list2 = await listCategories(db, '222222222222222222');
    expect(list2).toHaveLength(1);
    expect(list2[0].id).toBe(cat2.id);
    expect(list2[0].guild_id).toBe('222222222222222222');
  });

  it('(q2) getCategory with the other guild\'s id → not_found', async () => {
    await ensureGuild(db, '111111111111111111', 'Guild 1');
    await ensureGuild(db, '222222222222222222', 'Guild 2');

    const cat1 = await createCategory(db, '111111111111111111', {
      name: 'Billing',
      parentChannelId: '999999999999999991',
    });

    // Own guild query succeeds
    const found = await getCategory(db, '111111111111111111', cat1.id);
    expect(found.id).toBe(cat1.id);

    // Other guild query rejects with code: 'not_found'
    await expect(getCategory(db, '222222222222222222', cat1.id)).rejects.toMatchObject({
      code: 'not_found',
    });
  });

  it('(q3) openTicket numbers 1, 2 per guild independently', async () => {
    await ensureGuild(db, '111111111111111111', 'Guild 1');
    await ensureGuild(db, '222222222222222222', 'Guild 2');

    const cat1 = await createCategory(db, '111111111111111111', {
      name: 'General',
      parentChannelId: '100',
      maxOpenPerUser: 5,
    });
    const cat2 = await createCategory(db, '222222222222222222', {
      name: 'General',
      parentChannelId: '200',
      maxOpenPerUser: 5,
    });

    // Guild 1 tickets
    const t1_1 = await openTicket(db, {
      guildId: '111111111111111111',
      categoryId: cat1.id,
      openerId: 'user_a',
      channelId: 'chan_1',
    });
    expect(t1_1.number).toBe(1);

    const t1_2 = await openTicket(db, {
      guildId: '111111111111111111',
      categoryId: cat1.id,
      openerId: 'user_b',
      channelId: 'chan_2',
    });
    expect(t1_2.number).toBe(2);

    // Guild 2 tickets independently start at 1, 2
    const t2_1 = await openTicket(db, {
      guildId: '222222222222222222',
      categoryId: cat2.id,
      openerId: 'user_a',
      channelId: 'chan_3',
    });
    expect(t2_1.number).toBe(1);

    const t2_2 = await openTicket(db, {
      guildId: '222222222222222222',
      categoryId: cat2.id,
      openerId: 'user_b',
      channelId: 'chan_4',
    });
    expect(t2_2.number).toBe(2);
  });

  it('(q3b) openTicket serializes concurrent openings and retries on unique violation', async () => {
    await ensureGuild(db, '111111111111111111', 'Guild 1');

    const cat = await createCategory(db, '111111111111111111', {
      name: 'Concurrent',
      parentChannelId: '100',
      maxOpenPerUser: 10,
    });

    const results = await Promise.all([
      openTicket(db, {
        guildId: '111111111111111111',
        categoryId: cat.id,
        openerId: 'user_conc_1',
        channelId: 'chan_c1',
      }),
      openTicket(db, {
        guildId: '111111111111111111',
        categoryId: cat.id,
        openerId: 'user_conc_2',
        channelId: 'chan_c2',
      }),
      openTicket(db, {
        guildId: '111111111111111111',
        categoryId: cat.id,
        openerId: 'user_conc_3',
        channelId: 'chan_c3',
      }),
    ]);

    const numbers = results.map((t) => t.number).sort((a, b) => a - b);
    expect(numbers).toEqual([1, 2, 3]);
  });

  it('(q4) limit: enforces max_open_per_user and prevents category deletion while referenced', async () => {
    await ensureGuild(db, '111111111111111111', 'Guild 1');

    const cat = await createCategory(db, '111111111111111111', {
      name: 'Limited',
      parentChannelId: '100',
      maxOpenPerUser: 1,
    });

    const firstTicket = await openTicket(db, {
      guildId: '111111111111111111',
      categoryId: cat.id,
      openerId: 'user_limited',
      channelId: 'chan_limited_1',
    });
    expect(firstTicket.id).toBeDefined();

    // Second openTicket by same opener exceeds max_open_per_user (1) -> limit error
    await expect(
      openTicket(db, {
        guildId: '111111111111111111',
        categoryId: cat.id,
        openerId: 'user_limited',
        channelId: 'chan_limited_2',
      }),
    ).rejects.toMatchObject({ code: 'limit' });

    // deleteCategory while referenced by firstTicket -> limit error
    await expect(deleteCategory(db, '111111111111111111', cat.id)).rejects.toMatchObject({
      code: 'limit',
    });
  });

  it('(q5) blocked: refuses blocked users from opening tickets', async () => {
    await ensureGuild(db, '111111111111111111', 'Guild 1');

    const cat = await createCategory(db, '111111111111111111', {
      name: 'General',
      parentChannelId: '100',
    });

    // Block user_blocked in guild 1
    await db.insert(schema.blocks).values({
      guild_id: '111111111111111111',
      user_id: 'user_blocked',
      created_by: 'admin_1',
      reason: 'Spamming',
    });

    // Blocked user cannot open ticket -> blocked error
    await expect(
      openTicket(db, {
        guildId: '111111111111111111',
        categoryId: cat.id,
        openerId: 'user_blocked',
        channelId: 'chan_blocked',
      }),
    ).rejects.toMatchObject({ code: 'blocked' });

    // Negative control: non-blocked user can open ticket
    const allowed = await openTicket(db, {
      guildId: '111111111111111111',
      categoryId: cat.id,
      openerId: 'user_unblocked',
      channelId: 'chan_unblocked',
    });
    expect(allowed.id).toBeDefined();
  });

  it('(q6) claim→close→reopen updates columns and writes 3 audit rows', async () => {
    await ensureGuild(db, '111111111111111111', 'Guild 1');

    const cat = await createCategory(db, '111111111111111111', {
      name: 'General',
      parentChannelId: '100',
    });

    const ticket = await openTicket(db, {
      guildId: '111111111111111111',
      categoryId: cat.id,
      openerId: 'user_opener',
      channelId: 'chan_q6',
    });

    // 1. claim
    const claimed = await transitionTicket(
      db,
      '111111111111111111',
      ticket.id,
      'claim',
      'staff_claimer',
    );
    expect(claimed.status).toBe('claimed');
    expect(claimed.claimer_id).toBe('staff_claimer');

    // 2. close
    const closed = await transitionTicket(
      db,
      '111111111111111111',
      ticket.id,
      'close',
      'staff_claimer',
      undefined,
      'Issue resolved',
    );
    expect(closed.status).toBe('closed');
    expect(closed.claimer_id).toBe('staff_claimer');
    expect(closed.closed_at).not.toBeNull();
    expect(closed.close_reason).toBe('Issue resolved');

    // 3. reopen
    const reopened = await transitionTicket(
      db,
      '111111111111111111',
      ticket.id,
      'reopen',
      'staff_claimer',
    );
    expect(reopened.status).toBe('open');
    expect(reopened.claimer_id).toBeNull();
    expect(reopened.reopened_count).toBe(1);
    expect(reopened.closed_at).toBeNull();
    expect(reopened.close_reason).toBeNull();

    // Check 3 audit log rows written
    const logs = await db
      .select()
      .from(schema.auditLog)
      .where(eq(schema.auditLog.guild_id, '111111111111111111'));
    expect(logs).toHaveLength(3);
    expect(logs.map((l) => l.kind)).toEqual(['ticket.claim', 'ticket.close', 'ticket.reopen']);
  });

  it('(q6b) unclaim by claimer ok, by other → not_claimer', async () => {
    await ensureGuild(db, '111111111111111111', 'Guild 1');

    const cat = await createCategory(db, '111111111111111111', {
      name: 'General',
      parentChannelId: '100',
    });

    const ticket = await openTicket(db, {
      guildId: '111111111111111111',
      categoryId: cat.id,
      openerId: 'user_opener',
      channelId: 'chan_q6b',
    });

    await transitionTicket(
      db,
      '111111111111111111',
      ticket.id,
      'claim',
      'staff_claimer',
    );

    // Unclaim by other → rejects with code 'not_claimer'
    await expect(
      transitionTicket(
        db,
        '111111111111111111',
        ticket.id,
        'unclaim',
        'other_staff',
      ),
    ).rejects.toMatchObject({ code: 'not_claimer' });

    // Unclaim by claimer → succeeds, status is open, claimer_id is null
    const unclaimed = await transitionTicket(
      db,
      '111111111111111111',
      ticket.id,
      'unclaim',
      'staff_claimer',
    );
    expect(unclaimed.status).toBe('open');
    expect(unclaimed.claimer_id).toBeNull();
  });

  it('(q6c) transfer with/without target and by non-claimer', async () => {
    await ensureGuild(db, '111111111111111111', 'Guild 1');

    const cat = await createCategory(db, '111111111111111111', {
      name: 'General',
      parentChannelId: '100',
    });

    const ticket = await openTicket(db, {
      guildId: '111111111111111111',
      categoryId: cat.id,
      openerId: 'user_opener',
      channelId: 'chan_q6c',
    });

    await transitionTicket(
      db,
      '111111111111111111',
      ticket.id,
      'claim',
      'staff_claimer',
    );

    // Transfer without target → rejects with code 'target_required'
    await expect(
      transitionTicket(
        db,
        '111111111111111111',
        ticket.id,
        'transfer',
        'staff_claimer',
      ),
    ).rejects.toMatchObject({ code: 'target_required' });

    // Transfer by other → rejects with code 'not_claimer'
    await expect(
      transitionTicket(
        db,
        '111111111111111111',
        ticket.id,
        'transfer',
        'other_staff',
        'target_staff',
      ),
    ).rejects.toMatchObject({ code: 'not_claimer' });

    // Transfer with target by claimer → succeeds, claimer_id is targetId
    const transferred = await transitionTicket(
      db,
      '111111111111111111',
      ticket.id,
      'transfer',
      'staff_claimer',
      'target_staff',
    );
    expect(transferred.status).toBe('claimed');
    expect(transferred.claimer_id).toBe('target_staff');
  });

  it('(q7) appendMessage stores bytes that do not contain the plain text and readMessages returns it', async () => {
    await ensureGuild(db, '111111111111111111', 'Guild 1');

    const cat = await createCategory(db, '111111111111111111', {
      name: 'General',
      parentChannelId: '100',
    });

    const ticket = await openTicket(db, {
      guildId: '111111111111111111',
      categoryId: cat.id,
      openerId: 'user_opener',
      channelId: 'chan_q7',
    });

    const key = randomBytes(32);
    const plainText = 'Plaintext sensitive content that must be encrypted at rest!';

    await appendMessage(db, key, {
      guildId: '111111111111111111',
      ticketId: ticket.id,
      id: 'msg_1001',
      authorId: 'user_opener',
      authorName: 'Opener User',
      content: plainText,
    });

    // Verify stored raw database row
    const rawMsgRows = await db
      .select()
      .from(schema.messages)
      .where(eq(schema.messages.id, 'msg_1001'));
    expect(rawMsgRows).toHaveLength(1);
    const rawMsg = rawMsgRows[0];
    expect(rawMsg.content_enc).toBeInstanceOf(Buffer);
    expect(rawMsg.content_enc.toString('utf-8').includes(plainText)).toBe(false);

    // readMessages returns decrypted plain text oldest first
    const read = await readMessages(db, key, '111111111111111111', ticket.id);
    expect(read).toHaveLength(1);
    expect(read[0].content).toBe(plainText);
  });

  it('(q8) first staff message sets first_response_at once', async () => {
    await ensureGuild(db, '111111111111111111', 'Guild 1');

    const cat = await createCategory(db, '111111111111111111', {
      name: 'General',
      parentChannelId: '100',
    });

    const ticket = await openTicket(db, {
      guildId: '111111111111111111',
      categoryId: cat.id,
      openerId: 'user_opener',
      channelId: 'chan_q8',
    });

    const key = randomBytes(32);

    // Initial state: first_response_at is null
    const initial = await getTicket(db, '111111111111111111', ticket.id);
    expect(initial.first_response_at).toBeNull();

    // 1. User message (non-staff) does NOT set first_response_at
    await appendMessage(db, key, {
      guildId: '111111111111111111',
      ticketId: ticket.id,
      id: 'msg_user_1',
      authorId: 'user_opener',
      authorName: 'Opener',
      isStaff: false,
      content: 'Hello, need help',
    });

    const afterUser = await getTicket(db, '111111111111111111', ticket.id);
    expect(afterUser.first_response_at).toBeNull();

    // 2. First staff message sets first_response_at
    await appendMessage(db, key, {
      guildId: '111111111111111111',
      ticketId: ticket.id,
      id: 'msg_staff_1',
      authorId: 'staff_1',
      authorName: 'Staff Member 1',
      isStaff: true,
      content: 'Hello! How can we assist you?',
    });

    const afterFirstStaff = await getTicket(db, '111111111111111111', ticket.id);
    expect(afterFirstStaff.first_response_at).not.toBeNull();
    const firstResponseTime = afterFirstStaff.first_response_at;

    // 3. Second staff message does not overwrite first_response_at
    await appendMessage(db, key, {
      guildId: '111111111111111111',
      ticketId: ticket.id,
      id: 'msg_staff_2',
      authorId: 'staff_2',
      authorName: 'Staff Member 2',
      isStaff: true,
      content: 'Another staff note',
    });

    const afterSecondStaff = await getTicket(db, '111111111111111111', ticket.id);
    expect(afterSecondStaff.first_response_at).toEqual(firstResponseTime);
  });
});
