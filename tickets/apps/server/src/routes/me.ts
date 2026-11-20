import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { eq } from 'drizzle-orm';
import {
  guilds,
  categories,
  ensureGuild,
  isPlaceholderGuildName,
  type TicketsDb,
} from '@nakara-tickets/db';
import { checkStaff } from '../staff.js';
import type { TicketsConfig } from '../config.js';

const failedGuildLookups = new Map<string, number>();
const NEGATIVE_CACHE_TTL_MS = 60_000;
const NEGATIVE_CACHE_MAX_ENTRIES = 200;

export function clearGuildLookupNegativeCache(): void {
  failedGuildLookups.clear();
}

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
          const [row] = await db
            .select()
            .from(guilds)
            .where(eq(guilds.guild_id, guildId));

          let guildRow = row;

          if (!guildRow || isPlaceholderGuildName(guildRow.name, guildId)) {
            let realName: string | undefined;
            const failedAt = failedGuildLookups.get(guildId);
            const isNegativeCached = failedAt !== undefined && Date.now() - failedAt < NEGATIVE_CACHE_TTL_MS;

            if (config.DISCORD_TOKEN && !isNegativeCached) {
              let failed = false;
              try {
                const gRes = await fetch(`https://discord.com/api/v10/guilds/${guildId}`, {
                  headers: { Authorization: `Bot ${config.DISCORD_TOKEN}` },
                  signal: AbortSignal.timeout(10_000),
                });
                if (gRes.ok) {
                  const gData = (await gRes.json()) as { id: string; name?: string; icon?: string | null };
                  if (gData.name) {
                    realName = gData.name;
                    failedGuildLookups.delete(guildId);
                  } else {
                    failed = true;
                  }
                } else {
                  failed = true;
                }
              } catch {
                failed = true;
              }

              if (failed) {
                if (failedGuildLookups.size >= NEGATIVE_CACHE_MAX_ENTRIES) {
                  const oldest = failedGuildLookups.keys().next().value;
                  if (oldest !== undefined) failedGuildLookups.delete(oldest);
                }
                failedGuildLookups.set(guildId, Date.now());
              }
            }

            const nameToStore = realName ?? guildRow?.name ?? `Guild ${guildId}`;
            try {
              guildRow = await ensureGuild(db, guildId, nameToStore);
            } catch {
              // ignore
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
