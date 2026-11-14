import {
  tickets,
  categories,
  guildSettings,
  blocks,
  ticketMembers,
  messages,
  auditLog,
  inGuild,
  type TicketsDb,
} from '@nakara-tickets/db';
import * as dbPkg from '@nakara-tickets/db';
import { sealBytes } from '@nakara-tickets/core';
import { eq, and, or, gt, isNull, inArray, desc } from 'drizzle-orm';

export type TicketErrorCode =
  | 'limit'
  | 'blocked'
  | 'not_found'
  | 'invalid_transition'
  | 'not_claimer'
  | 'target_required';

export class TicketError extends Error {
  code: TicketErrorCode;
  constructor(code: TicketErrorCode, message?: string) {
    super(message ?? code);
    this.name = 'TicketError';
    this.code = code;
  }
}

export async function getCategory(db: TicketsDb, guildId: string, categoryId: string) {
  if (typeof (dbPkg as any).getCategory === 'function') {
    return (dbPkg as any).getCategory(db, guildId, categoryId);
  }
  const [cat] = await db
    .select()
    .from(categories)
    .where(and(inGuild(categories, guildId), eq(categories.id, categoryId)));
  return cat ?? null;
}

export async function getSettings(db: TicketsDb, guildId: string) {
  if (typeof (dbPkg as any).getSettings === 'function') {
    return (dbPkg as any).getSettings(db, guildId);
  }
  const [row] = await db
    .select()
    .from(guildSettings)
    .where(eq(guildSettings.guild_id, guildId));
  return row ?? null;
}

export async function getTicket(db: TicketsDb, guildId: string, ticketId: string) {
  if (typeof (dbPkg as any).getTicket === 'function') {
    return (dbPkg as any).getTicket(db, guildId, ticketId);
  }
  const [t] = await db
    .select()
    .from(tickets)
    .where(and(inGuild(tickets, guildId), eq(tickets.id, ticketId)));
  return t ?? null;
}

export async function getTicketByChannel(db: TicketsDb, guildId: string, channelId: string) {
  if (typeof (dbPkg as any).getTicketByChannel === 'function') {
    return (dbPkg as any).getTicketByChannel(db, guildId, channelId);
  }
  const [t] = await db
    .select()
    .from(tickets)
    .where(and(inGuild(tickets, guildId), eq(tickets.channel_id, channelId)));
  return t ?? null;
}

export async function openTicket(
  db: TicketsDb,
  input: {
    guildId: string;
    categoryId: string;
    openerId: string;
    channelId: string;
    answers?: any;
  }
) {
  if (typeof (dbPkg as any).openTicket === 'function') {
    return (dbPkg as any).openTicket(db, input);
  }

  const { guildId, categoryId, openerId, channelId, answers } = input;

  // 1. Check if user is blocked
  const now = new Date();
  const [blockRow] = await db
    .select()
    .from(blocks)
    .where(
      and(
        inGuild(blocks, guildId),
        eq(blocks.user_id, openerId),
        or(isNull(blocks.expires_at), gt(blocks.expires_at, now))
      )
    );

  if (blockRow) {
    throw new TicketError('blocked', 'User is blocked from opening tickets');
  }

  // 2. Check category
  const [cat] = await db
    .select()
    .from(categories)
    .where(and(inGuild(categories, guildId), eq(categories.id, categoryId)));

  if (!cat) {
    throw new TicketError('not_found', 'Category not found');
  }

  // 3. Check limit
  const openOrClaimed = await db
    .select()
    .from(tickets)
    .where(
      and(
        inGuild(tickets, guildId),
        eq(tickets.category_id, categoryId),
        eq(tickets.opener_id, openerId),
        inArray(tickets.status, ['open', 'claimed'])
      )
    );

  if (openOrClaimed.length >= cat.max_open_per_user) {
    throw new TicketError('limit', 'Open ticket limit reached');
  }

  // 4. Ticket number: max per guild + 1
  const [latest] = await db
    .select({ number: tickets.number })
    .from(tickets)
    .where(inGuild(tickets, guildId))
    .orderBy(desc(tickets.number))
    .limit(1);

  const number = (latest?.number ?? 0) + 1;

  // 5. Insert ticket
  const [created] = await db
    .insert(tickets)
    .values({
      guild_id: guildId,
      number,
      category_id: categoryId,
      status: 'open',
      opener_id: openerId,
      channel_id: channelId,
      answers: answers ?? null,
    })
    .returning();

  // 6. Insert member
  await db.insert(ticketMembers).values({
    guild_id: guildId,
    ticket_id: created.id,
    user_id: openerId,
    role: 'opener',
  });

  return created;
}

export async function transitionTicket(
  db: TicketsDb,
  guildId: string,
  ticketId: string,
  t: 'claim' | 'unclaim' | 'transfer' | 'close' | 'reopen',
  actorId: string,
  targetId?: string,
  reason?: string
) {
  if (typeof (dbPkg as any).transitionTicket === 'function') {
    return (dbPkg as any).transitionTicket(db, guildId, ticketId, t, actorId, targetId, reason);
  }

  const [cur] = await db
    .select()
    .from(tickets)
    .where(and(inGuild(tickets, guildId), eq(tickets.id, ticketId)));

  if (!cur) {
    throw new TicketError('not_found', 'Ticket not found');
  }

  let patch: Partial<typeof tickets.$inferInsert> = {};

  if (t === 'claim') {
    if (cur.status !== 'open') {
      throw new TicketError('invalid_transition', `Cannot claim ticket in state ${cur.status}`);
    }
    patch = { status: 'claimed', claimer_id: actorId };
  } else if (t === 'unclaim') {
    if (cur.status !== 'claimed' || cur.claimer_id !== actorId) {
      throw new TicketError('not_claimer', 'Only the claimer can unclaim');
    }
    patch = { status: 'open', claimer_id: null };
  } else if (t === 'transfer') {
    if (cur.status !== 'claimed' || cur.claimer_id !== actorId) {
      throw new TicketError('not_claimer', 'Only the claimer can transfer');
    }
    if (!targetId) {
      throw new TicketError('target_required', 'Target is required for transfer');
    }
    patch = { claimer_id: targetId };
  } else if (t === 'close') {
    if (cur.status !== 'open' && cur.status !== 'claimed') {
      throw new TicketError('invalid_transition', `Cannot close ticket in state ${cur.status}`);
    }
    patch = {
      status: 'closed',
      closed_at: new Date(),
      close_reason: reason ?? null,
    };
  } else if (t === 'reopen') {
    if (cur.status !== 'closed') {
      throw new TicketError('invalid_transition', `Cannot reopen ticket in state ${cur.status}`);
    }
    patch = {
      status: 'open',
      claimer_id: null,
      closed_at: null,
      close_reason: null,
      reopened_count: (cur.reopened_count ?? 0) + 1,
    };
  } else {
    throw new TicketError('invalid_transition', `Unknown transition ${t}`);
  }

  const [updated] = await db
    .update(tickets)
    .set(patch)
    .where(and(inGuild(tickets, guildId), eq(tickets.id, ticketId)))
    .returning();

  await db.insert(auditLog).values({
    guild_id: guildId,
    actor_id: actorId,
    kind: `ticket.${t}`,
    target: ticketId,
    detail: { reason, targetId },
  });

  return updated;
}

export async function appendMessage(
  db: TicketsDb,
  key: Buffer,
  input: {
    guildId: string;
    ticketId: string;
    id: string;
    authorId: string;
    authorName: string;
    isStaff: boolean;
    isSystem: boolean;
    content: string;
  }
) {
  if (typeof (dbPkg as any).appendMessage === 'function') {
    return (dbPkg as any).appendMessage(db, key, input);
  }

  const { guildId, ticketId, id, authorId, authorName, isStaff, isSystem, content } = input;
  const content_enc = sealBytes(key, Buffer.from(content, 'utf-8'));

  await db.insert(messages).values({
    id,
    guild_id: guildId,
    ticket_id: ticketId,
    author_id: authorId,
    author_name: authorName,
    is_staff: isStaff,
    is_system: isSystem,
    content_enc,
  });

  const now = new Date();
  const [ticket] = await db
    .select({ first_response_at: tickets.first_response_at })
    .from(tickets)
    .where(and(inGuild(tickets, guildId), eq(tickets.id, ticketId)));

  const ticketPatch: { last_activity_at: Date; first_response_at?: Date } = {
    last_activity_at: now,
  };

  if (isStaff && ticket && !ticket.first_response_at) {
    ticketPatch.first_response_at = now;
  }

  await db
    .update(tickets)
    .set(ticketPatch)
    .where(and(inGuild(tickets, guildId), eq(tickets.id, ticketId)));
}
