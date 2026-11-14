import type { FastifyInstance, FastifyReply } from 'fastify';

const stub = (op: string) => async (_: unknown, reply: FastifyReply) =>
  reply.code(501).send({ code: 'not_implemented', message: op });

export default async function (app: FastifyInstance) {
  app.get('/api/v1/guilds/:guildId/categories', stub('getCategories'));
  app.post('/api/v1/guilds/:guildId/categories', stub('postCategories'));
  app.put('/api/v1/guilds/:guildId/categories/:categoryId', stub('putCategory'));
  app.delete('/api/v1/guilds/:guildId/categories/:categoryId', stub('deleteCategory'));
}
