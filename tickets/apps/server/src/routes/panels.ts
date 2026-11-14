import type { FastifyInstance, FastifyReply } from 'fastify';

const stub = (op: string) => async (_: unknown, reply: FastifyReply) =>
  reply.code(501).send({ code: 'not_implemented', message: op });

export default async function (app: FastifyInstance) {
  app.get('/api/v1/guilds/:guildId/panels', stub('getPanels'));
  app.post('/api/v1/guilds/:guildId/panels', stub('postPanels'));
  app.put('/api/v1/guilds/:guildId/panels/:panelId', stub('putPanel'));
  app.delete('/api/v1/guilds/:guildId/panels/:panelId', stub('deletePanel'));
  app.post('/api/v1/guilds/:guildId/panels/:panelId/send', stub('postPanelSend'));
}
