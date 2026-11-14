import { and, eq, asc } from 'drizzle-orm';
import type { TicketsDb } from '../index.js';
import { messages, tickets } from '../schema.js';
import { inGuild } from '../index.js';
import { TicketError } from './errors.js';
import { sealBytes, openBytes } from '@nakara-tickets/core';

export interface AppendMessageInput {
  guildId: string;
  ticketId: string;
  id: string;
  authorId: string;
  authorName: string;
  isStaff?: boolean;
  isSystem?: boolean;
  content: string;
}

export async function appendMessage(
  db: TicketsDb,
  key: Buffer,
  input: AppendMessageInput,
) {
  return await db.transaction(async (tx) => {
    const [ticket] = await tx
      .select()
      .from(tickets)
      .where(and(eq(tickets.id, input.ticketId), inGuild(tickets, input.guildId)))
      .limit(1);

    if (!ticket) {
      throw new TicketError('not_found', `Ticket ${input.ticketId} not found in guild ${input.guildId}`);
    }

    const contentBuffer = Buffer.from(input.content, 'utf8');
    const content_enc = sealBytes(key, contentBuffer);

    const [inserted] = await tx
      .insert(messages)
      .values({
        id: input.id,
        guild_id: input.guildId,
        ticket_id: input.ticketId,
        author_id: input.authorId,
        author_name: input.authorName,
        is_staff: input.isStaff ?? false,
        is_system: input.isSystem ?? false,
        content_enc,
      })
      .returning();

    const now = new Date();
    const ticketUpdates: Record<string, any> = {
      last_activity_at: now,
    };

    if (input.isStaff && !ticket.first_response_at) {
      ticketUpdates.first_response_at = now;
    }

    await tx
      .update(tickets)
      .set(ticketUpdates)
      .where(and(eq(tickets.id, input.ticketId), inGuild(tickets, input.guildId)));

    return inserted;
  });
}

export async function readMessages(
  db: TicketsDb,
  key: Buffer,
  guildId: string,
  ticketId: string,
) {
  const rows = await db
    .select()
    .from(messages)
    .where(and(eq(messages.ticket_id, ticketId), inGuild(messages, guildId)))
    .orderBy(asc(messages.created_at));

  return rows.map((row) => {
    const decryptedBuffer = openBytes(key, row.content_enc);
    return {
      ...row,
      content: decryptedBuffer.toString('utf8'),
    };
  });
}
