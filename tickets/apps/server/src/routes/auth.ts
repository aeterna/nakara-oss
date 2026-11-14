import type { FastifyInstance, FastifyReply } from 'fastify';

const stub = (op: string) => async (_: unknown, reply: FastifyReply) =>
  reply.code(501).send({ code: 'not_implemented', message: op });

export default async function (app: FastifyInstance) {
  app.get('/auth/login', stub('getAuthLogin'));
  app.get('/auth/callback', stub('getAuthCallback'));
  app.post('/auth/logout', stub('postAuthLogout'));
}
