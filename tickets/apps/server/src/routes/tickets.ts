import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { and, eq, lt, desc } from 'drizzle-orm';
import {
  tickets,
  attachments,
  inGuild,
  readMessages,
  transitionTicket,
  TicketError,
  type TicketsDb,
} from '@nakara-tickets/db';
import type { Transition } from '@nakara-tickets/core';
import { createStorage } from '../storage.js';

function escapeHtml(str: string | null | undefined): string {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function formatTicket(t: any) {
  return {
    id: t.id,
    number: t.number,
    guildId: t.guild_id,
    categoryId: t.category_id,
    status: t.status,
    openerId: t.opener_id,
    claimerId: t.claimer_id ?? null,
    channelId: t.channel_id,
    answers: t.answers ?? undefined,
    firstResponseAt: t.first_response_at ? new Date(t.first_response_at).toISOString() : null,
    lastActivityAt: t.last_activity_at ? new Date(t.last_activity_at).toISOString() : null,
    closedAt: t.closed_at ? new Date(t.closed_at).toISOString() : null,
    closeReason: t.close_reason ?? null,
    reopenedCount: t.reopened_count ?? 0,
    player: null,
    createdAt: new Date(t.created_at).toISOString(),
  };
}

const transitionBodySchema = z.object({
  toUserId: z.string().regex(/^[0-9]{17,20}$/).optional(),
  reason: z.string().max(512).optional(),
}).optional();

export default async function (app: FastifyInstance) {
  const requireStaff = async (req: FastifyRequest, reply: FastifyReply) => {
    if (typeof app.requireStaff !== 'function') {
      reply.code(500).send({ code: 'misconfigured', message: 'Staff auth misconfigured' });
      return;
    }
    await app.requireStaff(req, reply);
  };

  // 1. GET /api/v1/guilds/:guildId/tickets
  app.get(
    '/api/v1/guilds/:guildId/tickets',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const query = req.query as Record<string, string | undefined>;

      const conditions = [inGuild(tickets, req.guildId)];

      if (query.status && ['open', 'claimed', 'closed'].includes(query.status)) {
        conditions.push(eq(tickets.status, query.status as any));
      }
      if (query.categoryId) {
        conditions.push(eq(tickets.category_id, query.categoryId));
      }
      if (query.openerId) {
        conditions.push(eq(tickets.opener_id, query.openerId));
      }
      if (query.claimerId) {
        conditions.push(eq(tickets.claimer_id, query.claimerId));
      }

      const searchParam = query.search ?? query.number ?? query.q;
      if (searchParam && /^\d+$/.test(searchParam)) {
        conditions.push(eq(tickets.number, Number(searchParam)));
      }

      if (query.cursor) {
        const cursorDate = new Date(query.cursor);
        if (!isNaN(cursorDate.getTime())) {
          conditions.push(lt(tickets.created_at, cursorDate));
        }
      }

      const limit = Math.min(Math.max(Number(query.limit) || 50, 1), 100);

      const rows = await db
        .select()
        .from(tickets)
        .where(and(...conditions))
        .orderBy(desc(tickets.created_at), desc(tickets.number))
        .limit(limit + 1);

      let next: string | null = null;
      if (rows.length > limit) {
        const lastItem = rows[limit - 1];
        next = new Date(lastItem.created_at).toISOString();
        rows.splice(limit);
      }

      return reply.send({
        items: rows.map(formatTicket),
        next,
      });
    }
  );

  // 2. GET /api/v1/guilds/:guildId/tickets/:ticketId
  app.get(
    '/api/v1/guilds/:guildId/tickets/:ticketId',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const { ticketId } = req.params as { ticketId: string };

      const [ticket] = await db
        .select()
        .from(tickets)
        .where(and(eq(tickets.id, ticketId), inGuild(tickets, req.guildId)))
        .limit(1);

      if (!ticket) {
        return reply.code(404).send({ code: 'not_found', message: 'Ticket not found' });
      }

      return reply.send(formatTicket(ticket));
    }
  );

  // 3. GET /api/v1/guilds/:guildId/tickets/:ticketId/messages
  app.get(
    '/api/v1/guilds/:guildId/tickets/:ticketId/messages',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const { ticketId } = req.params as { ticketId: string };

      const [ticket] = await db
        .select()
        .from(tickets)
        .where(and(eq(tickets.id, ticketId), inGuild(tickets, req.guildId)))
        .limit(1);

      if (!ticket) {
        return reply.code(404).send({ code: 'not_found', message: 'Ticket not found' });
      }

      const dataKey = req.server.config?.TICKETS_DATA_KEY;
      if (!dataKey) {
        return reply.code(500).send({ code: 'misconfigured', message: 'Data key not configured' });
      }

      const msgs = await readMessages(db, dataKey, req.guildId, ticketId);

      const attRows = await db
        .select()
        .from(attachments)
        .where(and(eq(attachments.ticket_id, ticketId), inGuild(attachments, req.guildId)));

      const attsByMsg = new Map<string, any[]>();
      for (const a of attRows) {
        const mId = a.message_id || '';
        if (!attsByMsg.has(mId)) {
          attsByMsg.set(mId, []);
        }
        attsByMsg.get(mId)!.push({
          id: a.id,
          filename: a.filename,
          contentType: a.content_type,
          size: a.size,
          sha256: a.sha256,
          stored: a.stored,
        });
      }

      const items = msgs.map((m) => ({
        id: m.id,
        authorId: m.author_id,
        authorName: m.author_name,
        isStaff: m.is_staff,
        isSystem: m.is_system,
        content: m.content,
        embeds: [],
        attachments: attsByMsg.get(m.id) || [],
        editedAt: m.edited_at ? new Date(m.edited_at).toISOString() : null,
        createdAt: new Date(m.created_at).toISOString(),
      }));

      return reply.send({
        items,
        next: null,
      });
    }
  );

  // 4. GET /api/v1/guilds/:guildId/tickets/:ticketId/transcript
  app.get(
    '/api/v1/guilds/:guildId/tickets/:ticketId/transcript',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const { ticketId } = req.params as { ticketId: string };

      const [ticket] = await db
        .select()
        .from(tickets)
        .where(and(eq(tickets.id, ticketId), inGuild(tickets, req.guildId)))
        .limit(1);

      if (!ticket) {
        return reply.code(404).send({ code: 'not_found', message: 'Ticket not found' });
      }

      const dataKey = req.server.config?.TICKETS_DATA_KEY;
      if (!dataKey) {
        return reply.code(500).send({ code: 'misconfigured', message: 'Data key not configured' });
      }

      const msgs = await readMessages(db, dataKey, req.guildId, ticketId);

      const attRows = await db
        .select()
        .from(attachments)
        .where(and(eq(attachments.ticket_id, ticketId), inGuild(attachments, req.guildId)));

      const attsByMsg = new Map<string, any[]>();
      for (const a of attRows) {
        const mId = a.message_id || '';
        if (!attsByMsg.has(mId)) {
          attsByMsg.set(mId, []);
        }
        attsByMsg.get(mId)!.push(a);
      }

      let messagesHtml = '';
      for (const m of msgs) {
        const msgAtts = attsByMsg.get(m.id) || [];
        let attLinksHtml = '';
        if (msgAtts.length > 0) {
          const links = msgAtts
            .map((att) => {
              const url = `/api/v1/guilds/${encodeURIComponent(req.guildId)}/attachments/${encodeURIComponent(att.id)}`;
              return `<a href="${escapeHtml(url)}" target="_blank" rel="noopener noreferrer">${escapeHtml(att.filename)}</a> (${att.size} bytes)`;
            })
            .join(', ');
          attLinksHtml = `<div class="attachments">Attachments: ${links}</div>`;
        }

        const staffBadge = m.is_staff ? '<span class="badge staff">STAFF</span> ' : '';
        const systemBadge = m.is_system ? '<span class="badge system">SYSTEM</span> ' : '';
        const timeStr = escapeHtml(new Date(m.created_at).toISOString());

        messagesHtml += `
        <div class="message">
          <div class="header">
            ${staffBadge}${systemBadge}<strong>${escapeHtml(m.author_name)}</strong>
            <span class="timestamp">${timeStr}</span>
          </div>
          <div class="content">${escapeHtml(m.content)}</div>
          ${attLinksHtml}
        </div>`;
      }

      const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Ticket #${ticket.number} Transcript</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #0f172a; color: #f8fafc; margin: 0; padding: 2rem; }
    .container { max-width: 800px; margin: 0 auto; background: #1e293b; border-radius: 8px; padding: 1.5rem; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3); }
    h1 { margin-top: 0; font-size: 1.5rem; border-bottom: 1px solid #334155; padding-bottom: 0.75rem; color: #38bdf8; }
    .meta { color: #94a3b8; font-size: 0.875rem; margin-bottom: 1.5rem; }
    .message { border-bottom: 1px solid #334155; padding: 0.75rem 0; }
    .message:last-child { border-bottom: none; }
    .header { margin-bottom: 0.25rem; font-size: 0.875rem; }
    .timestamp { color: #64748b; margin-left: 0.5rem; font-size: 0.75rem; }
    .badge { font-size: 0.65rem; padding: 2px 6px; border-radius: 4px; font-weight: bold; }
    .badge.staff { background: #0284c7; color: white; }
    .badge.system { background: #475569; color: white; }
    .content { white-space: pre-wrap; word-break: break-word; line-height: 1.5; color: #e2e8f0; }
    .attachments { margin-top: 0.5rem; font-size: 0.8125rem; color: #38bdf8; }
    .attachments a { color: #38bdf8; text-decoration: underline; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Ticket #${ticket.number} Transcript</h1>
    <div class="meta">
      <div>Status: ${escapeHtml(ticket.status)} | Created: ${escapeHtml(new Date(ticket.created_at).toISOString())}</div>
      ${ticket.close_reason ? `<div>Close Reason: ${escapeHtml(ticket.close_reason)}</div>` : ''}
    </div>
    <div class="messages">
      ${messagesHtml}
    </div>
  </div>
</body>
</html>`;

      reply.header('Content-Type', 'text/html; charset=utf-8');
      reply.header('Content-Disposition', `attachment; filename="ticket-${ticket.number}.html"`);
      reply.header(
        'Content-Security-Policy',
        "default-src 'none'; style-src 'unsafe-inline'; img-src data:"
      );
      reply.header('X-Content-Type-Options', 'nosniff');

      return reply.send(html);
    }
  );

  // 5. POST /api/v1/guilds/:guildId/tickets/:ticketId/:transition
  app.post(
    '/api/v1/guilds/:guildId/tickets/:ticketId/:transition',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const { ticketId, transition } = req.params as { ticketId: string; transition: string };

      const validTransitions = ['claim', 'unclaim', 'transfer', 'close', 'reopen'];
      if (!validTransitions.includes(transition)) {
        return reply.code(400).send({ code: 'invalid', message: `Unknown transition: ${transition}` });
      }

      const parsed = transitionBodySchema.safeParse(req.body);
      const body = parsed.success ? parsed.data : undefined;

      try {
        const updated = await transitionTicket(
          db,
          req.guildId,
          ticketId,
          transition as Transition,
          req.user.id,
          body?.toUserId,
          body?.reason
        );

        // If app.discord is available, post system message
        if (app.discord && updated.channel_id) {
          const actionText = `Ticket #${updated.number} ${transition}ed by <@${req.user.id}>`;
          await app.discord.sendMessage(updated.channel_id, { content: actionText }).catch(() => {});
        }

        return reply.send(formatTicket(updated));
      } catch (err: any) {
        if (err instanceof TicketError || err?.name === 'TicketError') {
          if (err.code === 'not_found') {
            return reply.code(404).send({ code: 'not_found', message: err.message });
          }
          return reply.code(409).send({ code: err.code, message: err.message });
        }
        throw err;
      }
    }
  );

  // 6. GET /api/v1/guilds/:guildId/attachments/:attachmentId
  app.get(
    '/api/v1/guilds/:guildId/attachments/:attachmentId',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const { attachmentId } = req.params as { attachmentId: string };

      const [row] = await db
        .select()
        .from(attachments)
        .where(and(eq(attachments.id, attachmentId), inGuild(attachments, req.guildId)))
        .limit(1);

      if (!row || !row.stored || !row.storage_key) {
        return reply.code(404).send({ code: 'not_found', message: 'Attachment not found' });
      }

      const storage = createStorage(req.server.config);
      const file = await storage.get(row.storage_key);

      if (!file) {
        return reply.code(404).send({ code: 'not_found', message: 'Attachment file not found' });
      }

      let contentType = row.content_type || file.contentType || 'application/octet-stream';
      if (
        contentType.toLowerCase().includes('text/html') ||
        contentType.toLowerCase().includes('application/xhtml+xml')
      ) {
        contentType = 'application/octet-stream';
      }

      reply.header('Content-Type', contentType);
      reply.header('Content-Disposition', `attachment; filename="${encodeURIComponent(row.filename)}"`);
      reply.header('X-Content-Type-Options', 'nosniff');

      return reply.send(file.bytes);
    }
  );
}
