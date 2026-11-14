import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import {
  listCategories,
  createCategory,
  updateCategory,
  deleteCategory,
  TicketError,
  type TicketsDb,
} from '@nakara-tickets/db';

const snowflakeRegex = /^[0-9]{17,20}$/;

const formFieldSchema = z.object({
  id: z.string().regex(/^[a-z0-9_]{1,32}$/),
  label: z.string().min(1).max(45),
  style: z.enum(['short', 'paragraph']),
  required: z.boolean(),
  placeholder: z.string().max(100).optional(),
  maxLength: z.number().int().min(1).max(4000).optional(),
});

const categoryInputSchema = z.object({
  name: z.string().min(1).max(64),
  emoji: z.string().max(64).nullable().optional(),
  staffRoleIds: z.array(z.string().regex(snowflakeRegex)).max(25),
  mode: z.enum(['thread', 'channel']).default('thread'),
  parentChannelId: z.string().regex(snowflakeRegex),
  nameTemplate: z.string().max(64).default('ticket-{number}'),
  welcomeMessage: z.string().max(2000).optional(),
  form: z.array(formFieldSchema).max(5).optional(),
  autoCloseHours: z.number().int().min(1).max(720).nullable().optional(),
  maxOpenPerUser: z.number().int().min(1).max(10).default(1),
  gameServerId: z.string().uuid().nullable().optional(),
});

export default async function (app: FastifyInstance) {
  const requireStaff = async (req: FastifyRequest, reply: FastifyReply) => {
    if (typeof app.requireStaff !== 'function') {
      reply.code(500).send({ code: 'misconfigured', message: 'Staff auth misconfigured' });
      return;
    }
    await app.requireStaff(req, reply);
  };

  app.get(
    '/api/v1/guilds/:guildId/categories',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const cats = await listCategories(db, req.guildId);
      return reply.send(cats);
    }
  );

  app.post(
    '/api/v1/guilds/:guildId/categories',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const parsed = categoryInputSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          code: 'invalid',
          message: parsed.error.issues.map((i) => i.message).join('; '),
        });
      }

      const created = await createCategory(db, req.guildId, parsed.data);
      return reply.code(201).send(created);
    }
  );

  app.put(
    '/api/v1/guilds/:guildId/categories/:categoryId',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const { categoryId } = req.params as { categoryId: string };
      const parsed = categoryInputSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          code: 'invalid',
          message: parsed.error.issues.map((i) => i.message).join('; '),
        });
      }

      try {
        const updated = await updateCategory(db, req.guildId, categoryId, parsed.data);
        return reply.send(updated);
      } catch (err: any) {
        if (
          (err instanceof TicketError || err?.name === 'TicketError') &&
          err.code === 'not_found'
        ) {
          return reply.code(404).send({ code: 'not_found', message: 'Category not found' });
        }
        throw err;
      }
    }
  );

  app.delete(
    '/api/v1/guilds/:guildId/categories/:categoryId',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const { categoryId } = req.params as { categoryId: string };

      try {
        await deleteCategory(db, req.guildId, categoryId);
        return reply.code(204).send();
      } catch (err: any) {
        if (err instanceof TicketError || err?.name === 'TicketError') {
          if (err.code === 'not_found') {
            return reply.code(404).send({ code: 'not_found', message: 'Category not found' });
          }
          if (err.code === 'limit') {
            return reply.code(409).send({
              code: 'conflict',
              message: 'Category cannot be deleted while referenced by tickets',
            });
          }
        }
        throw err;
      }
    }
  );
}
