import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { eq } from 'drizzle-orm';
import { guilds, categories, ensureGuild, type TicketsDb } from '@nakara-tickets/db';
import { checkStaff } from '../staff.js';
import type { TicketsConfig } from '../config.js';

export default async function (app: FastifyInstance) {
  app.get(
    '/api/v1/me',
    {
      preHandler: [
        async (req, reply) => {
          if (typeof app.requireUser !== 'function') {
            reply.code(500).send({ code: 'misconfigured', message: 'User auth misconfigured' });
            return;
          }
          await app.requireUser(req, reply);
        },
      ],
    },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const config = req.server.config as TicketsConfig | null;
      const db = req.server.db as TicketsDb | null;

      if (!config || !db) {
        return reply.code(500).send({ code: 'server_error', message: 'Configuration or database missing' });
      }

      const staffGuilds: Array<{
        id: string;
        name: string;
        icon: string | null;
        canManage: boolean;
      }> = [];

      for (const guildId of config.ALLOWED_GUILD_IDS ?? []) {
        let staffRoleIds: string[] = [];
        try {
          const catRows = await db
            .select({ staff_role_ids: categories.staff_role_ids })
            .from(categories)
            .where(eq(categories.guild_id, guildId));
          staffRoleIds = catRows.flatMap((c) => c.staff_role_ids ?? []);
        } catch {
          // ignore
        }

        const isStaffMember = await checkStaff(
          { token: config.DISCORD_TOKEN },
          guildId,
          req.user.id,
          staffRoleIds
        );

        if (isStaffMember) {
          let [guildRow] = await db
            .select()
            .from(guilds)
            .where(eq(guilds.guild_id, guildId));

          if (!guildRow) {
            try {
              await ensureGuild(db, guildId, `Guild ${guildId}`);
              [guildRow] = await db
                .select()
                .from(guilds)
                .where(eq(guilds.guild_id, guildId));
            } catch {
              // fallback
            }
          }

          staffGuilds.push({
            id: guildId,
            name: guildRow?.name ?? `Guild ${guildId}`,
            icon: guildRow?.icon ?? null,
            canManage: true,
          });
        }
      }

      return reply.send({
        user: req.user,
        guilds: staffGuilds,
        csrfToken: req.session?.csrf ?? '',
      });
    }
  );
}
