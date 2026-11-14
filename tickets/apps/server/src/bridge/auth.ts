import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { eq, and, lt } from 'drizzle-orm';
import { openBytes, verifyBridge, type BridgeParts } from '@nakara-tickets/core';
import { gameServers, bridgeNonces, type TicketsDb } from '@nakara-tickets/db';

declare module 'fastify' {
  interface FastifyInstance {
    requireBridge: (req: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
  interface FastifyRequest {
    gameServer?: typeof gameServers.$inferSelect;
    rawBody?: Buffer;
  }
}

let lastCleanup = 0;

export function installBridgeAuth(
  app: FastifyInstance,
  opts?: { db?: TicketsDb | null; dataKey?: Buffer | null }
) {
  const getDb = () => opts?.db ?? app.db;
  const getDataKey = () => opts?.dataKey ?? app.config?.TICKETS_DATA_KEY;

  const requireBridge = async (req: FastifyRequest, reply: FastifyReply) => {
    const db = getDb();
    const dataKey = getDataKey();

    if (!db || !dataKey) {
      return reply.code(401).send({ code: 'unauthorized', message: 'unauthorized' });
    }

    const sigHeader = req.headers['x-tickets-signature'];
    const serverHeader = req.headers['x-tickets-server'];
    const tsHeader = req.headers['x-tickets-timestamp'];
    const nonceHeader = req.headers['x-tickets-nonce'];
    const protocolHeader = req.headers['x-tickets-protocol'];

    if (
      typeof sigHeader !== 'string' ||
      typeof serverHeader !== 'string' ||
      (typeof tsHeader !== 'string' && typeof tsHeader !== 'number') ||
      typeof nonceHeader !== 'string' ||
      (typeof protocolHeader !== 'string' && typeof protocolHeader !== 'number') ||
      String(protocolHeader) !== '1'
    ) {
      return reply.code(401).send({ code: 'unauthorized', message: 'unauthorized' });
    }

    // Load game_servers row (not revoked)
    let server: typeof gameServers.$inferSelect | undefined;
    try {
      const rows = await db
        .select()
        .from(gameServers)
        .where(and(eq(gameServers.id, serverHeader), eq(gameServers.revoked, false)));
      server = rows[0];
    } catch {
      return reply.code(401).send({ code: 'unauthorized', message: 'unauthorized' });
    }

    if (!server) {
      return reply.code(401).send({ code: 'unauthorized', message: 'unauthorized' });
    }

    // Open secret_enc with openBytes
    let secret: Buffer;
    try {
      secret = openBytes(dataKey, server.secret_enc);
    } catch {
      return reply.code(401).send({ code: 'unauthorized', message: 'unauthorized' });
    }

    // Verify HMAC over raw body bytes
    const rawBody: Buffer = (req as any).rawBody ?? Buffer.alloc(0);
    const nowSec = Math.floor(Date.now() / 1000);
    const parts: BridgeParts = {
      timestamp: String(tsHeader),
      nonce: nonceHeader,
      method: req.method,
      pathWithQuery: req.url,
      body: rawBody,
    };

    const verifyResult = verifyBridge(secret, parts, sigHeader, nowSec, 60);
    if (!verifyResult.ok) {
      return reply.code(401).send({ code: 'unauthorized', message: 'unauthorized' });
    }

    // Insert nonce into bridge_nonces (expires now+120 s) with ON CONFLICT DO NOTHING
    const expiresAt = new Date(Date.now() + 120 * 1000);
    try {
      const inserted = await db
        .insert(bridgeNonces)
        .values({
          server_id: server.id,
          nonce: nonceHeader,
          expires_at: expiresAt,
        })
        .onConflictDoNothing()
        .returning({ server_id: bridgeNonces.server_id });

      if (!inserted || inserted.length === 0) {
        // Replay detected
        return reply.code(401).send({ code: 'unauthorized', message: 'unauthorized' });
      }
    } catch {
      return reply.code(401).send({ code: 'unauthorized', message: 'unauthorized' });
    }

    // Periodic cleanup of expired nonces (at most once a minute)
    const now = Date.now();
    if (now - lastCleanup > 60_000) {
      lastCleanup = now;
      db.delete(bridgeNonces)
        .where(lt(bridgeNonces.expires_at, new Date()))
        .catch(() => {});
    }

    // Attach gameServer to request
    req.gameServer = server;
  };

  if (!app.hasDecorator('requireBridge')) {
    app.decorate('requireBridge', requireBridge);
  }
}
