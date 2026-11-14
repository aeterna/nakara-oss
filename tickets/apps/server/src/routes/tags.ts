import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { and, eq, ne, asc } from 'drizzle-orm';
import { tags, inGuild, type TicketsDb } from '@nakara-tickets/db';

const tagInputSchema = z
  .object({
    name: z.string().regex(/^[a-z0-9-]{1,32}$/),
    content: z.string().min(1).max(2000).optional(),
    body: z.string().min(1).max(2000).optional(),
  })
  .refine((data) => (data.content !== undefined && data.content.length > 0) || (data.body !== undefined && data.body.length > 0), {
    message: 'content or body must be provided (between 1 and 2000 characters)',
  });

function toApiTag(t: { id: string; name: string; body: string }) {
  return {
    id: t.id,
    name: t.name,
    content: t.body,
    body: t.body,
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

  // GET /api/v1/guilds/:guildId/tags
  app.get(
    '/api/v1/guilds/:guildId/tags',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const guildId = (req.params as any)?.guildId ?? req.guildId;

      const tagRows = await db
        .select()
        .from(tags)
        .where(inGuild(tags, guildId))
        .orderBy(asc(tags.name));

      return reply.send(tagRows.map(toApiTag));
    }
  );

  // POST /api/v1/guilds/:guildId/tags
  app.post(
    '/api/v1/guilds/:guildId/tags',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const guildId = (req.params as any)?.guildId ?? req.guildId;

      const parsed = tagInputSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          code: 'invalid',
          message: parsed.error.issues.map((i) => i.message).join('; '),
        });
      }

      const { name } = parsed.data;
      const tagContent = parsed.data.content ?? parsed.data.body!;

      // Check duplicate tag name in this guild
      const existing = await db
        .select()
        .from(tags)
        .where(and(inGuild(tags, guildId), eq(tags.name, name)))
        .limit(1);

      if (existing.length > 0) {
        return reply.code(409).send({
          code: 'conflict',
          message: `Tag with name "${name}" already exists in guild`,
        });
      }

      try {
        const [inserted] = await db
          .insert(tags)
          .values({
            guild_id: guildId,
            name,
            body: tagContent,
          })
          .returning();

        return reply.code(201).send(toApiTag(inserted));
      } catch (err: any) {
        if (err?.code === '23505' || err?.cause?.code === '23505') {
          return reply.code(409).send({
            code: 'conflict',
            message: `Tag with name "${name}" already exists in guild`,
          });
        }
        throw err;
      }
    }
  );

  // PUT /api/v1/guilds/:guildId/tags/:tagId
  app.put(
    '/api/v1/guilds/:guildId/tags/:tagId',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const guildId = (req.params as any)?.guildId ?? req.guildId;
      const { tagId } = req.params as { tagId: string };

      const parsed = tagInputSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          code: 'invalid',
          message: parsed.error.issues.map((i) => i.message).join('; '),
        });
      }

      const { name } = parsed.data;
      const tagContent = parsed.data.content ?? parsed.data.body!;

      const [existing] = await db
        .select()
        .from(tags)
        .where(and(inGuild(tags, guildId), eq(tags.id, tagId)))
        .limit(1);

      if (!existing) {
        return reply.code(404).send({
          code: 'not_found',
          message: 'Tag not found',
        });
      }

      // Check conflict if name changed
      if (existing.name !== name) {
        const conflict = await db
          .select()
          .from(tags)
          .where(and(inGuild(tags, guildId), eq(tags.name, name), ne(tags.id, tagId)))
          .limit(1);

        if (conflict.length > 0) {
          return reply.code(409).send({
            code: 'conflict',
            message: `Tag with name "${name}" already exists in guild`,
          });
        }
      }

      try {
        const [updated] = await db
          .update(tags)
          .set({
            name,
            body: tagContent,
          })
          .where(and(inGuild(tags, guildId), eq(tags.id, tagId)))
          .returning();

        return reply.send(toApiTag(updated));
      } catch (err: any) {
        if (err?.code === '23505' || err?.cause?.code === '23505') {
          return reply.code(409).send({
            code: 'conflict',
            message: `Tag with name "${name}" already exists in guild`,
          });
        }
        throw err;
      }
    }
  );

  // DELETE /api/v1/guilds/:guildId/tags/:tagId
  app.delete(
    '/api/v1/guilds/:guildId/tags/:tagId',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const guildId = (req.params as any)?.guildId ?? req.guildId;
      const { tagId } = req.params as { tagId: string };

      const deleted = await db
        .delete(tags)
        .where(and(inGuild(tags, guildId), eq(tags.id, tagId)))
        .returning();

      if (deleted.length === 0) {
        return reply.code(404).send({
          code: 'not_found',
          message: 'Tag not found',
        });
      }

      return reply.code(204).send();
    }
  );
}
