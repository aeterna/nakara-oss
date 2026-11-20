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

      let oauthGuilds: Array<{ id: string; name: string; icon?: string | null }> =
        (req.user as any)?.guilds ?? (req as any)?.guilds ?? [];

      if (oauthGuilds.length === 0) {
        const authHeader =
          (req.session as any)?.accessToken
            ? `Bearer ${(req.session as any).accessToken}`
            : config.DISCORD_TOKEN
              ? `Bot ${config.DISCORD_TOKEN}`
              : undefined;

        if (authHeader) {
          try {
            const res = await fetch('https://discord.com/api/v10/users/@me/guilds', {
              headers: { Authorization: authHeader },
              signal: AbortSignal.timeout(10_000),
            });
            if (res.ok) {
              oauthGuilds = (await res.json()) as Array<{
                id: string;
                name: string;
                icon?: string | null;
              }>;
            }
          } catch {
            // ignore
          }
        }
      }

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
          const oauthGuild = Array.isArray(oauthGuilds)
            ? oauthGuilds.find((g) => g.id === guildId)
            : undefined;

          let realName = oauthGuild?.name;
          let realIcon = oauthGuild?.icon ?? null;

          if (!realName && config.DISCORD_TOKEN) {
            try {
              const gRes = await fetch(`https://discord.com/api/v10/guilds/${guildId}`, {
                headers: { Authorization: `Bot ${config.DISCORD_TOKEN}` },
                signal: AbortSignal.timeout(10_000),
              });
              if (gRes.ok) {
                const gData = (await gRes.json()) as { id: string; name?: string; icon?: string | null };
                if (gData.name) {
                  realName = gData.name;
                  if (gData.icon) realIcon = gData.icon;
                }
              }
            } catch {
              // ignore
            }
          }

          const nameToEnsure = realName ?? `Guild ${guildId}`;
          let guildRow;
          try {
            guildRow = await ensureGuild(db, guildId, nameToEnsure);
          } catch {
            const [row] = await db
              .select()
              .from(guilds)
              .where(eq(guilds.guild_id, guildId));
            guildRow = row;
          }

          staffGuilds.push({
            id: guildId,
            name: guildRow?.name ?? realName ?? `Guild ${guildId}`,
            icon: guildRow?.icon ?? realIcon ?? null,
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
