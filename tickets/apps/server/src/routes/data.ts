import type { FastifyInstance, FastifyReply } from 'fastify';

const stub = (op: string) => async (_: unknown, reply: FastifyReply) =>
  reply.code(501).send({ code: 'not_implemented', message: op });

export default async function (app: FastifyInstance) {
  app.delete('/api/v1/me/data', stub('deleteMeData'));
  app.get('/api/v1/guilds/:guildId/export', stub('getExport'));
}
