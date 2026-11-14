import { describe, it, expect, beforeAll, beforeEach, afterAll, vi } from 'vitest';
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
} from '@nakara-tickets/db';
import { deleteUserData, exportGuild, purgeExpired } from '../src/privacy.js';
import { sealBytes } from '@nakara-tickets/core';

describe('server privacy unit tests', () => {
  let testEnv: TestDbHandle;
  let db: any;
  const dataKey = Buffer.alloc(32, 9);
  const GUILD_ID = '111111111111111111';
  const USER_ID = '222222222222222222';

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

    const mockStorage = {
      delete: vi.fn(),
    };

    const counts = await deleteUserData(db, mockStorage, GUILD_ID, USER_ID);

    expect(counts.messages).toBe(1);
    expect(counts.attachments).toBe(1);
    expect(counts.ratings).toBe(1);
    expect(counts.tickets).toBe(1);
    expect(mockStorage.delete).toHaveBeenCalledWith('srv/file.txt');

    const [updatedTicket] = await db.select().from(tickets).where(eq(tickets.id, tkt.id));
    expect(updatedTicket.opener_id).toBe('deleted');

    const reqs = await db.select().from(dataRequests);
    expect(reqs.length).toBe(1);
    expect(reqs[0].kind).toBe('delete');
    expect(reqs[0].status).toBe('done');

    const audits = await db.select().from(auditLog);
    expect(audits.length).toBe(1);
    expect(JSON.stringify(audits[0])).not.toContain(USER_ID);
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
});
