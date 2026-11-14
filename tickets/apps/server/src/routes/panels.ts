import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { and, eq, asc, inArray } from 'drizzle-orm';
import { panels, categories, inGuild, type TicketsDb } from '@nakara-tickets/db';
import { buildPanelMessage } from '../panel-message.js';

const snowflakeRegex = /^[0-9]{17,20}$/;

const buttonSchema = z.object({
  categoryId: z.string().uuid().optional(),
  category_id: z.string().uuid().optional(),
  label: z.string().min(1).max(80),
  emoji: z.string().max(64).nullable().optional(),
  style: z.enum(['primary', 'secondary', 'success', 'danger']).default('primary'),
}).refine((b) => Boolean(b.categoryId || b.category_id), {
  message: 'categoryId is required',
});

const embedSchema = z.object({
  title: z.string().min(1).max(256),
  description: z.string().max(4096).nullable().optional(),
  color: z.number().int().min(0).max(16777215).nullable().optional(),
  imageUrl: z.string().url().refine((u) => u.startsWith('https://'), { message: 'Must be an https URL' }).nullable().optional().or(z.literal('')),
  image_url: z.string().url().refine((u) => u.startsWith('https://'), { message: 'Must be an https URL' }).nullable().optional().or(z.literal('')),
  footer: z.string().max(2048).nullable().optional(),
}).refine((e) => {
  const tLen = e.title?.length || 0;
  const dLen = e.description?.length || 0;
  const fLen = e.footer?.length || 0;
  return tLen + dLen + fLen <= 6000;
}, {
  message: 'Total embed characters cannot exceed 6000',
});

const panelInputSchema = z.object({
  channelId: z.string().regex(snowflakeRegex).optional(),
  channel_id: z.string().regex(snowflakeRegex).optional(),
  embed: embedSchema,
  kind: z.enum(['buttons', 'select']).default('buttons'),
  buttons: z.array(buttonSchema).min(1).max(25),
}).refine((p) => Boolean(p.channelId || p.channel_id), {
  message: 'channelId is required and must be a valid snowflake',
});

function normalizePanelInput(data: z.infer<typeof panelInputSchema>) {
  const channelId = (data.channelId ?? data.channel_id) as string;
  const imageUrlRaw = data.embed.imageUrl ?? data.embed.image_url ?? null;
  const imageUrl = imageUrlRaw && imageUrlRaw.trim() ? imageUrlRaw.trim() : null;

  return {
    channelId,
    embed: {
      title: data.embed.title,
      description: data.embed.description || null,
      color: data.embed.color ?? null,
      imageUrl,
      footer: data.embed.footer || null,
    },
    kind: data.kind,
    buttons: data.buttons.map((b) => ({
      categoryId: (b.categoryId ?? b.category_id) as string,
      label: b.label,
      emoji: b.emoji || null,
      style: b.style || 'primary',
    })),
  };
}

function toApiPanel(row: any) {
  const embed = row.embed || {};
  return {
    id: row.id,
    channelId: row.channel_id,
    messageId: row.message_id ?? null,
    embed: {
      title: embed.title,
      description: embed.description ?? null,
      color: embed.color ?? null,
      imageUrl: embed.imageUrl ?? embed.image_url ?? null,
      footer: embed.footer ?? null,
    },
    kind: row.kind,
    buttons: (row.buttons || []).map((b: any) => ({
      categoryId: b.categoryId ?? b.category_id,
      label: b.label,
      emoji: b.emoji ?? null,
      style: b.style ?? 'primary',
    })),
    createdAt: row.created_at?.toISOString?.() ?? (row.created_at as string),
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

  // GET /api/v1/guilds/:guildId/panels
  app.get(
    '/api/v1/guilds/:guildId/panels',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const rows = await db
        .select()
        .from(panels)
        .where(inGuild(panels, req.guildId))
        .orderBy(asc(panels.created_at));

      return reply.send(rows.map(toApiPanel));
    }
  );

  // POST /api/v1/guilds/:guildId/panels
  app.post(
    '/api/v1/guilds/:guildId/panels',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const parsed = panelInputSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          code: 'invalid',
          message: parsed.error.issues.map((i) => i.message).join('; '),
        });
      }

      const input = normalizePanelInput(parsed.data);

      // Verify every categoryId belongs to this guild
      const uniqueCatIds = Array.from(new Set(input.buttons.map((b) => b.categoryId)));
      const foundCats = await db
        .select({ id: categories.id })
        .from(categories)
        .where(and(inGuild(categories, req.guildId), inArray(categories.id, uniqueCatIds)));

      if (foundCats.length !== uniqueCatIds.length) {
        return reply.code(422).send({
          code: 'invalid_category',
          message: 'One or more categories do not belong to this guild',
        });
      }

      const [created] = await db
        .insert(panels)
        .values({
          guild_id: req.guildId,
          channel_id: input.channelId,
          message_id: null,
          embed: input.embed,
          kind: input.kind,
          buttons: input.buttons,
        })
        .returning();

      return reply.code(201).send(toApiPanel(created));
    }
  );

  // PUT /api/v1/guilds/:guildId/panels/:panelId
  app.put(
    '/api/v1/guilds/:guildId/panels/:panelId',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const { panelId } = req.params as { panelId: string };

      const existing = await db
        .select()
        .from(panels)
        .where(and(eq(panels.id, panelId), inGuild(panels, req.guildId)))
        .limit(1);

      if (existing.length === 0) {
        return reply.code(404).send({ code: 'not_found', message: 'Panel not found' });
      }

      const parsed = panelInputSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          code: 'invalid',
          message: parsed.error.issues.map((i) => i.message).join('; '),
        });
      }

      const input = normalizePanelInput(parsed.data);

      // Verify categories belong to this guild
      const uniqueCatIds = Array.from(new Set(input.buttons.map((b) => b.categoryId)));
      const foundCats = await db
        .select({ id: categories.id })
        .from(categories)
        .where(and(inGuild(categories, req.guildId), inArray(categories.id, uniqueCatIds)));

      if (foundCats.length !== uniqueCatIds.length) {
        return reply.code(422).send({
          code: 'invalid_category',
          message: 'One or more categories do not belong to this guild',
        });
      }

      const [updated] = await db
        .update(panels)
        .set({
          channel_id: input.channelId,
          embed: input.embed,
          kind: input.kind,
          buttons: input.buttons,
        })
        .where(and(eq(panels.id, panelId), inGuild(panels, req.guildId)))
        .returning();

      return reply.send(toApiPanel(updated));
    }
  );

  // DELETE /api/v1/guilds/:guildId/panels/:panelId
  app.delete(
    '/api/v1/guilds/:guildId/panels/:panelId',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const { panelId } = req.params as { panelId: string };

      const existing = await db
        .select()
        .from(panels)
        .where(and(eq(panels.id, panelId), inGuild(panels, req.guildId)))
        .limit(1);

      if (existing.length === 0) {
        return reply.code(404).send({ code: 'not_found', message: 'Panel not found' });
      }

      const panelRow = existing[0];

      // Remove Discord message if message_id exists (ignore 404)
      if (panelRow.message_id && app.discord) {
        try {
          await app.discord.deleteMessage(panelRow.channel_id, panelRow.message_id);
        } catch (err: any) {
          const status = err?.status ?? err?.statusCode;
          const code = String(err?.code || '');
          if (status !== 404 && code !== '10008' && code !== '404') {
            // non-404 error: we still proceed to delete the row as required by the contract
          }
        }
      }

      await db
        .delete(panels)
        .where(and(eq(panels.id, panelId), inGuild(panels, req.guildId)));

      return reply.code(204).send();
    }
  );

  // POST /api/v1/guilds/:guildId/panels/:panelId/send
  app.post(
    '/api/v1/guilds/:guildId/panels/:panelId/send',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      if (!app.discord) {
        return reply.code(503).send({
          code: 'discord_unavailable',
          message: 'Discord REST service unavailable',
        });
      }

      const db = req.server.db as TicketsDb;
      const { panelId } = req.params as { panelId: string };

      const existing = await db
        .select()
        .from(panels)
        .where(and(eq(panels.id, panelId), inGuild(panels, req.guildId)))
        .limit(1);

      if (existing.length === 0) {
        return reply.code(404).send({ code: 'not_found', message: 'Panel not found' });
      }

      const panelRow = existing[0];

      // Fetch categories to populate button labels/emojis if needed
      const guildCats = await db
        .select()
        .from(categories)
        .where(inGuild(categories, req.guildId));

      const discordMessage = buildPanelMessage(
        {
          embed: panelRow.embed as any,
          kind: panelRow.kind,
          buttons: panelRow.buttons as any,
        },
        guildCats
      );

      let sentMsg: any = null;
      const currentMessageId = panelRow.message_id;

      if (currentMessageId) {
        try {
          sentMsg = await app.discord.editMessage(
            panelRow.channel_id,
            currentMessageId,
            discordMessage
          );
        } catch (err: any) {
          const status = err?.status ?? err?.statusCode;
          const code = String(err?.code || '');
          if (status === 404 || code === '10008' || code === '404') {
            // Edit 404 falls back to send
            try {
              sentMsg = await app.discord.sendMessage(panelRow.channel_id, discordMessage);
            } catch (sendErr: any) {
              return reply.code(502).send({
                code: 'discord_error',
                message: sendErr?.message || 'Failed to send message to Discord',
              });
            }
          } else {
            return reply.code(502).send({
              code: 'discord_error',
              message: err?.message || 'Failed to edit message in Discord',
            });
          }
        }
      } else {
        try {
          sentMsg = await app.discord.sendMessage(panelRow.channel_id, discordMessage);
        } catch (sendErr: any) {
          return reply.code(502).send({
            code: 'discord_error',
            message: sendErr?.message || 'Failed to send message to Discord',
          });
        }
      }

      const newMsgId = sentMsg?.id ?? sentMsg?.message_id ?? currentMessageId;
      if (newMsgId && newMsgId !== panelRow.message_id) {
        const [updated] = await db
          .update(panels)
          .set({ message_id: newMsgId })
          .where(and(eq(panels.id, panelId), inGuild(panels, req.guildId)))
          .returning();
        return reply.send(toApiPanel(updated));
      }

      return reply.send(toApiPanel({ ...panelRow, message_id: newMsgId }));
    }
  );
}
