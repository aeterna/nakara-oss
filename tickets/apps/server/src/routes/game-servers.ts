import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { createHash, randomBytes } from 'node:crypto';
import { eq, and, sql } from 'drizzle-orm';
import { gameServers, pairCodes, auditLog, inGuild } from '@nakara-tickets/db';

const CROCKFORD_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

function generateCrockfordCode(): string {
  const bytes = randomBytes(10);
  let code = '';
  for (let i = 0; i < 10; i++) {
    code += CROCKFORD_ALPHABET[bytes[i] % 32];
  }
  return code;
}

function sha256hex(str: string): string {
  return createHash('sha256').update(str).digest('hex');
}

function formatServer(r: typeof gameServers.$inferSelect) {
  return {
    id: r.id,
    name: r.name,
    confirmed: r.confirmed,
    edition: r.edition ?? null,
    resourceVersion: r.resource_version ?? null,
    playersOnline: r.players_online ?? 0,
    lastSeenAt: r.last_seen_at ? r.last_seen_at.toISOString() : null,
    revoked: r.revoked,
  };
}

export default async function (app: FastifyInstance) {
  const requireStaffAuth = async (req: FastifyRequest, reply: FastifyReply) => {
    if (app.requireStaff) {
      return app.requireStaff(req, reply);
    }
  };

  // GET /api/v1/guilds/:guildId/game-servers
  app.get(
    '/api/v1/guilds/:guildId/game-servers',
    { preHandler: [requireStaffAuth] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      if (!app.db) {
        return reply.code(501).send({ code: 'not_implemented', message: 'getGameServers' });
      }

      const { guildId } = req.params as { guildId: string };
      const rows = await app.db
        .select()
        .from(gameServers)
        .where(inGuild(gameServers, guildId))
        .orderBy(sql`${gameServers.created_at} DESC`);

      return reply.code(200).send(rows.map(formatServer));
    }
  );

  // POST /api/v1/guilds/:guildId/game-servers/pair-codes
  app.post(
    '/api/v1/guilds/:guildId/game-servers/pair-codes',
    { preHandler: [requireStaffAuth] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      if (!app.db) {
        return reply.code(501).send({ code: 'not_implemented', message: 'postGameServersPairCodes' });
      }

      const { guildId } = req.params as { guildId: string };
      const code = generateCrockfordCode();
      const codeHash = sha256hex(code);
      const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

      await app.db.insert(pairCodes).values({
        guild_id: guildId,
        code_hash: codeHash,
        expires_at: expiresAt,
      });

      return reply.code(201).send({
        code,
        expiresAt: expiresAt.toISOString(),
      });
    }
  );

  // PATCH /api/v1/guilds/:guildId/game-servers/:serverId
  app.patch(
    '/api/v1/guilds/:guildId/game-servers/:serverId',
    { preHandler: [requireStaffAuth] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      if (!app.db) {
        return reply.code(501).send({ code: 'not_implemented', message: 'patchGameServer' });
      }

      const { guildId, serverId } = req.params as { guildId: string; serverId: string };
      const body = (req.body ?? {}) as any;

      const [server] = await app.db
        .select()
        .from(gameServers)
        .where(and(eq(gameServers.id, serverId), inGuild(gameServers, guildId)));

      if (!server) {
        return reply.code(404).send({ code: 'not_found', message: 'server not found' });
      }

      const updateData: any = {};
      if (typeof body.name === 'string' && body.name.trim().length > 0) {
        updateData.name = body.name.trim().slice(0, 64);
      }
      if (typeof body.confirmed === 'boolean') {
        updateData.confirmed = body.confirmed;
      }

      const [updated] = await app.db
        .update(gameServers)
        .set(updateData)
        .where(and(eq(gameServers.id, serverId), inGuild(gameServers, guildId)))
        .returning();

      return reply.code(200).send(formatServer(updated));
    }
  );

  // DELETE /api/v1/guilds/:guildId/game-servers/:serverId
  app.delete(
    '/api/v1/guilds/:guildId/game-servers/:serverId',
    { preHandler: [requireStaffAuth] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      if (!app.db) {
        return reply.code(501).send({ code: 'not_implemented', message: 'deleteGameServer' });
      }

      const { guildId, serverId } = req.params as { guildId: string; serverId: string };

      const [server] = await app.db
        .select()
        .from(gameServers)
        .where(and(eq(gameServers.id, serverId), inGuild(gameServers, guildId)));

      if (!server) {
        return reply.code(404).send({ code: 'not_found', message: 'server not found' });
      }

      await app.db
        .update(gameServers)
        .set({ revoked: true })
        .where(and(eq(gameServers.id, serverId), inGuild(gameServers, guildId)));

      await app.db.insert(auditLog).values({
        guild_id: guildId,
        actor_id: (req as any).user?.id ?? 'staff',
        kind: 'server.revoke',
        target: serverId,
        detail: { name: server.name },
      });

      return reply.code(204).send();
    }
  );
}
