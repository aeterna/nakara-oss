import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { and, eq, desc } from 'drizzle-orm';
import { blocks, inGuild, type TicketsDb } from '@nakara-tickets/db';

const snowflakeRegex = /^[0-9]{17,20}$/;

const blockInputSchema = z
  .object({
    userId: z.string().regex(snowflakeRegex).optional(),
    user_id: z.string().regex(snowflakeRegex).optional(),
    reason: z.string().max(500).nullable().optional(),
    expiresAt: z.string().datetime().nullable().optional(),
    expires_at: z.string().datetime().nullable().optional(),
  })
  .refine((data) => data.userId !== undefined || data.user_id !== undefined, {
    message: 'userId must be provided as a valid snowflake',
  });

function toApiBlock(b: {
  id: string;
  user_id: string;
  reason: string | null;
  expires_at: Date | null;
  created_by: string;
  created_at: Date;
}) {
  const expiresIso = b.expires_at?.toISOString?.() ?? (b.expires_at ? new Date(b.expires_at).toISOString() : null);
  const createdIso = b.created_at?.toISOString?.() ?? (b.created_at ? new Date(b.created_at).toISOString() : new Date().toISOString());

  return {
    id: b.id,
    userId: b.user_id,
    user_id: b.user_id,
    reason: b.reason,
    expiresAt: expiresIso,
    expires_at: expiresIso,
    createdBy: b.created_by,
    created_by: b.created_by,
    createdAt: createdIso,
    created_at: createdIso,
  };
}

export default async function (app: FastifyInstance) {
  const requireStaff = async (req: FastifyRequest, reply: FastifyReply) => {
    if (typeof app.requireStaff !== 'function') {
      reply.code(500).send({ code: 'misconfigured', message: 'Staff auth misconfigured' });
      return;
    }
    await app.requireStaff(req, reply);
  };

  // GET /api/v1/guilds/:guildId/blocks
  app.get(
    '/api/v1/guilds/:guildId/blocks',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const guildId = (req.params as any)?.guildId ?? req.guildId;

      const blockRows = await db
        .select()
        .from(blocks)
        .where(inGuild(blocks, guildId))
        .orderBy(desc(blocks.created_at));

      return reply.send(blockRows.map(toApiBlock));
    }
  );

  // POST /api/v1/guilds/:guildId/blocks
  app.post(
    '/api/v1/guilds/:guildId/blocks',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const guildId = (req.params as any)?.guildId ?? req.guildId;

      const parsed = blockInputSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          code: 'invalid',
          message: parsed.error.issues.map((i) => i.message).join('; '),
        });
      }

      const targetUserId = parsed.data.userId ?? parsed.data.user_id!;
      const reason = parsed.data.reason ?? null;
      const expiresAtRaw = parsed.data.expiresAt ?? parsed.data.expires_at ?? null;
      const expiresAt = expiresAtRaw ? new Date(expiresAtRaw) : null;
      const actorId = req.user?.id ?? 'system';

      // Check duplicate per guild
      const existing = await db
        .select()
        .from(blocks)
        .where(and(inGuild(blocks, guildId), eq(blocks.user_id, targetUserId)))
        .limit(1);

      if (existing.length > 0) {
        return reply.code(409).send({
          code: 'conflict',
          message: `User ${targetUserId} is already blocked in guild`,
        });
      }

      try {
        const [inserted] = await db
          .insert(blocks)
          .values({
            guild_id: guildId,
            user_id: targetUserId,
            reason,
            created_by: actorId,
            expires_at: expiresAt,
          })
          .returning();

        return reply.code(201).send(toApiBlock(inserted));
      } catch (err: any) {
        if (err?.code === '23505' || err?.cause?.code === '23505') {
          return reply.code(409).send({
            code: 'conflict',
            message: `User ${targetUserId} is already blocked in guild`,
          });
        }
        throw err;
      }
    }
  );

  // DELETE /api/v1/guilds/:guildId/blocks/:userId
  app.delete(
    '/api/v1/guilds/:guildId/blocks/:userId',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const guildId = (req.params as any)?.guildId ?? req.guildId;
      const { userId } = req.params as { userId: string };

      if (!snowflakeRegex.test(userId)) {
        return reply.code(400).send({
          code: 'invalid',
          message: 'userId must be a valid snowflake',
        });
      }

      const deleted = await db
        .delete(blocks)
        .where(and(inGuild(blocks, guildId), eq(blocks.user_id, userId)))
        .returning();

      if (deleted.length === 0) {
        return reply.code(404).send({
          code: 'not_found',
          message: 'Block not found',
        });
      }

      return reply.code(204).send();
    }
  );
}
