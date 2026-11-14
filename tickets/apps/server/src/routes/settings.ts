import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { getSettings, updateSettings, TicketError, type TicketsDb } from '@nakara-tickets/db';

const snowflakeRegex = /^[0-9]{17,20}$/;

const guildSettingsSchema = z.object({
  locale: z.enum(['th', 'en']),
  retentionDays: z.number().int().min(1).max(3650).default(90),
  logChannelId: z.string().regex(snowflakeRegex).nullable(),
  ratingDm: z.boolean().default(false),
  privacyPolicyUrl: z.string().url().nullable().optional(),
});

export default async function (app: FastifyInstance) {
  const requireStaff = (req: FastifyRequest, reply: FastifyReply) => {
    if (typeof app.requireStaff !== 'function') {
      return reply.code(500).send({ code: 'misconfigured', message: 'Staff auth misconfigured' });
    }
    return app.requireStaff(req, reply);
  };

  app.get(
    '/api/v1/guilds/:guildId/settings',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      try {
        const s = await getSettings(db, req.guildId);
        return reply.send(s);
      } catch (err: any) {
        if (
          (err instanceof TicketError || err?.name === 'TicketError') &&
          err.code === 'not_found'
        ) {
          return reply.code(404).send({ code: 'not_found', message: 'Settings not found' });
        }
        throw err;
      }
    }
  );

  app.put(
    '/api/v1/guilds/:guildId/settings',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const parsed = guildSettingsSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          code: 'invalid',
          message: parsed.error.issues.map((i) => i.message).join('; '),
        });
      }

      try {
        const updated = await updateSettings(db, req.guildId, parsed.data);
        return reply.send(updated);
      } catch (err: any) {
        if (
          (err instanceof TicketError || err?.name === 'TicketError') &&
          err.code === 'not_found'
        ) {
          return reply.code(404).send({ code: 'not_found', message: 'Settings not found' });
        }
        throw err;
      }
    }
  );
}
