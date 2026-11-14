import type { FastifyInstance } from 'fastify';
import { sql } from 'drizzle-orm';
import pkg from '../../package.json' with { type: 'json' };
import type { GatewayStatus } from '../types.js';

export default async function (app: FastifyInstance) {
  app.get('/healthz', async (_req, reply) => {
    let dbStatus: 'up' | 'down' = 'down';

    if (app.db) {
      try {
        const timeoutPromise = new Promise<never>((_, reject) => {
          const timer = setTimeout(() => reject(new Error('timeout')), 1000);
          if (typeof timer.unref === 'function') {
            timer.unref();
          }
        });
        await Promise.race([
          app.db.execute(sql`SELECT 1`),
          timeoutPromise,
        ]);
        dbStatus = 'up';
      } catch {
        dbStatus = 'down';
      }
    }

    const rawGateway = app.gateway?.status();
    let gatewayStatus: GatewayStatus = 'connecting';
    if (rawGateway === 'connected' || rawGateway === 'standby' || rawGateway === 'connecting') {
      gatewayStatus = rawGateway;
    }

    const ok = dbStatus === 'up';
    const statusCode = ok ? 200 : 503;

    return reply.code(statusCode).send({
      ok,
      db: dbStatus,
      gateway: gatewayStatus,
      version: pkg.version ?? '0.1.0',
    });
  });

  app.get('/metrics', async (_req, reply) => {
    const ticketCounts = { open: 0, claimed: 0, closed: 0 };
    let gameServersOnline = 0;

    if (app.db) {
      try {
        const rows = (await app.db.execute(sql`
          SELECT status, COUNT(*)::int as count
          FROM tickets
          GROUP BY status
        `)) as { rows?: Array<{ status: string; count: number | string }> };

        for (const row of rows.rows ?? []) {
          if (row.status in ticketCounts) {
            ticketCounts[row.status as keyof typeof ticketCounts] = Number(row.count);
          }
        }
      } catch {
        // fallback to 0
      }

      try {
        const ninetySecAgo = new Date(Date.now() - 90 * 1000);
        const rows = (await app.db.execute(sql`
          SELECT COUNT(*)::int as count
          FROM game_servers
          WHERE last_seen_at >= ${ninetySecAgo}
        `)) as { rows?: Array<{ count: number | string }> };

        gameServersOnline = Number(rows.rows?.[0]?.count ?? 0);
      } catch {
        // fallback to 0
      }
    }

    const gatewayConnected = app.gateway?.status() === 'connected' ? 1 : 0;

    const lines = [
      '# HELP nakara_tickets_up Process liveness indicator',
      '# TYPE nakara_tickets_up gauge',
      'nakara_tickets_up 1',
      '# HELP nakara_tickets_tickets Ticket counts by status',
      '# TYPE nakara_tickets_tickets gauge',
      `nakara_tickets_tickets{status="open"} ${ticketCounts.open}`,
      `nakara_tickets_tickets{status="claimed"} ${ticketCounts.claimed}`,
      `nakara_tickets_tickets{status="closed"} ${ticketCounts.closed}`,
      '# HELP nakara_tickets_game_servers_online Game servers seen in the last 90 seconds',
      '# TYPE nakara_tickets_game_servers_online gauge',
      `nakara_tickets_game_servers_online ${gameServersOnline}`,
      '# HELP nakara_tickets_gateway_connected Discord gateway connection status',
      '# TYPE nakara_tickets_gateway_connected gauge',
      `nakara_tickets_gateway_connected ${gatewayConnected}`,
    ];

    return reply
      .type('text/plain; version=0.0.4')
      .send(lines.join('\n') + '\n');
  });
}
