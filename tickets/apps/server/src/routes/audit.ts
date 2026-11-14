import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { and, eq, or, lt, desc, type SQL } from 'drizzle-orm';
import { auditLog, inGuild, type TicketsDb } from '@nakara-tickets/db';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Returns null when the cursor is malformed (bad encoding, unparseable date, or a non-uuid id)
function parseCursor(cursor: string): { createdAt: Date | null; id: string | null } | null {
  let decoded: unknown;
  try {
    decoded = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
  } catch {
    // Not an encoded cursor: accept a bare timestamp or a bare audit id
    const d = new Date(cursor);
    if (!isNaN(d.getTime())) {
      return { createdAt: d, id: null };
    }
    if (UUID_PATTERN.test(cursor)) {
      return { createdAt: null, id: cursor };
    }
    return null;
  }

  if (!decoded || typeof decoded !== 'object' || Array.isArray(decoded)) {
    return null;
  }

  const { createdAt, id } = decoded as { createdAt?: unknown; id?: unknown };

  let parsedCreatedAt: Date | null = null;
  if (createdAt !== undefined) {
    if (typeof createdAt !== 'string') return null;
    parsedCreatedAt = new Date(createdAt);
    if (isNaN(parsedCreatedAt.getTime())) return null;
  }

  let parsedId: string | null = null;
  if (id !== undefined) {
    if (typeof id !== 'string' || !UUID_PATTERN.test(id)) return null;
    parsedId = id;
  }

  if (!parsedCreatedAt && !parsedId) return null;
  return { createdAt: parsedCreatedAt, id: parsedId };
}

export default async function (app: FastifyInstance) {
  const requireStaff = async (req: FastifyRequest, reply: FastifyReply) => {
    if (typeof app.requireStaff !== 'function') {
      reply.code(500).send({ code: 'misconfigured', message: 'Staff authentication not configured' });
      return;
    }
    await app.requireStaff(req, reply);
  };

  app.get(
    '/api/v1/guilds/:guildId/audit',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const guildId = req.guildId || (req.params as any)?.guildId;

      if (!guildId) {
        return reply.code(400).send({ code: 'missing_guild', message: 'Guild ID is required' });
      }

      const query = (req.query ?? {}) as Record<string, string | undefined>;
      const rawLimit = parseInt(query.limit ?? '50', 10);
      const limit = isNaN(rawLimit) || rawLimit <= 0 ? 50 : Math.min(rawLimit, 100);

      const action = query.action || query.kind;
      const cursor = query.cursor;

      const conditions: SQL[] = [inGuild(auditLog, guildId)];

      if (action) {
        conditions.push(eq(auditLog.kind, action));
      }

      let cursorCreatedAt: Date | null = null;
      let cursorId: string | null = null;

      if (cursor) {
        const parsedCursor = parseCursor(cursor);
        if (!parsedCursor) {
          return reply.code(400).send({ code: 'invalid', message: 'cursor is invalid' });
        }
        cursorCreatedAt = parsedCursor.createdAt;
        cursorId = parsedCursor.id;

        if (cursorId && !cursorCreatedAt) {
          const [ref] = await db
            .select({ created_at: auditLog.created_at })
            .from(auditLog)
            .where(and(eq(auditLog.id, cursorId), inGuild(auditLog, guildId)))
            .limit(1);
          if (ref) {
            cursorCreatedAt = ref.created_at;
          }
        }

        if (cursorCreatedAt && cursorId) {
          conditions.push(
            or(
              lt(auditLog.created_at, cursorCreatedAt),
              and(eq(auditLog.created_at, cursorCreatedAt), lt(auditLog.id, cursorId))
            )!
          );
        } else if (cursorCreatedAt) {
          conditions.push(lt(auditLog.created_at, cursorCreatedAt));
        } else if (cursorId) {
          conditions.push(lt(auditLog.id, cursorId));
        }
      }

      const rows = await db
        .select()
        .from(auditLog)
        .where(and(...conditions))
        .orderBy(desc(auditLog.created_at), desc(auditLog.id))
        .limit(limit + 1);

      let next: string | null = null;
      let pageRows = rows;

      if (rows.length > limit) {
        pageRows = rows.slice(0, limit);
        const last = pageRows[pageRows.length - 1];
        next = Buffer.from(
          JSON.stringify({ createdAt: last.created_at.toISOString(), id: last.id })
        ).toString('base64url');
      }

      const items = pageRows.map((r) => ({
        id: r.id,
        actorId: r.actor_id,
        actor_id: r.actor_id,
        kind: r.kind,
        target: r.target ?? null,
        detail: r.detail ?? {},
        createdAt: r.created_at.toISOString(),
        created_at: r.created_at.toISOString(),
      }));

      return reply.send({ items, next });
    }
  );
}
