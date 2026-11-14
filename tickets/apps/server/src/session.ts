import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import fastifyCookie from '@fastify/cookie';
import { createHash, timingSafeEqual } from 'node:crypto';
import { eq } from 'drizzle-orm';
import { sessions, categories, type TicketsDb } from '@nakara-tickets/db';
import type { TicketsConfig } from './config.js';
import { checkStaff } from './staff.js';

export interface UserSessionData {
  id: string;
  userId: string;
  csrf: string;
}

export interface UserProfile {
  id: string;
  username: string;
  avatar: string | null;
}

declare module 'fastify' {
  interface FastifyInstance {
    requireUser: (req: FastifyRequest, reply: FastifyReply) => Promise<void>;
    requireStaff: (req: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
  interface FastifyRequest {
    user: UserProfile;
    guildId: string;
    session?: UserSessionData;
  }
}

export const userCache = new Map<string, UserProfile>();

export function constantTimeCompare(a: string | undefined, b: string): boolean {
  if (typeof a !== 'string' || typeof b !== 'string') {
    return false;
  }
  const bufA = Buffer.from(a, 'utf8');
  const bufB = Buffer.from(b, 'utf8');
  if (bufA.length !== bufB.length) {
    return false;
  }
  return timingSafeEqual(bufA, bufB);
}

export function getSessionCookieOptions(config?: TicketsConfig | null) {
  const isLocalhost = config?.PUBLIC_ORIGIN
    ? config.PUBLIC_ORIGIN.startsWith('http://localhost')
    : false;
  return {
    httpOnly: true,
    secure: !isLocalhost,
    sameSite: 'lax' as const,
    path: '/',
    maxAge: 7 * 24 * 60 * 60, // 7 days in seconds
  };
}

async function resolveUser(userId: string, config?: TicketsConfig | null): Promise<UserProfile> {
  const cached = userCache.get(userId);
  if (cached) {
    return cached;
  }

  if (config?.DISCORD_TOKEN) {
    try {
      const res = await fetch(`https://discord.com/api/v10/users/${userId}`, {
        headers: { Authorization: `Bot ${config.DISCORD_TOKEN}` },
      });
      if (res.ok) {
        const data = (await res.json()) as { id: string; username: string; avatar?: string | null };
        const profile: UserProfile = {
          id: data.id,
          username: data.username,
          avatar: data.avatar ?? null,
        };
        userCache.set(userId, profile);
        return profile;
      }
    } catch {
      // fallback if discord fetch fails
    }
  }

  const fallback: UserProfile = {
    id: userId,
    username: userId,
    avatar: null,
  };
  userCache.set(userId, fallback);
  return fallback;
}

export interface InstallSessionOptions {
  config?: TicketsConfig | null;
  db?: TicketsDb | null;
}

export async function installSession(app: FastifyInstance, opts?: InstallSessionOptions): Promise<void> {
  await app.register(fastifyCookie);

  if (!app.hasDecorator('config')) {
    app.decorate('config', opts?.config ?? null);
  } else if (opts?.config) {
    app.config = opts.config;
  }

  if (!app.hasDecorator('db')) {
    app.decorate('db', opts?.db ?? null);
  } else if (opts?.db) {
    app.db = opts.db;
  }

  const requireUser = async (req: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const token = req.cookies?.nt_session;
    if (!token || typeof token !== 'string') {
      return reply.code(401).send({ code: 'unauthorized', message: 'Authentication required' });
    }

    const db = (req.server.db ?? opts?.db) as TicketsDb | null;
    if (!db) {
      return reply.code(500).send({ code: 'server_error', message: 'Database handle not configured' });
    }

    const tokenHash = createHash('sha256').update(token).digest('hex');
    const [session] = await db.select().from(sessions).where(eq(sessions.token_hash, tokenHash));

    if (!session || new Date(session.expires_at) <= new Date()) {
      return reply.code(401).send({ code: 'unauthorized', message: 'Session expired or invalid' });
    }

    const config = (req.server.config ?? opts?.config) as TicketsConfig | null;
    const user = await resolveUser(session.user_id, config);

    req.user = user;
    req.session = {
      id: session.id,
      userId: session.user_id,
      csrf: session.csrf_hash,
    };

    // CSRF check: every non-GET under /api/v1 needs header X-CSRF-Token equal to the session's csrf value
    if (
      req.url.startsWith('/api/v1') &&
      req.method !== 'GET' &&
      req.method !== 'HEAD' &&
      req.method !== 'OPTIONS'
    ) {
      const csrfHeader = req.headers['x-csrf-token'];
      if (typeof csrfHeader !== 'string' || !constantTimeCompare(csrfHeader, session.csrf_hash)) {
        return reply.code(403).send({ code: 'csrf', message: 'csrf' });
      }
    }
  };

  const requireStaff = async (req: FastifyRequest, reply: FastifyReply): Promise<void> => {
    await requireUser(req, reply);
    if (reply.sent) {
      return;
    }

    const guildId =
      (req.params as Record<string, string | undefined>)?.guildId ?? req.guildId;
    const config = (req.server.config ?? opts?.config) as TicketsConfig | null;
    const db = (req.server.db ?? opts?.db) as TicketsDb | null;

    if (!guildId || !config?.ALLOWED_GUILD_IDS?.includes(guildId)) {
      return reply.code(403).send({ code: 'forbidden', message: 'Guild not allowed' });
    }

    let staffRoleIds: string[] = [];
    if (db) {
      try {
        const catRows = await db
          .select({ staff_role_ids: categories.staff_role_ids })
          .from(categories)
          .where(eq(categories.guild_id, guildId));
        staffRoleIds = catRows.flatMap((c) => c.staff_role_ids ?? []);
      } catch {
        // use empty list if categories query fails
      }
    }

    const isStaffMember = await checkStaff(
      { token: config?.DISCORD_TOKEN },
      guildId,
      req.user.id,
      staffRoleIds
    );

    if (!isStaffMember) {
      return reply.code(403).send({ code: 'forbidden', message: 'Staff access required' });
    }

    req.guildId = guildId;
  };

  app.decorate('requireUser', requireUser);
  app.decorate('requireStaff', requireStaff);
}
