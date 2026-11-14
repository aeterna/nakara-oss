import type { FastifyReply, FastifyRequest } from 'fastify';

declare module 'fastify' {
  interface FastifyInstance {
    requireStaff: (req: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
}
