import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { eq, and, sql } from 'drizzle-orm';
import { gameActions, tickets, categories, gameServers, inGuild } from '@nakara-tickets/db';

function formatAction(r: typeof gameActions.$inferSelect) {
  return {
    id: r.id,
    ticketId: r.ticket_id,
    serverId: r.server_id,
    action: r.action,
    params: r.params ?? {},
    status: r.status,
    requestedBy: r.requested_by,
    result: r.result ?? null,
    createdAt: r.created_at.toISOString(),
    expiresAt: r.expires_at.toISOString(),
  };
}

export default async function (app: FastifyInstance) {
  const requireStaffAuth = async (req: FastifyRequest, reply: FastifyReply) => {
    if (app.requireStaff) {
      return app.requireStaff(req, reply);
    }
  };

  // GET /api/v1/guilds/:guildId/tickets/:ticketId/actions
  app.get(
    '/api/v1/guilds/:guildId/tickets/:ticketId/actions',
    { preHandler: [requireStaffAuth] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      if (!app.db) {
        return reply.code(501).send({ code: 'not_implemented', message: 'getTicketActions' });
      }

      const { guildId, ticketId } = req.params as { guildId: string; ticketId: string };

      const rows = await app.db
        .select()
        .from(gameActions)
        .where(and(inGuild(gameActions, guildId), eq(gameActions.ticket_id, ticketId)))
        .orderBy(sql`${gameActions.created_at} DESC`);

      return reply.code(200).send(rows.map(formatAction));
    }
  );

  // POST /api/v1/guilds/:guildId/tickets/:ticketId/actions
  app.post(
    '/api/v1/guilds/:guildId/tickets/:ticketId/actions',
    { preHandler: [requireStaffAuth] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      if (!app.db) {
        return reply.code(501).send({ code: 'not_implemented', message: 'postTicketAction' });
      }

      const { guildId, ticketId } = req.params as { guildId: string; ticketId: string };
      const body = (req.body ?? {}) as any;

      if (!body.action || typeof body.action !== 'string') {
        return reply.code(400).send({ code: 'invalid', message: 'action is required' });
      }

      const [ticket] = await app.db
        .select()
        .from(tickets)
        .where(and(eq(tickets.id, ticketId), inGuild(tickets, guildId)));

      if (!ticket) {
        return reply.code(404).send({ code: 'not_found', message: 'ticket not found' });
      }

      const [category] = await app.db
        .select()
        .from(categories)
        .where(and(eq(categories.id, ticket.category_id), inGuild(categories, guildId)));

      if (!category || !category.game_server_id) {
        return reply.code(422).send({
          code: 'unprocessable_entity',
          message: 'category has no linked game server',
        });
      }

      const [server] = await app.db
        .select()
        .from(gameServers)
        .where(
          and(
            eq(gameServers.id, category.game_server_id),
            inGuild(gameServers, guildId),
            eq(gameServers.revoked, false)
          )
        );

      if (!server) {
        return reply.code(422).send({
          code: 'unprocessable_entity',
          message: 'linked game server not found or revoked',
        });
      }

      const now = new Date();
      const expiresAt = new Date(now.getTime() + 60 * 1000);

      const [queued] = await app.db
        .insert(gameActions)
        .values({
          guild_id: guildId,
          ticket_id: ticketId,
          server_id: server.id,
          action: String(body.action).trim(),
          params: body.params ?? {},
          status: 'queued',
          requested_by: (req as any).user?.id ?? 'staff',
          expires_at: expiresAt,
        })
        .returning();

      return reply.code(202).send(formatAction(queued));
    }
  );
}
