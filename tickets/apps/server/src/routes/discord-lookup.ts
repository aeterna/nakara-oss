import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';

interface CacheEntry<T> {
  data: T;
  expiresAt: number;
}

class GuildCache<T> {
  private map = new Map<string, CacheEntry<T>>();
  constructor(private max = 200, private ttl = 60_000) {}

  get(key: string): T | undefined {
    const entry = this.map.get(key);
    if (!entry) return undefined;
    if (Date.now() >= entry.expiresAt) {
      this.map.delete(key);
      return undefined;
    }
    return entry.data;
  }

  set(key: string, data: T): void {
    if (this.map.has(key)) this.map.delete(key);
    else if (this.map.size >= this.max) {
      const oldest = this.map.keys().next().value;
      if (oldest !== undefined) this.map.delete(oldest);
    }
    this.map.set(key, { data, expiresAt: Date.now() + this.ttl });
  }

  clear(): void {
    this.map.clear();
  }
}

const channelsCache = new GuildCache<any[]>();
const rolesCache = new GuildCache<any[]>();
// Member display names per guild+user; null remembers a Discord 404 (member not in guild).
const memberNameCache = new GuildCache<string | null>(2000, 10 * 60_000);
export const clearDiscordLookupCache = () => {
  channelsCache.clear();
  rolesCache.clear();
  memberNameCache.clear();
};

const ALLOWED_TYPES = new Set([0, 4, 5, 15]);

const MEMBER_ID = /^[0-9]{17,20}$/;
const MAX_MEMBER_IDS = 50;
const MEMBER_FETCH_CONCURRENCY = 5;

// Comma-separated ids -> unique ids, or null when the list is malformed or too long.
function parseMemberIds(raw: unknown): string[] | null {
  if (raw === undefined || raw === '') return [];
  if (typeof raw !== 'string') return null;
  const ids = [...new Set(raw.split(','))];
  if (ids.length > MAX_MEMBER_IDS || !ids.every((id) => MEMBER_ID.test(id))) return null;
  return ids;
}

async function mapWithLimit<T, R>(items: T[], limit: number, fn: (item: T) => Promise<R>): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  const worker = async () => {
    while (next < items.length) {
      const i = next++;
      results[i] = await fn(items[i]);
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return results;
}

export default async function (app: FastifyInstance) {
  const requireStaff = async (req: FastifyRequest, reply: FastifyReply) => {
    if (typeof app.requireStaff !== 'function') {
      return reply.code(500).send({ code: 'misconfigured', message: 'Staff auth misconfigured' });
    }
    await app.requireStaff(req, reply);
  };

  const handle = async (
    req: FastifyRequest,
    reply: FastifyReply,
    fetcher: (discord: any, guildId: string) => Promise<any>
  ) => {
    const guildId = (req.params as { guildId: string }).guildId ?? req.guildId;
    const discord = req.server.discord ?? app.discord;
    if (!discord) {
      return reply.code(502).send({ code: 'discord_unavailable', message: 'Discord client unavailable' });
    }
    try {
      return reply.send(await fetcher(discord, guildId));
    } catch (err: any) {
      const token = (req.server.config ?? app.config)?.DISCORD_TOKEN;
      const raw = err?.message || 'Discord unavailable';
      const msg = token ? raw.replaceAll(token, '[REDACTED]') : raw;
      return reply.code(502).send({ code: 'discord_unavailable', message: msg });
    }
  };

  app.get('/api/v1/guilds/:guildId/discord/channels', { preHandler: [requireStaff] }, (req, reply) =>
    handle(req, reply, async (discord, guildId) => {
      const cached = channelsCache.get(guildId);
      if (cached) return cached;
      const raw = await discord.listGuildChannels(guildId);
      const data = raw
        .filter((c: any) => ALLOWED_TYPES.has(c.type))
        .map((c: any) => ({
          id: String(c.id),
          name: String(c.name),
          type: Number(c.type),
          parentId: c.parent_id ? String(c.parent_id) : null,
          position: typeof c.position === 'number' ? c.position : 0,
        }))
        .sort((a: any, b: any) => a.position - b.position);
      channelsCache.set(guildId, data);
      return data;
    })
  );

  app.get('/api/v1/guilds/:guildId/discord/roles', { preHandler: [requireStaff] }, (req, reply) =>
    handle(req, reply, async (discord, guildId) => {
      const cached = rolesCache.get(guildId);
      if (cached) return cached;
      const raw = await discord.listGuildRoles(guildId);
      const data = raw
        .filter((r: any) => r.id !== guildId && !r.managed)
        .map((r: any) => ({
          id: String(r.id),
          name: String(r.name),
          color: typeof r.color === 'number' ? r.color : 0,
          position: typeof r.position === 'number' ? r.position : 0,
        }))
        .sort((a: any, b: any) => b.position - a.position);
      rolesCache.set(guildId, data);
      return data;
    })
  );

  // One member's display name. Unknown members (404) are cached as misses; other errors are
  // left out and not cached, so the next request tries again.
  const fetchMemberName = async (discord: any, guildId: string, userId: string) => {
    const key = `${guildId}:${userId}`;
    const cached = memberNameCache.get(key);
    if (cached !== undefined) return cached === null ? null : { id: userId, name: cached };
    try {
      const member = await discord.getGuildMember(guildId, userId);
      const name = String(member?.nick || member?.user?.global_name || member?.user?.username || '');
      if (!name) return null;
      memberNameCache.set(key, name);
      return { id: userId, name };
    } catch (err: any) {
      if (err?.status === 404) memberNameCache.set(key, null);
      return null;
    }
  };

  app.get('/api/v1/guilds/:guildId/discord/members', { preHandler: [requireStaff] }, async (req, reply) => {
    const ids = parseMemberIds((req.query as { ids?: unknown }).ids);
    if (!ids) {
      return reply.code(400).send({ code: 'invalid_ids', message: 'ids must be up to 50 Discord user ids' });
    }
    return handle(req, reply, async (discord, guildId) => {
      const found = await mapWithLimit(ids, MEMBER_FETCH_CONCURRENCY, (id) => fetchMemberName(discord, guildId, id));
      return found.filter((m): m is { id: string; name: string } => m !== null);
    });
  });
}
