import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { createHash, randomBytes } from 'node:crypto';
import { eq, and, or, lt, sql } from 'drizzle-orm';
import { sealBytes } from '@nakara-tickets/core';
import {
  pairCodes,
  gameServers,
  guilds,
  gameActions,
  auditLog,
  tickets,
} from '@nakara-tickets/db';

const serverPlayers = new Map<string, any[]>();
const pairRateLimits = new Map<string, { count: number; resetAt: number }>();

export function getOnlinePlayers(serverId: string): any[] {
  return serverPlayers.get(serverId) ?? [];
}

function checkPairRateLimit(ip: string): boolean {
  const now = Date.now();
  const entry = pairRateLimits.get(ip);
  if (!entry || now > entry.resetAt) {
    pairRateLimits.set(ip, { count: 1, resetAt: now + 60_000 });
    return true;
  }
  if (entry.count >= 10) {
    return false;
  }
  entry.count++;
  return true;
}

function sha256hex(str: string): string {
  return createHash('sha256').update(str).digest('hex');
}

export default async function (app: FastifyInstance) {
  // Raw body parser registered inside bridge route plugin only
  app.addContentTypeParser('application/json', { parseAs: 'buffer' }, (req, body, done) => {
    (req as any).rawBody = body;
    if (!body || body.length === 0) {
      done(null, {});
      return;
    }
    try {
      const json = JSON.parse(body.toString('utf8'));
      done(null, json);
    } catch (err: any) {
      done(err, undefined);
    }
  });

  const requireBridgeAuth = async (req: FastifyRequest, reply: FastifyReply) => {
    if (app.requireBridge) {
      return app.requireBridge(req, reply);
    }
    return reply.code(401).send({ code: 'unauthorized', message: 'unauthorized' });
  };

  // POST /bridge/v1/pair
  app.post('/bridge/v1/pair', async (req: FastifyRequest, reply: FastifyReply) => {
    if (!app.db) {
      return reply.code(501).send({ code: 'not_implemented', message: 'postBridgePair' });
    }

    if (!checkPairRateLimit(req.ip)) {
      return reply.code(429).send({ code: 'rate_limited', message: 'Too many pair requests' });
    }

    const body = (req.body ?? {}) as any;
    const { code, serverName, edition, resourceVersion, protocol } = body;

    if (!code || !serverName || protocol !== 1) {
      return reply.code(400).send({ code: 'invalid', message: 'invalid request' });
    }

    const normCode = String(code).trim();
    const upperCodeHash = sha256hex(normCode.toUpperCase());
    const exactCodeHash = sha256hex(normCode);

    const [pairCodeRow] = await app.db
      .select()
      .from(pairCodes)
      .where(or(eq(pairCodes.code_hash, upperCodeHash), eq(pairCodes.code_hash, exactCodeHash)));

    const now = new Date();
    if (!pairCodeRow || pairCodeRow.used_at !== null || pairCodeRow.expires_at < now) {
      return reply.code(400).send({ code: 'invalid', message: 'invalid or expired pair code' });
    }

    // Mark pair code as used
    await app.db
      .update(pairCodes)
      .set({ used_at: now })
      .where(eq(pairCodes.id, pairCodeRow.id));

    // Generate 32 random bytes secret sealed with sealBytes
    const rawSecret = randomBytes(32);
    const dataKey = app.config?.TICKETS_DATA_KEY ?? Buffer.alloc(32);
    const secretEnc = sealBytes(dataKey, rawSecret);

    const [newServer] = await app.db
      .insert(gameServers)
      .values({
        guild_id: pairCodeRow.guild_id,
        name: String(serverName).slice(0, 64),
        secret_enc: secretEnc,
        confirmed: false,
        edition: edition ? String(edition).slice(0, 32) : null,
        resource_version: resourceVersion ? String(resourceVersion).slice(0, 32) : null,
        protocol: 1,
      })
      .returning();

    const [guild] = await app.db
      .select()
      .from(guilds)
      .where(eq(guilds.guild_id, pairCodeRow.guild_id));

    return reply.code(200).send({
      serverId: newServer.id,
      secret: rawSecret.toString('base64url'),
      guildName: guild?.name ?? 'Nakara Tickets Guild',
    });
  });

  // POST /bridge/v1/heartbeat
  app.post(
    '/bridge/v1/heartbeat',
    { preHandler: [requireBridgeAuth] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      if (!app.db) {
        return reply.code(501).send({ code: 'not_implemented', message: 'postBridgeHeartbeat' });
      }

      const server = req.gameServer!;
      const body = (req.body ?? {}) as any;
      const players = Array.isArray(body?.players) ? body.players : [];

      const updateData: any = {
        last_seen_at: new Date(),
        players_online: players.length,
      };
      if (body?.edition) {
        updateData.edition = String(body.edition).slice(0, 32);
      }

      await app.db
        .update(gameServers)
        .set(updateData)
        .where(eq(gameServers.id, server.id));

      serverPlayers.set(server.id, players);

      return reply.code(200).send({ ok: true });
    }
  );

  // GET /bridge/v1/actions
  app.get(
    '/bridge/v1/actions',
    { preHandler: [requireBridgeAuth] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      if (!app.db) {
        return reply.code(501).send({ code: 'not_implemented', message: 'getBridgeActions' });
      }

      const server = req.gameServer!;

      // Only a confirmed server receives actions
      if (!server.confirmed) {
        return reply.code(200).send({ action: null });
      }

      const waitQuery = (req.query as any)?.wait;
      const waitSec = waitQuery !== undefined ? Math.max(0, Math.min(25, Number(waitQuery))) : 25;
      const deadline = Date.now() + waitSec * 1000;

      while (true) {
        const now = new Date();

        // Actions past expires_at become expired
        await app.db
          .update(gameActions)
          .set({ status: 'expired' })
          .where(
            and(
              eq(gameActions.server_id, server.id),
              or(eq(gameActions.status, 'queued'), eq(gameActions.status, 'leased')),
              lt(gameActions.expires_at, now)
            )
          );

        // Lease the oldest action
        const leasedRes = await app.db.execute(sql`
          WITH next_action AS (
            SELECT id FROM game_actions
            WHERE server_id = ${server.id}
              AND (status = 'queued' OR (status = 'leased' AND lease_until < now()))
              AND expires_at >= now()
            ORDER BY created_at ASC
            LIMIT 1
            FOR UPDATE SKIP LOCKED
          )
          UPDATE game_actions
          SET status = 'leased', lease_until = now() + interval '30 seconds'
          WHERE id = (SELECT id FROM next_action)
          RETURNING id, ticket_id, server_id, action, params, requested_by, lease_until, expires_at;
        `);

        const leasedRows = leasedRes.rows || [];
        if (leasedRows.length > 0) {
          const row: any = leasedRows[0];
          const [ticket] = await app.db
            .select({ opener_id: tickets.opener_id })
            .from(tickets)
            .where(eq(tickets.id, row.ticket_id));

          return reply.code(200).send({
            action: {
              id: row.id,
              action: row.action,
              params: row.params ?? {},
              discordId: ticket?.opener_id ?? null,
              requestedBy: row.requested_by,
              leaseUntil: new Date(row.lease_until).toISOString(),
              expiresAt: new Date(row.expires_at).toISOString(),
            },
          });
        }

        if (Date.now() >= deadline) {
          break;
        }

        const remainingMs = deadline - Date.now();
        await new Promise((resolve) => setTimeout(resolve, Math.min(1000, remainingMs)));
      }

      return reply.code(200).send({ action: null });
    }
  );

  // POST /bridge/v1/actions/:actionId/result
  app.post(
    '/bridge/v1/actions/:actionId/result',
    { preHandler: [requireBridgeAuth] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      if (!app.db) {
        return reply.code(501).send({ code: 'not_implemented', message: 'postBridgeActionsResult' });
      }

      const server = req.gameServer!;
      const actionId = (req.params as any).actionId;
      const body = (req.body ?? {}) as any;

      const [action] = await app.db
        .select()
        .from(gameActions)
        .where(and(eq(gameActions.id, actionId), eq(gameActions.server_id, server.id)));

      if (!action) {
        return reply.code(404).send({ code: 'not_found', message: 'action not found' });
      }

      // Check idempotence
      if (action.status === 'done' || action.status === 'failed') {
        const existingResult = JSON.stringify(action.result);
        const incomingResult = JSON.stringify(body);

        if (existingResult === incomingResult) {
          return reply.code(200).send({ ok: true });
        }
        return reply.code(409).send({ code: 'conflict', message: 'conflicting result already recorded' });
      }

      const newStatus = body.ok ? 'done' : 'failed';
      await app.db
        .update(gameActions)
        .set({
          status: newStatus,
          result: body,
        })
        .where(eq(gameActions.id, action.id));

      await app.db.insert(auditLog).values({
        guild_id: action.guild_id,
        actor_id: `game:${server.id}`,
        kind: 'action.result',
        target: action.id,
        detail: {
          action: action.action,
          ticketId: action.ticket_id,
          result: body,
        },
      });

      return reply.code(200).send({ ok: true });
    }
  );
}
