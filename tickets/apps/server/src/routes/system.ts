import type { FastifyInstance, FastifyReply } from 'fastify';
import pkg from '../../package.json' with { type: 'json' };

const stub = (op: string) => async (_: unknown, reply: FastifyReply) =>
  reply.code(501).send({ code: 'not_implemented', message: op });

export default async function (app: FastifyInstance) {
  app.get('/healthz', async () => ({ ok: true, db: 'down', gateway: 'standby', version: pkg.version }));
  app.get('/metrics', stub('getMetrics'));
}
