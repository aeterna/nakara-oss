import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { randomBytes } from 'node:crypto';
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
import { normalizePairCode, sha256hex } from '../bridge/pair-code.js';

export { normalizePairCode, sha256hex };

const serverPlayers = new Map<string, any[]>();
const pairRateLimits = new Map<string, { count: number; resetAt: number }>();

export function getOnlinePlayers(serverId: string): any[] {
  return serverPlayers.get(serverId) ?? [];
}

function checkPairRateLimit(ip: string): boolean {
  const now = Date.now();

  // Prune expired entries
  for (const [k, v] of pairRateLimits.entries()) {
    if (now > v.resetAt) {
      pairRateLimits.delete(k);
    }
  }

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

function isDeepEqual(a: any, b: any): boolean {
  if (a === b) return true;
  if (a === null || b === null || typeof a !== typeof b) return false;
  if (typeof a !== 'object') return false;
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  if (Array.isArray(a)) {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) {
      if (!isDeepEqual(a[i], b[i])) return false;
    }
    return true;
  }
  const keysA = Object.keys(a);
  const keysB = Object.keys(b);
  if (keysA.length !== keysB.length) return false;
  for (const k of keysA) {
    if (!Object.prototype.hasOwnProperty.call(b, k)) return false;
    if (!isDeepEqual(a[k], b[k])) return false;
  }
  return true;
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
      await app.requireBridge(req, reply);
      return;
    }
    reply.code(401).send({ code: 'unauthorized', message: 'unauthorized' });
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

    const dataKey = app.config?.TICKETS_DATA_KEY;
    if (!dataKey) {
      return reply.code(500).send({ code: 'misconfigured', message: 'TICKETS_DATA_KEY is not configured' });
    }

    const normCode = normalizePairCode(String(code));
    const codeHash = sha256hex(normCode);

    // Atomically consume pair code and insert game_server in one transaction
    const txResult = await app.db.transaction(async (tx) => {
      const updateResult = (await tx.execute(sql`
        UPDATE pair_codes
        SET used_at = now()
        WHERE code_hash = ${codeHash}
          AND used_at IS NULL
          AND expires_at > now()
        RETURNING id, guild_id, server_name;
      `)) as { rows?: any[] };

      const rows = updateResult.rows || [];
      if (rows.length === 0) {
        return null;
      }
      const pairCodeRow: any = rows[0];

      const rawSecret = randomBytes(32);
      const secretEnc = sealBytes(dataKey, rawSecret);

      const [newServer] = await tx
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

      const [guild] = await tx
        .select()
        .from(guilds)
        .where(eq(guilds.guild_id, pairCodeRow.guild_id));

      return {
        serverId: newServer.id,
        secret: rawSecret.toString('base64url'),
        guildName: guild?.name ?? 'Nakara Tickets Guild',
      };
    });

    if (!txResult) {
      return reply.code(400).send({ code: 'invalid', message: 'invalid or expired pair code' });
    }

    return reply.code(200).send(txResult);
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

      if (!body || typeof body !== 'object' || !Array.isArray(body.players)) {
        return reply.code(400).send({ code: 'invalid', message: 'players must be an array' });
      }

      if (body.players.length > 2048) {
        return reply.code(400).send({ code: 'invalid', message: 'too many players (max 2048)' });
      }

      const SNOWFLAKE_RE = /^[0-9]{17,20}$/;
      for (const p of body.players) {
        if (
          !p ||
          typeof p !== 'object' ||
          !Number.isInteger(p.playerId) ||
          p.playerId < 0 ||
          typeof p.discordId !== 'string' ||
          !SNOWFLAKE_RE.test(p.discordId)
        ) {
          return reply.code(400).send({ code: 'invalid', message: 'invalid player in players list' });
        }
      }

      const players = body.players;

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

      const waitQuery = (req.query as any)?.wait;
      const waitSec = waitQuery !== undefined ? Math.max(0, Math.min(25, Number(waitQuery))) : 25;

      // Only a confirmed server receives actions; unconfirmed waits full wait duration then returns null
      if (!server.confirmed) {
        if (waitSec > 0) {
          await new Promise((resolve) => setTimeout(resolve, waitSec * 1000));
        }
        return reply.code(200).send({ action: null });
      }

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
        const leasedRes = (await app.db.execute(sql`
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
        `)) as { rows?: any[] };

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

      const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (typeof actionId !== 'string' || !UUID_REGEX.test(actionId)) {
        return reply.code(400).send({ code: 'invalid', message: 'invalid actionId' });
      }

      const body = req.body as any;

      if (!body || typeof body !== 'object' || Array.isArray(body)) {
        return reply.code(400).send({ code: 'invalid', message: 'body must be an object' });
      }

      const allowedKeys = new Set(['ok', 'code', 'message', 'data']);
      for (const k of Object.keys(body)) {
        if (!allowedKeys.has(k)) {
          return reply.code(400).send({ code: 'invalid', message: `unexpected field '${k}'` });
        }
      }

      if (typeof body.ok !== 'boolean') {
        return reply.code(400).send({ code: 'invalid', message: 'ok must be a boolean' });
      }

      if (typeof body.code !== 'string' || body.code.length === 0 || body.code.length > 32) {
        return reply.code(400).send({ code: 'invalid', message: 'code must be string up to 32 chars' });
      }

      if (body.message !== undefined && (typeof body.message !== 'string' || body.message.length > 512)) {
        return reply.code(400).send({ code: 'invalid', message: 'message must be string up to 512 chars' });
      }

      if (body.data !== undefined) {
        if (typeof body.data !== 'object' || body.data === null || Array.isArray(body.data)) {
          return reply.code(400).send({ code: 'invalid', message: 'data must be an object' });
        }
        if (Object.keys(body.data).length > 16) {
          return reply.code(400).send({ code: 'invalid', message: 'data max 16 properties' });
        }
      }

      const [action] = await app.db
        .select()
        .from(gameActions)
        .where(and(eq(gameActions.id, actionId), eq(gameActions.server_id, server.id)));

      if (!action) {
        return reply.code(404).send({ code: 'not_found', message: 'action not found' });
      }

      // Check idempotence
      if (action.status === 'done' || action.status === 'failed') {
        if (isDeepEqual(action.result, body)) {
          return reply.code(200).send({ ok: true });
        }
        return reply.code(409).send({ code: 'conflict', message: 'conflicting result already recorded' });
      }

      // Record only via UPDATE ... WHERE id=$1 AND server_id=$2 AND status='leased' RETURNING
      const newStatus = body.ok ? 'done' : 'failed';
      const updatedRes = (await app.db.execute(sql`
        UPDATE game_actions
        SET status = ${newStatus}, result = ${JSON.stringify(body)}::jsonb
        WHERE id = ${actionId} AND server_id = ${server.id} AND status = 'leased'
        RETURNING id, guild_id, ticket_id, action;
      `)) as { rows?: any[] };

      const updatedRows = updatedRes.rows || [];
      if (updatedRows.length === 0) {
        const [recheck] = await app.db
          .select()
          .from(gameActions)
          .where(and(eq(gameActions.id, actionId), eq(gameActions.server_id, server.id)));
        if (recheck && (recheck.status === 'done' || recheck.status === 'failed')) {
          if (isDeepEqual(recheck.result, body)) {
            return reply.code(200).send({ ok: true });
          }
          return reply.code(409).send({ code: 'conflict', message: 'conflicting result already recorded' });
        }
        return reply.code(409).send({ code: 'conflict', message: 'action is not leased' });
      }

      const updatedAction: any = updatedRows[0];
      await app.db.insert(auditLog).values({
        guild_id: updatedAction.guild_id,
        actor_id: `game:${server.id}`,
        kind: 'action.result',
        target: updatedAction.id,
        detail: {
          action: updatedAction.action,
          ticketId: updatedAction.ticket_id,
          result: body,
        },
      });

      return reply.code(200).send({ ok: true });
    }
  );
}
