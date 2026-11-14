import { and, eq, or, isNull, gt, lt, max, count, desc, sql } from 'drizzle-orm';
import type { TicketsDb } from '../index.js';
import { tickets, ticketMembers, blocks, categories, auditLog } from '../schema.js';
import { inGuild } from '../index.js';
import { TicketError } from './errors.js';
import { nextState, type Transition, type TicketStatus } from '@nakara-tickets/core';

export interface OpenTicketInput {
  guildId: string;
  categoryId: string;
  openerId: string;
  channelId: string;
  answers?: Record<string, any> | null;
}

export async function openTicket(db: TicketsDb, input: OpenTicketInput) {
  const { guildId, categoryId, openerId, channelId, answers } = input;

  const executeOpen = async () => {
    return await db.transaction(async (tx) => {
      await tx.execute(
        sql`SELECT pg_advisory_xact_lock(hashtextextended('nt-open:' || ${guildId}, 0))`,
      );

      // 1. Refuses a blocked user (code: blocked)
      const block = await tx
        .select()
        .from(blocks)
        .where(
          and(
            inGuild(blocks, guildId),
            eq(blocks.user_id, openerId),
            or(isNull(blocks.expires_at), gt(blocks.expires_at, new Date())),
          ),
        )
        .limit(1);

      if (block.length > 0) {
        throw new TicketError('blocked', `User ${openerId} is blocked in guild ${guildId}`);
      }

      // Verify category exists in this guild
      const cat = await tx
        .select()
        .from(categories)
        .where(and(eq(categories.id, categoryId), inGuild(categories, guildId)))
        .limit(1);

      if (cat.length === 0) {
        throw new TicketError('not_found', `Category ${categoryId} not found in guild ${guildId}`);
      }

      const maxOpen = cat[0].max_open_per_user;

      // 2. Refuses when the opener already has max_open_per_user open/claimed tickets in that category (code: limit)
      const existing = await tx
        .select({ count: count() })
        .from(tickets)
        .where(
          and(
            inGuild(tickets, guildId),
            eq(tickets.category_id, categoryId),
            eq(tickets.opener_id, openerId),
            or(eq(tickets.status, 'open'), eq(tickets.status, 'claimed')),
          ),
        );

      if (Number(existing[0]?.count ?? 0) >= maxOpen) {
        throw new TicketError(
          'limit',
          `User ${openerId} has reached max open tickets for category ${categoryId}`,
        );
      }

      // 3. number = per-guild max + 1
      const maxNumRes = await tx
        .select({ maxNum: max(tickets.number) })
        .from(tickets)
        .where(inGuild(tickets, guildId));

      const nextNumber = (maxNumRes[0]?.maxNum ?? 0) + 1;

      // Insert ticket
      const [ticket] = await tx
        .insert(tickets)
        .values({
          guild_id: guildId,
          category_id: categoryId,
          number: nextNumber,
          status: 'open',
          opener_id: openerId,
          channel_id: channelId,
          answers: answers ?? null,
        })
        .returning();

      // 4. Inserts the opener into ticket_members (role opener)
      await tx.insert(ticketMembers).values({
        guild_id: guildId,
        ticket_id: ticket.id,
        user_id: openerId,
        role: 'opener',
      });

      return ticket;
    });
  };

  try {
    return await executeOpen();
  } catch (err: any) {
    if (err?.code === '23505' || err?.cause?.code === '23505') {
      return await executeOpen();
    }
    throw err;
  }
}

export async function getTicket(db: TicketsDb, guildId: string, id: string) {
  const rows = await db
    .select()
    .from(tickets)
    .where(and(eq(tickets.id, id), inGuild(tickets, guildId)))
    .limit(1);

  if (rows.length === 0) {
    throw new TicketError('not_found', `Ticket ${id} not found in guild ${guildId}`);
  }
  return rows[0];
}

export async function getTicketByChannel(db: TicketsDb, guildId: string, channelId: string) {
  const rows = await db
    .select()
    .from(tickets)
    .where(and(eq(tickets.channel_id, channelId), inGuild(tickets, guildId)))
    .limit(1);

  if (rows.length === 0) {
    throw new TicketError(
      'not_found',
      `Ticket with channel ${channelId} not found in guild ${guildId}`,
    );
  }
  return rows[0];
}

export interface ListTicketsOptions {
  status?: TicketStatus;
  limit?: number;
  before?: Date | string;
}

export async function listTickets(
  db: TicketsDb,
  guildId: string,
  opts: ListTicketsOptions = {},
) {
  const conditions = [inGuild(tickets, guildId)];

  if (opts.status) {
    conditions.push(eq(tickets.status, opts.status));
  }

  if (opts.before) {
    let beforeDate: Date | undefined;
    if (opts.before instanceof Date) {
      beforeDate = opts.before;
    } else if (typeof opts.before === 'string') {
      const d = new Date(opts.before);
      if (!isNaN(d.getTime())) {
        beforeDate = d;
      } else {
        const [refTicket] = await db
          .select({ created_at: tickets.created_at })
          .from(tickets)
          .where(and(eq(tickets.id, opts.before), inGuild(tickets, guildId)))
          .limit(1);
        if (refTicket) {
          beforeDate = refTicket.created_at;
        }
      }
    }
    if (beforeDate) {
      conditions.push(lt(tickets.created_at, beforeDate));
    }
  }

  const lim = opts.limit ?? 50;

  return await db
    .select()
    .from(tickets)
    .where(and(...conditions))
    .orderBy(desc(tickets.created_at), desc(tickets.number))
    .limit(lim);
}

export async function transitionTicket(
  db: TicketsDb,
  guildId: string,
  id: string,
  t: Transition,
  actorId: string,
  targetId?: string,
  reason?: string,
) {
  return await db.transaction(async (tx) => {
    const rows = await tx
      .select()
      .from(tickets)
      .where(and(eq(tickets.id, id), inGuild(tickets, guildId)))
      .for('update')
      .limit(1);

    if (rows.length === 0) {
      throw new TicketError('not_found', `Ticket ${id} not found in guild ${guildId}`);
    }
    const cur = rows[0];

    const next = nextState(
      { status: cur.status, claimerId: cur.claimer_id },
      t,
      actorId,
      targetId,
    );
    if (!next.ok) {
      throw new TicketError(next.reason);
    }

    const updateSet: Record<string, any> = {
      status: next.status,
      claimer_id: next.claimerId,
      last_activity_at: new Date(),
    };

    if (t === 'close') {
      updateSet.closed_at = new Date();
      updateSet.close_reason = reason ?? null;
    } else if (t === 'reopen') {
      updateSet.reopened_count = cur.reopened_count + 1;
      updateSet.closed_at = null;
      updateSet.close_reason = null;
    }

    const [updated] = await tx
      .update(tickets)
      .set(updateSet)
      .where(and(eq(tickets.id, id), inGuild(tickets, guildId)))
      .returning();

    // Writes an audit_log row
    await tx.insert(auditLog).values({
      guild_id: guildId,
      actor_id: actorId,
      kind: `ticket.${t}`,
      target: id,
      detail: {
        from_status: cur.status,
        to_status: next.status,
        target_id: targetId ?? null,
        reason: reason ?? null,
      },
    });

    return updated;
  });
}
