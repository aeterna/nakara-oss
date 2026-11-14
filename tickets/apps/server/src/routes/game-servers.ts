import type { FastifyInstance, FastifyReply } from 'fastify';

const stub = (op: string) => async (_: unknown, reply: FastifyReply) =>
  reply.code(501).send({ code: 'not_implemented', message: op });

export default async function (app: FastifyInstance) {
  app.get('/api/v1/guilds/:guildId/game-servers', stub('getGameServers'));
  app.post('/api/v1/guilds/:guildId/game-servers/pair-codes', stub('postGameServersPairCodes'));
  app.patch('/api/v1/guilds/:guildId/game-servers/:serverId', stub('patchGameServer'));
  app.delete('/api/v1/guilds/:guildId/game-servers/:serverId', stub('deleteGameServer'));
}
