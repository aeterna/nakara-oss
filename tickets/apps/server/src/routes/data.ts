import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { deleteUserData, exportGuild } from '../privacy.js';

export default async function (app: FastifyInstance) {
  app.delete(
    '/api/v1/me/data',
    {
      preHandler: async (req: FastifyRequest, reply: FastifyReply) => {
        await app.requireUser(req, reply);
      },
    },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = app.db;
      if (!db) {
        return reply.code(500).send({ code: 'server_error', message: 'Database handle not configured' });
      }

      const storage = (app as any).storage ?? null;
      const counts = await deleteUserData(db, storage, null, req.user.id);

      return reply.code(200).send({
        ok: true,
        kind: 'delete_user',
        status: 'done',
        createdAt: new Date().toISOString(),
        counts,
        messages: counts.messages,
        attachments: counts.attachments,
        ratings: counts.ratings,
        tickets: counts.tickets,
      });
    },
  );

  app.get(
    '/api/v1/guilds/:guildId/export',
    {
      preHandler: async (req: FastifyRequest, reply: FastifyReply) => {
        await app.requireStaff(req, reply);
      },
    },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = app.db;
      if (!db) {
        return reply.code(500).send({ code: 'server_error', message: 'Database handle not configured' });
      }

      const guildId = req.guildId;
      const dataKey = req.server.config?.TICKETS_DATA_KEY;
      if (!dataKey) {
        return reply.code(500).send({ code: 'server_error', message: 'Data key not configured' });
      }

      const exportedData = await exportGuild(db, dataKey, guildId);

      return reply
        .header('Content-Disposition', `attachment; filename="nakara-tickets-${guildId}.json"`)
        .header('Content-Type', 'application/json')
        .send(exportedData);
    },
  );
}
