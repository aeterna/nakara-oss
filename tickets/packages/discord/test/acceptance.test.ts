import { describe, it, expect, vi } from 'vitest';
import { randomBytes } from 'node:crypto';
import { acquireGatewayLock } from '../src/lock.js';
import {
  handleOpenButton,
  handleClaim,
  handleClose,
  handleMessageCreate,
} from '../src/handlers/index.js';
import { FakeDiscordPort } from './fake-port.js';
import { createTestDb } from './test-db.js';
import { guilds, guildSettings, categories, tickets, messages } from '@nakara-tickets/db';
import { openBytes } from '@nakara-tickets/core';
import { startGateway } from '../src/gateway.js';
import { eq } from 'drizzle-orm';

describe('acceptance tests d1-d8', () => {
  it('d1 lock: a second acquireGatewayLock on the same key keeps waiting until the first releases', async () => {
    const executedQueries: { sql: string; params: any[] }[] = [];
    let isLocked = false;
    let unlockCallCount = 0;

    const createMockClient = () => {
      let clientReleased = false;
      return {
        query: vi.fn(async (sql: string, params?: any[]) => {
          executedQueries.push({ sql, params: params ?? [] });
          if (sql.includes('pg_try_advisory_lock')) {
            if (!isLocked) {
              isLocked = true;
              return { rows: [{ locked: true }] };
            }
            return { rows: [{ locked: false }] };
          }
          if (sql.includes('pg_advisory_unlock')) {
            isLocked = false;
            unlockCallCount++;
            return { rows: [{ unlocked: true }] };
          }
          return { rows: [] };
        }),
        release: vi.fn(() => {
          clientReleased = true;
        }),
        get released() {
          return clientReleased;
        },
      };
    };

    const fakePool: any = {
      connect: vi.fn(async () => createMockClient()),
    };

    // First acquire
    const lock1 = await acquireGatewayLock(fakePool, 'app-42', { intervalMs: 20 });
    expect(isLocked).toBe(true);

    // Verify SQL query text and key
    const lock1Queries = executedQueries.filter((q) => q.sql.includes('pg_try_advisory_lock'));
    expect(lock1Queries.length).toBeGreaterThanOrEqual(1);
    expect(lock1Queries[0].sql).toContain('pg_try_advisory_lock(hashtextextended($1, 0))');
    expect(lock1Queries[0].params).toEqual(['nakara-tickets:app-42']);

    // Second acquire in progress
    let standbyCalled = 0;
    const lock2Promise = acquireGatewayLock(fakePool, 'app-42', {
      intervalMs: 25,
      onStandby: () => {
        standbyCalled++;
      },
    });

    // Wait a brief tick for lock2 to try and fail, entering standby
    await new Promise((r) => setTimeout(r, 60));
    expect(standbyCalled).toBeGreaterThanOrEqual(1);

    // Release lock1
    await lock1.release();
    expect(unlockCallCount).toBe(1);
    const unlockQuery = executedQueries.find((q) => q.sql.includes('pg_advisory_unlock'));
    expect(unlockQuery?.sql).toContain('pg_advisory_unlock(hashtextextended($1, 0))');
    expect(unlockQuery?.params).toEqual(['nakara-tickets:app-42']);

    // Now lock2 should successfully acquire
    const lock2 = await lock2Promise;
    expect(isLocked).toBe(true);
    await lock2.release();
    expect(unlockCallCount).toBe(2);
  });

  it('d2 open without form creates thread with name ticket-0001 and posts claim/close buttons', async () => {
    const { db } = await createTestDb();
    const guildId = '111111111111111111';
    await db.insert(guilds).values({ guild_id: guildId, name: 'Test Guild' });
    await db.insert(guildSettings).values({ guild_id: guildId, locale: 'th' });

    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: guildId,
        name: 'General',
        parent_channel_id: '999000111',
        name_template: 'ticket-{number}',
        form: null,
      })
      .returning();

    const port = new FakeDiscordPort();
    const interaction = {
      guildId,
      user: { id: '222222222222222222', username: 'alice' },
    };

    await handleOpenButton(port, db, interaction, cat.id);

    // Thread created with ticket-0001
    const created = Array.from(port.threads.values());
    expect(created.length).toBe(1);
    expect(created[0].name).toBe('ticket-0001');
    expect(created[0].channelId).toBe('999000111');
    expect(created[0].members).toContain('222222222222222222');

    // Claim and close buttons posted
    expect(port.messages.length).toBe(1);
    const msg = port.messages[0];
    expect(msg.channelId).toBe(created[0].id);
    const components = msg.payload.components ?? [];
    const customIds = components.flatMap((c: any) => c.components?.map((b: any) => b.customId) ?? []);

    const [ticketRow] = await db.select().from(tickets).where(eq(tickets.guild_id, guildId));
    expect(ticketRow).toBeDefined();
    expect(ticketRow.number).toBe(1);
    expect(ticketRow.status).toBe('open');
    expect(ticketRow.channel_id).toBe(created[0].id);

    expect(customIds).toContain(`nt:claim:${ticketRow.id}`);
    expect(customIds).toContain(`nt:close:${ticketRow.id}`);
  });

  it('d3 open with form shows modal and nothing is written', async () => {
    const { db } = await createTestDb();
    const guildId = '111111111111111112';
    await db.insert(guilds).values({ guild_id: guildId, name: 'Test Guild' });
    await db.insert(guildSettings).values({ guild_id: guildId, locale: 'en' });

    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: guildId,
        name: 'Applications',
        parent_channel_id: '999000112',
        name_template: 'app-{number}',
        form: [
          { id: 'ign', label: 'In Game Name', required: true },
          { id: 'reason', label: 'Why join?', required: true },
        ],
      })
      .returning();

    const port = new FakeDiscordPort();
    const interaction = {
      guildId,
      user: { id: '333333333333333333', username: 'bob' },
    };

    await handleOpenButton(port, db, interaction, cat.id);

    // Modal shown
    expect(port.modals.length).toBe(1);
    expect(port.modals[0].modal.customId).toBe(`nt:form:${cat.id}`);
    expect(port.modals[0].modal.components.length).toBe(2);

    // Nothing written to tickets table
    const ticketRows = await db.select().from(tickets).where(eq(tickets.guild_id, guildId));
    expect(ticketRows.length).toBe(0);

    // No threads created
    expect(port.threads.size).toBe(0);
  });

  it('d4 limit → ephemeral reply, no thread', async () => {
    const { db } = await createTestDb();
    const guildId = '111111111111111113';
    await db.insert(guilds).values({ guild_id: guildId, name: 'Test Guild' });
    await db.insert(guildSettings).values({ guild_id: guildId, locale: 'th' });

    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: guildId,
        name: 'SingleTicketCategory',
        parent_channel_id: '999000113',
        max_open_per_user: 1,
      })
      .returning();

    const port = new FakeDiscordPort();
    const interaction = {
      guildId,
      user: { id: '444444444444444444', username: 'charlie' },
    };

    // First ticket succeeds
    await handleOpenButton(port, db, interaction, cat.id);
    expect(port.threads.size).toBe(1);

    // Second ticket fails due to limit
    const port2 = new FakeDiscordPort();
    await handleOpenButton(port2, db, interaction, cat.id);

    // No new thread created
    expect(port2.threads.size).toBe(0);

    // Ephemeral reply sent
    const reply =
      port2.ephemeralReplies.length > 0
        ? port2.ephemeralReplies[0].message
        : port2.editedReplies[0].message;
    const replyText = typeof reply === 'string' ? reply : reply.content;
    expect(replyText).toMatch(/กำหนด|limit|เปิดอยู่/i);

    // Ticket count in DB remains 1
    const ticketRows = await db.select().from(tickets).where(eq(tickets.guild_id, guildId));
    expect(ticketRows.length).toBe(1);
  });

  it('d5 non-staff claim refused, staff claim updates row', async () => {
    const { db } = await createTestDb();
    const guildId = '111111111111111114';
    await db.insert(guilds).values({ guild_id: guildId, name: 'Test Guild' });
    await db.insert(guildSettings).values({ guild_id: guildId, locale: 'en' });

    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: guildId,
        name: 'Support',
        parent_channel_id: '999000114',
        staff_role_ids: ['role-staff-123'],
      })
      .returning();

    const [ticket] = await db
      .insert(tickets)
      .values({
        guild_id: guildId,
        category_id: cat.id,
        number: 1,
        opener_id: '555555555555555555',
        channel_id: 'thread-8888',
        status: 'open',
      })
      .returning();

    const port = new FakeDiscordPort();

    // 1. Non-staff tries to claim
    const nonStaffInteraction = {
      guildId,
      user: { id: '666666666666666666' },
      memberPermissions: 0n,
      memberRoleIds: ['role-other'],
    };

    await handleClaim(port, db, nonStaffInteraction, ticket.id);

    // Ephemeral refusal
    const reply =
      port.ephemeralReplies.length > 0
        ? port.ephemeralReplies[0].message
        : port.editedReplies[0]?.message;
    const refusedText = typeof reply === 'string' ? reply : reply?.content;
    expect(refusedText).toMatch(/staff|ทีมงาน/i);

    // DB remains unchanged
    let [freshTicket] = await db.select().from(tickets).where(eq(tickets.id, ticket.id));
    expect(freshTicket.status).toBe('open');
    expect(freshTicket.claimer_id).toBeNull();

    // 2. Staff user claims
    const staffInteraction = {
      guildId,
      user: { id: '777777777777777777' },
      memberPermissions: 0n,
      memberRoleIds: ['role-staff-123'],
    };

    await handleClaim(port, db, staffInteraction, ticket.id);

    // DB row updated to claimed with claimer_id
    [freshTicket] = await db.select().from(tickets).where(eq(tickets.id, ticket.id));
    expect(freshTicket.status).toBe('claimed');
    expect(freshTicket.claimer_id).toBe('777777777777777777');

    // System line posted in thread
    expect(port.messages.some((m) => m.channelId === 'thread-8888' && m.payload.content?.includes('777777777777777777'))).toBe(true);
  });

  it('d6 close archives thread and status is closed', async () => {
    const { db } = await createTestDb();
    const guildId = '111111111111111115';
    await db.insert(guilds).values({ guild_id: guildId, name: 'Test Guild' });
    await db.insert(guildSettings).values({ guild_id: guildId, locale: 'en' });

    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: guildId,
        name: 'General',
        parent_channel_id: '999000115',
        staff_role_ids: ['role-staff-close'],
      })
      .returning();

    const [ticket] = await db
      .insert(tickets)
      .values({
        guild_id: guildId,
        category_id: cat.id,
        number: 1,
        opener_id: '888888888888888888',
        channel_id: 'thread-to-close',
        status: 'open',
      })
      .returning();

    const port = new FakeDiscordPort();
    // Register the thread in fake port
    await port.createPrivateThread('999000115', 'ticket-0001');
    const existingThread = port.threads.get('1000')!;
    existingThread.id = 'thread-to-close';
    port.threads.set('thread-to-close', existingThread);

    const staffInteraction = {
      guildId,
      user: { id: '999999999999999999' },
      memberPermissions: 1n << 5n, // MANAGE_GUILD
      memberRoleIds: [],
    };

    await handleClose(port, db, staffInteraction, ticket.id, 'Issue resolved');

    // DB status closed
    const [closedTicket] = await db.select().from(tickets).where(eq(tickets.id, ticket.id));
    expect(closedTicket.status).toBe('closed');
    expect(closedTicket.close_reason).toBe('Issue resolved');
    expect(closedTicket.closed_at).not.toBeNull();

    // Thread is locked and archived
    const threadState = port.threads.get('thread-to-close');
    expect(threadState?.locked).toBe(true);
    expect(threadState?.archived).toBe(true);
  });

  it('d7 message in ticket thread stored encrypted, bot message ignored', async () => {
    const { db } = await createTestDb();
    const dataKey = randomBytes(32);
    const guildId = '111111111111111116';
    await db.insert(guilds).values({ guild_id: guildId, name: 'Test Guild' });
    await db.insert(guildSettings).values({ guild_id: guildId, locale: 'en' });

    const [cat] = await db
      .insert(categories)
      .values({
        guild_id: guildId,
        name: 'Chat',
        parent_channel_id: '999000116',
        staff_role_ids: ['role-chat-staff'],
      })
      .returning();

    const [ticket] = await db
      .insert(tickets)
      .values({
        guild_id: guildId,
        category_id: cat.id,
        number: 1,
        opener_id: '121212121212121212',
        channel_id: 'thread-chat-1',
        status: 'open',
      })
      .returning();

    // 1. Bot message is ignored
    await handleMessageCreate(db, dataKey, {
      id: 'msg-bot-1',
      guildId,
      channelId: 'thread-chat-1',
      author: { id: 'bot-999', username: 'SomeBot', bot: true },
      content: 'This message from a bot should not be saved',
    });

    let storedMessages = await db.select().from(messages).where(eq(messages.ticket_id, ticket.id));
    expect(storedMessages.length).toBe(0);

    // 2. User message is stored encrypted
    const secretContent = 'This is a sensitive user message in the ticket thread.';
    await handleMessageCreate(db, dataKey, {
      id: 'msg-user-1',
      guildId,
      channelId: 'thread-chat-1',
      author: { id: '121212121212121212', username: 'dan', bot: false },
      content: secretContent,
      member: { permissions: 0n, roleIds: [] },
    });

    storedMessages = await db.select().from(messages).where(eq(messages.ticket_id, ticket.id));
    expect(storedMessages.length).toBe(1);

    const saved = storedMessages[0];
    expect(saved.id).toBe('msg-user-1');
    expect(saved.author_name).toBe('dan');
    expect(saved.is_staff).toBe(false);

    // Verify raw content_enc does NOT contain the plaintext string
    const rawBuffer = Buffer.from(saved.content_enc);
    expect(rawBuffer.includes(Buffer.from(secretContent, 'utf-8'))).toBe(false);

    // Decrypting with dataKey restores the original content
    const decrypted = openBytes(dataKey, rawBuffer);
    expect(decrypted.toString('utf-8')).toBe(secretContent);
  });

  it('d8 guild not allowed → leave', async () => {
    let left = false;
    let registeredGuildCommands: string[] = [];

    const mockGuildUnauthorized = {
      id: 'unauthorized-guild-999',
      leave: vi.fn(async () => {
        left = true;
      }),
      commands: {
        set: vi.fn(async () => []),
      },
    };

    const mockGuildAuthorized = {
      id: 'allowed-guild-111',
      leave: vi.fn(async () => {}),
      commands: {
        set: vi.fn(async (cmds: any[]) => {
          registeredGuildCommands.push(mockGuildAuthorized.id);
          return [];
        }),
      },
    };

    const listeners: Record<string, ((...args: any[]) => any)[]> = {};
    const mockClient: any = {
      on: vi.fn((event: string, handler: (...args: any[]) => any) => {
        listeners[event] = listeners[event] || [];
        listeners[event].push(handler);
        return mockClient;
      }),
      guilds: {
        cache: new Map([
          [mockGuildAuthorized.id, mockGuildAuthorized],
        ]),
      },
      login: vi.fn(async () => 'fake-token'),
      destroy: vi.fn(async () => {}),
      isReady: vi.fn(() => true),
    };

    const mockPool: any = {
      connect: vi.fn(async () => ({
        query: vi.fn(async () => ({ rows: [{ locked: true }] })),
        release: vi.fn(),
      })),
    };

    const dataKey = randomBytes(32);
    const gw = await startGateway({
      token: 'fake-token',
      appId: 'app-d8',
      allowedGuildIds: ['allowed-guild-111'],
      db: {} as any,
      pool: mockPool,
      dataKey,
      log: { info: () => {}, warn: () => {}, error: () => {} },
      client: mockClient,
    });

    // Trigger ready
    for (const h of listeners['ready'] ?? []) {
      await h(mockClient);
    }
    expect(registeredGuildCommands).toContain('allowed-guild-111');

    // Trigger guildCreate with unauthorized guild
    for (const h of listeners['guildCreate'] ?? []) {
      await h(mockGuildUnauthorized);
    }
    expect(left).toBe(true);

    // Negative control: trigger guildCreate with allowed guild
    let allowedLeft = false;
    const mockGuildAllowedNew = {
      id: 'allowed-guild-111',
      leave: vi.fn(async () => {
        allowedLeft = true;
      }),
    };
    for (const h of listeners['guildCreate'] ?? []) {
      await h(mockGuildAllowedNew);
    }
    expect(allowedLeft).toBe(false);

    await gw.stop();
  });
});
