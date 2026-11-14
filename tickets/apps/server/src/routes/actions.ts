import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { eq, and, sql } from 'drizzle-orm';
import { gameActions, tickets, categories, gameServers, auditLog, inGuild } from '@nakara-tickets/db';
import '../bridge/staff-types.js';

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

const ACTION_NAME_PATTERN = /^[a-z0-9_.]{1,64}$/;

export default async function (app: FastifyInstance) {
  const requireStaffAuth = async (req: FastifyRequest, reply: FastifyReply) => {
    if (typeof app.requireStaff !== 'function') {
      reply.code(500).send({ code: 'misconfigured', message: 'Staff authentication not configured' });
      return;
    }
    await app.requireStaff(req, reply);
  };

  // GET /api/v1/guilds/:guildId/tickets/:ticketId/actions
  app.get(
    '/api/v1/guilds/:guildId/tickets/:ticketId/actions',
    { preHandler: [requireStaffAuth] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      if (!app.db) {
        return reply.code(501).send({ code: 'not_implemented', message: 'getTicketActions' });
      }

      const guildId = req.guildId ?? (req.params as any).guildId;
      const { ticketId } = req.params as { ticketId: string };

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

      const guildId = req.guildId ?? (req.params as any).guildId;
      const { ticketId } = req.params as { ticketId: string };
      const body = (req.body ?? {}) as any;

      if (!body.action || typeof body.action !== 'string') {
        return reply.code(400).send({ code: 'invalid', message: 'action is required' });
      }

      const actionName = body.action.trim();
      if (!ACTION_NAME_PATTERN.test(actionName)) {
        return reply.code(400).send({ code: 'invalid', message: 'action name pattern invalid' });
      }

      const params = body.params ?? {};
      if (typeof params !== 'object' || Array.isArray(params) || params === null) {
        return reply.code(400).send({ code: 'invalid', message: 'params must be an object' });
      }

      if (Object.keys(params).length > 16) {
        return reply.code(400).send({ code: 'invalid', message: 'params cannot exceed 16 keys' });
      }

      // Validate known actions
      if (actionName === 'player.teleport') {
        if (typeof params.spot !== 'string' || !params.spot.trim()) {
          return reply.code(400).send({ code: 'invalid', message: 'player.teleport requires params.spot string' });
        }
      } else if (actionName === 'player.give_item') {
        if (
          typeof params.item !== 'string' ||
          !params.item.trim() ||
          typeof params.count !== 'number' ||
          !Number.isInteger(params.count) ||
          params.count < 1
        ) {
          return reply.code(400).send({
            code: 'invalid',
            message: 'player.give_item requires params.item string and params.count positive integer',
          });
        }
      } else if (actionName === 'player.revive' || actionName === 'player.info') {
        // Known built-in action with optional/no mandatory params
      }

      const [ticket] = await app.db
        .select()
        .from(tickets)
        .where(and(eq(tickets.id, ticketId), inGuild(tickets, guildId)));

      if (!ticket) {
        return reply.code(404).send({ code: 'not_found', message: 'ticket not found' });
      }

      // Check repeat-confirm for give_item: within 10 minutes with same ticket, item, and confirmRepeat !== true
      if (actionName === 'player.give_item' && body.confirmRepeat !== true) {
        const tenMinutesAgo = new Date(Date.now() - 10 * 60 * 1000);
        const recentGiveItems = await app.db
          .select()
          .from(gameActions)
          .where(
            and(
              inGuild(gameActions, guildId),
              eq(gameActions.ticket_id, ticketId),
              eq(gameActions.action, 'player.give_item'),
              sql`${gameActions.created_at} >= ${tenMinutesAgo}`
            )
          );

        const hasMatchingItem = recentGiveItems.some(
          (a) => (a.params as any)?.item === params.item
        );

        if (hasMatchingItem) {
          return reply.code(409).send({
            code: 'repeat_confirm',
            message: 'A matching give_item exists in the last 10 minutes; please confirm to repeat',
          });
        }
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
      const requestedBy = (req as any).user?.id ?? 'staff';

      const [queued] = await app.db
        .insert(gameActions)
        .values({
          guild_id: guildId,
          ticket_id: ticketId,
          server_id: server.id,
          action: actionName,
          params,
          status: 'queued',
          requested_by: requestedBy,
          expires_at: expiresAt,
        })
        .returning();

      await app.db.insert(auditLog).values({
        guild_id: guildId,
        actor_id: requestedBy,
        kind: 'action.queue',
        target: queued.id,
        detail: {
          ticketId,
          action: queued.action,
          params: queued.params,
        },
      });

      return reply.code(202).send(formatAction(queued));
    }
  );
}
