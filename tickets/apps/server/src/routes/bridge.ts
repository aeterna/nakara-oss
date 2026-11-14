import type { FastifyInstance, FastifyReply } from 'fastify';

const stub = (op: string) => async (_: unknown, reply: FastifyReply) =>
  reply.code(501).send({ code: 'not_implemented', message: op });

export default async function (app: FastifyInstance) {
  app.post('/bridge/v1/pair', stub('postBridgePair'));
  app.post('/bridge/v1/heartbeat', stub('postBridgeHeartbeat'));
  app.get('/bridge/v1/actions', stub('getBridgeActions'));
  app.post('/bridge/v1/actions/:actionId/result', stub('postBridgeActionsResult'));
}
