import type { FastifyInstance, FastifyReply } from 'fastify';

const stub = (op: string) => async (_: unknown, reply: FastifyReply) =>
  reply.code(501).send({ code: 'not_implemented', message: op });

export default async function (app: FastifyInstance) {
  app.get('/api/v1/guilds/:guildId/blocks', stub('getBlocks'));
  app.post('/api/v1/guilds/:guildId/blocks', stub('postBlocks'));
  app.delete('/api/v1/guilds/:guildId/blocks/:userId', stub('deleteBlock'));
}
