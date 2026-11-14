import type { FastifyInstance, FastifyReply } from 'fastify';

const stub = (op: string) => async (_: unknown, reply: FastifyReply) =>
  reply.code(501).send({ code: 'not_implemented', message: op });

export default async function (app: FastifyInstance) {
  app.get('/api/v1/guilds/:guildId/tickets', stub('getTickets'));
  app.get('/api/v1/guilds/:guildId/tickets/:ticketId', stub('getTicket'));
  app.get('/api/v1/guilds/:guildId/tickets/:ticketId/messages', stub('getTicketMessages'));
  app.get('/api/v1/guilds/:guildId/tickets/:ticketId/transcript', stub('getTicketTranscript'));
  app.post('/api/v1/guilds/:guildId/tickets/:ticketId/:transition', stub('postTicketTransition'));
  app.get('/api/v1/guilds/:guildId/attachments/:attachmentId', stub('getAttachment'));
}
