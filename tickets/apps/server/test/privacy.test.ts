import { describe, it, expect, beforeAll, beforeEach, afterAll, vi } from 'vitest';
import { createHash } from 'node:crypto';
import { eq } from 'drizzle-orm';
import { openTestDb, type TestDbHandle } from '@nakara-tickets/db/test-support';
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
  blocks,
} from '@nakara-tickets/db';
import { deleteUserData, exportGuild, purgeExpired } from '../src/privacy.js';
import { sealBytes } from '@nakara-tickets/core';

describe('server privacy unit tests', () => {
  let testEnv: TestDbHandle;
  let db: any;
  const dataKey = Buffer.alloc(32, 9);
  const GUILD_ID = '111111111111111111';
  const USER_ID = '222222222222222222';
  const OTHER_USER = '333333333333333333';

  beforeAll(async () => {
    testEnv = await openTestDb();
    db = testEnv.db;
  });

  beforeEach(async () => {
    await testEnv.reset();

    await db.insert(guilds).values({
      guild_id: GUILD_ID,
      name: 'Server Privacy Test Guild',
    });

    await db.insert(guildSettings).values({
      guild_id: GUILD_ID,
      retention_days: 90,
    });
  });

  afterAll(async () => {
    await testEnv.close();
  });

  it('deleteUserData with storage service removes files and rows', async () => {
    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: GUILD_ID,
        name: 'General',
        parent_channel_id: '333333333333333333',
      })
      .returning();

    const [tkt] = await db
      .insert(tickets)
      .values({
        guild_id: GUILD_ID,
        number: 1,
        category_id: cat.id,
        opener_id: USER_ID,
        channel_id: '444444444444444444',
        answers: { subject: 'Issue report' },
      })
      .returning();

    const [msg] = await db
      .insert(messages)
      .values({
        id: 'msg-srv-1',
        guild_id: GUILD_ID,
        ticket_id: tkt.id,
        author_id: USER_ID,
        author_name: 'Author',
        content_enc: sealBytes(dataKey, Buffer.from('hello world')),
      })
      .returning();

    await db.insert(attachments).values({
      guild_id: GUILD_ID,
      ticket_id: tkt.id,
      message_id: msg.id,
      filename: 'file.txt',
      size: 12,
      sha256: 'f'.repeat(64),
      stored: true,
      storage_key: 'srv/file.txt',
    });

    await db.insert(ratings).values({
      guild_id: GUILD_ID,
      ticket_id: tkt.id,
      user_id: USER_ID,
      score: 5,
    });

    // Blocks: USER_ID as target, and USER_ID as creator
    await db.insert(blocks).values([
      {
        guild_id: GUILD_ID,
        user_id: USER_ID,
        reason: 'target block',
        created_by: OTHER_USER,
      },
      {
        guild_id: GUILD_ID,
        user_id: OTHER_USER,
        reason: 'creator block',
        created_by: USER_ID,
      },
    ]);

    // Audit logs naming USER_ID
    await db.insert(auditLog).values([
      {
        guild_id: GUILD_ID,
        actor_id: USER_ID,
        kind: 'ticket.open',
        target: tkt.id,
        detail: { user: USER_ID },
      },
      {
        guild_id: GUILD_ID,
        actor_id: OTHER_USER,
        kind: 'user.block',
        target: USER_ID,
        detail: { target: USER_ID },
      },
    ]);

    const mockStorage = {
      delete: vi.fn(),
    };

    const counts = await deleteUserData(db, mockStorage, GUILD_ID, USER_ID);

    expect(counts.messages).toBe(1);
    expect(counts.attachments).toBe(1);
    expect(counts.ratings).toBe(1);
    expect(counts.tickets).toBe(1);
    expect(mockStorage.delete).toHaveBeenCalledWith('srv/file.txt');

    // Ticket opener_id replaced and answers nulled
    const [updatedTicket] = await db.select().from(tickets).where(eq(tickets.id, tkt.id));
    expect(updatedTicket.opener_id).toBe('deleted');
    expect(updatedTicket.answers).toBeNull();

    // Target block deleted, creator block set to 'deleted'
    const targetBlocks = await db.select().from(blocks).where(eq(blocks.user_id, USER_ID));
    expect(targetBlocks.length).toBe(0);

    const [creatorBlock] = await db.select().from(blocks).where(eq(blocks.user_id, OTHER_USER));
    expect(creatorBlock.created_by).toBe('deleted');

    // Data request has user_id stored as sha256(userId)
    const expectedHash = createHash('sha256').update(USER_ID).digest('hex');
    const reqs = await db.select().from(dataRequests);
    expect(reqs.length).toBe(1);
    expect(reqs[0].kind).toBe('delete');
    expect(reqs[0].status).toBe('done');
    expect(reqs[0].user_id).toBe(expectedHash);

    // Audit logs anonymised
    const audits = await db.select().from(auditLog);
    for (const audit of audits) {
      expect(audit.actor_id).not.toBe(USER_ID);
      expect(audit.target).not.toBe(USER_ID);
      expect(JSON.stringify(audit.detail ?? {})).not.toContain(USER_ID);
    }
  });

  it('deleteUserData: a failing storage delete leaves the attachment row', async () => {
    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: GUILD_ID,
        name: 'General',
        parent_channel_id: '333333333333333333',
      })
      .returning();

    const [tkt] = await db
      .insert(tickets)
      .values({
        guild_id: GUILD_ID,
        number: 2,
        category_id: cat.id,
        opener_id: USER_ID,
        channel_id: '444444444444444445',
      })
      .returning();

    const [msg] = await db
      .insert(messages)
      .values({
        id: 'msg-srv-fail',
        guild_id: GUILD_ID,
        ticket_id: tkt.id,
        author_id: USER_ID,
        author_name: 'Author',
        content_enc: sealBytes(dataKey, Buffer.from('hello')),
      })
      .returning();

    const [att] = await db
      .insert(attachments)
      .values({
        guild_id: GUILD_ID,
        ticket_id: tkt.id,
        message_id: msg.id,
        filename: 'leave-me.png',
        size: 200,
        sha256: 'a'.repeat(64),
        stored: true,
        storage_key: 'srv/leave-me.png',
      })
      .returning();

    const failingStorage = {
      delete: vi.fn().mockRejectedValue(new Error('Storage failure')),
    };

    const counts = await deleteUserData(db, failingStorage, GUILD_ID, USER_ID);
    expect(failingStorage.delete).toHaveBeenCalledWith('srv/leave-me.png');
    expect(counts.attachments).toBe(0);

    // Row is kept in attachments
    const remaining = await db.select().from(attachments).where(eq(attachments.id, att.id));
    expect(remaining.length).toBe(1);
    expect(remaining[0].storage_key).toBe('srv/leave-me.png');
  });

  it('exportGuild returns complete decrypted payload without secrets', async () => {
    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: GUILD_ID,
        name: 'Technical',
        parent_channel_id: '333333333333333333',
      })
      .returning();

    const [tkt] = await db
      .insert(tickets)
      .values({
        guild_id: GUILD_ID,
        number: 10,
        category_id: cat.id,
        opener_id: USER_ID,
        channel_id: '444444444444444444',
      })
      .returning();

    await db.insert(messages).values({
      id: 'msg-exp-server',
      guild_id: GUILD_ID,
      ticket_id: tkt.id,
      author_id: USER_ID,
      author_name: 'Author',
      content_enc: sealBytes(dataKey, Buffer.from('Server exported message')),
    });

    const exported = await exportGuild(db, dataKey, GUILD_ID);

    expect(exported.guild).toBeDefined();
    expect(exported.settings).toBeDefined();
    expect(exported.tickets[0].messages[0].content).toBe('Server exported message');
    expect(JSON.stringify(exported)).not.toContain('secret_enc');
    expect(JSON.stringify(exported)).not.toContain('csrf_hash');
  });

  it('purgeExpired removes old tickets and calls storage delete', async () => {
    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: GUILD_ID,
        name: 'General',
        parent_channel_id: '333333333333333333',
      })
      .returning();

    const now = new Date('2026-11-14T12:00:00Z');
    const closed100DaysAgo = new Date(now.getTime() - 100 * 24 * 60 * 60 * 1000);

    const [tkt] = await db
      .insert(tickets)
      .values({
        guild_id: GUILD_ID,
        number: 100,
        category_id: cat.id,
        opener_id: USER_ID,
        channel_id: '444444444444444444',
        status: 'closed',
        closed_at: closed100DaysAgo,
      })
      .returning();

    await db.insert(attachments).values({
      guild_id: GUILD_ID,
      ticket_id: tkt.id,
      filename: 'old.pdf',
      size: 500,
      sha256: 'e'.repeat(64),
      stored: true,
      storage_key: 'srv/old.pdf',
    });

    const mockStorage = {
      delete: vi.fn(),
    };

    const counts = await purgeExpired(db, now, mockStorage);
    expect(counts.tickets).toBe(1);
    expect(counts.attachments).toBe(1);
    expect(mockStorage.delete).toHaveBeenCalledWith('srv/old.pdf');
  });

  it('purgeExpired: keep attachment row (mark for retry) when file delete fails, never orphan files', async () => {
    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: GUILD_ID,
        name: 'General',
        parent_channel_id: '333333333333333333',
      })
      .returning();

    const now = new Date('2026-11-14T12:00:00Z');
    const closed150DaysAgo = new Date(now.getTime() - 150 * 24 * 60 * 60 * 1000);

    const [tkt] = await db
      .insert(tickets)
      .values({
        guild_id: GUILD_ID,
        number: 150,
        category_id: cat.id,
        opener_id: USER_ID,
        channel_id: '444444444444444150',
        status: 'closed',
        closed_at: closed150DaysAgo,
      })
      .returning();

    const [att] = await db
      .insert(attachments)
      .values({
        guild_id: GUILD_ID,
        ticket_id: tkt.id,
        filename: 'srv-fail.pdf',
        size: 300,
        sha256: 'b'.repeat(64),
        stored: true,
        storage_key: 'srv/srv-fail.pdf',
      })
      .returning();

    const failingStorage = {
      delete: vi.fn().mockRejectedValueOnce(new Error('S3 down')),
    };

    const counts = await purgeExpired(db, now, failingStorage);
    expect(counts.attachments).toBe(0);
    expect(counts.tickets).toBe(0);

    // Row is kept in attachments table and ticket is not deleted
    const remainingAtt = await db.select().from(attachments).where(eq(attachments.id, att.id));
    expect(remainingAtt.length).toBe(1);

    const remainingTkt = await db.select().from(tickets).where(eq(tickets.id, tkt.id));
    expect(remainingTkt.length).toBe(1);
  });
});
