import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { sql } from 'drizzle-orm';
import type { TicketsDb } from '@nakara-tickets/db';

export default async function (app: FastifyInstance) {
  const requireStaff = async (req: FastifyRequest, reply: FastifyReply) => {
    if (typeof app.requireStaff === 'function') {
      await app.requireStaff(req, reply);
    } else {
      req.guildId = (req.params as any)?.guildId;
    }
  };

  app.get(
    '/api/v1/guilds/:guildId/stats',
    { preHandler: [requireStaff] },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db as TicketsDb;
      const guildId = req.guildId || (req.params as any)?.guildId;

      if (!guildId) {
        return reply.code(400).send({ code: 'missing_guild', message: 'Guild ID is required' });
      }

      const query = (req.query ?? {}) as Record<string, string | undefined>;
      let fromStr = query.from;
      let toStr = query.to;

      const now = new Date();
      if (!fromStr || !toStr) {
        // Default: last 30 days
        const defaultTo = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 23, 59, 59, 999));
        const defaultFrom = new Date(defaultTo.getTime() - 29 * 86400000);
        defaultFrom.setUTCHours(0, 0, 0, 0);

        fromStr = defaultFrom.toISOString().slice(0, 10);
        toStr = defaultTo.toISOString().slice(0, 10);
      }

      const fromMatch = /^(\d{4})-(\d{2})-(\d{2})/.exec(fromStr);
      const toMatch = /^(\d{4})-(\d{2})-(\d{2})/.exec(toStr);

      if (!fromMatch || !toMatch) {
        return reply.code(400).send({ code: 'invalid_date', message: 'Dates must be in YYYY-MM-DD format' });
      }

      const fromYear = parseInt(fromMatch[1], 10);
      const fromMonth = parseInt(fromMatch[2], 10) - 1;
      const fromDay = parseInt(fromMatch[3], 10);

      const toYear = parseInt(toMatch[1], 10);
      const toMonth = parseInt(toMatch[2], 10) - 1;
      const toDay = parseInt(toMatch[3], 10);

      const fromStart = new Date(Date.UTC(fromYear, fromMonth, fromDay, 0, 0, 0, 0));
      const toEnd = new Date(Date.UTC(toYear, toMonth, toDay, 23, 59, 59, 999));

      if (isNaN(fromStart.getTime()) || isNaN(toEnd.getTime())) {
        return reply.code(400).send({ code: 'invalid_date', message: 'Invalid calendar date' });
      }

      if (toEnd.getTime() < fromStart.getTime()) {
        return reply.code(400).send({ code: 'invalid_range', message: "'to' date must be on or after 'from' date" });
      }

      // Max 366 days
      const daysCount = Math.round((Date.UTC(toYear, toMonth, toDay) - Date.UTC(fromYear, fromMonth, fromDay)) / 86400000) + 1;
      if (daysCount > 366) {
        return reply.code(400).send({ code: 'range_too_large', message: 'Date range cannot exceed 366 days' });
      }

      // 1. opened in range
      const openedRes = await db.execute<{ count: string | number }>(
        sql`SELECT COUNT(*)::int AS count
            FROM tickets
            WHERE guild_id = ${guildId}
              AND created_at >= ${fromStart}
              AND created_at <= ${toEnd}`
      );
      const opened = Number((openedRes.rows?.[0] as any)?.count ?? (openedRes as any)[0]?.count ?? 0);

      // 2. closed in range
      const closedRes = await db.execute<{ count: string | number }>(
        sql`SELECT COUNT(*)::int AS count
            FROM tickets
            WHERE guild_id = ${guildId}
              AND closed_at >= ${fromStart}
              AND closed_at <= ${toEnd}`
      );
      const closed = Number((closedRes.rows?.[0] as any)?.count ?? (closedRes as any)[0]?.count ?? 0);

      // 3. open_now (status IN ('open', 'claimed'))
      const openNowRes = await db.execute<{ count: string | number }>(
        sql`SELECT COUNT(*)::int AS count
            FROM tickets
            WHERE guild_id = ${guildId}
              AND status IN ('open', 'claimed')`
      );
      const open_now = Number((openNowRes.rows?.[0] as any)?.count ?? (openNowRes as any)[0]?.count ?? 0);

      // 4. median_first_response_s (percentile_cont(0.5))
      const medianFirstRes = await db.execute<{ median: string | number | null }>(
        sql`SELECT percentile_cont(0.5) WITHIN GROUP (
              ORDER BY EXTRACT(EPOCH FROM (first_response_at - created_at))::float
            ) AS median
            FROM tickets
            WHERE guild_id = ${guildId}
              AND created_at >= ${fromStart}
              AND created_at <= ${toEnd}
              AND first_response_at IS NOT NULL
              AND first_response_at >= created_at`
      );
      const mfrVal = (medianFirstRes.rows?.[0] as any)?.median ?? (medianFirstRes as any)[0]?.median;
      const median_first_response_s = mfrVal != null ? Math.round(Number(mfrVal) * 100) / 100 : null;

      // 5. median_close_s (percentile_cont(0.5))
      const medianCloseRes = await db.execute<{ median: string | number | null }>(
        sql`SELECT percentile_cont(0.5) WITHIN GROUP (
              ORDER BY EXTRACT(EPOCH FROM (closed_at - created_at))::float
            ) AS median
            FROM tickets
            WHERE guild_id = ${guildId}
              AND closed_at >= ${fromStart}
              AND closed_at <= ${toEnd}
              AND closed_at IS NOT NULL
              AND closed_at >= created_at`
      );
      const mcVal = (medianCloseRes.rows?.[0] as any)?.median ?? (medianCloseRes as any)[0]?.median;
      const median_close_s = mcVal != null ? Math.round(Number(mcVal) * 100) / 100 : null;

      // 6. rating_avg and rating_count
      const ratingsRes = await db.execute<{ avg_score: string | number | null; count: string | number }>(
        sql`SELECT
              AVG(score)::float AS avg_score,
              COUNT(*)::int AS count
            FROM ratings
            WHERE guild_id = ${guildId}
              AND created_at >= ${fromStart}
              AND created_at <= ${toEnd}`
      );
      const rRow = (ratingsRes.rows?.[0] as any) ?? (ratingsRes as any)[0];
      const rating_count = Number(rRow?.count ?? 0);
      const rating_avg = rRow?.avg_score != null && rating_count > 0 ? Math.round(Number(rRow.avg_score) * 100) / 100 : null;

      // 7. daily: [{ date, opened, closed }] in UTC, zero-filled for days with no tickets
      const dailyMap = new Map<string, { date: string; opened: number; closed: number }>();
      const curDate = new Date(fromStart);
      while (curDate <= toEnd) {
        const dateStr = curDate.toISOString().slice(0, 10);
        dailyMap.set(dateStr, { date: dateStr, opened: 0, closed: 0 });
        curDate.setUTCDate(curDate.getUTCDate() + 1);
      }

      const dailyOpenedRes = await db.execute<{ day: string; count: string | number }>(
        sql`SELECT
              to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD') AS day,
              COUNT(*)::int AS count
            FROM tickets
            WHERE guild_id = ${guildId}
              AND created_at >= ${fromStart}
              AND created_at <= ${toEnd}
            GROUP BY day`
      );
      const openedRows = dailyOpenedRes.rows ?? (dailyOpenedRes as any) ?? [];
      for (const r of openedRows) {
        const item = dailyMap.get(r.day);
        if (item) item.opened = Number(r.count);
      }

      const dailyClosedRes = await db.execute<{ day: string; count: string | number }>(
        sql`SELECT
              to_char(closed_at AT TIME ZONE 'UTC', 'YYYY-MM-DD') AS day,
              COUNT(*)::int AS count
            FROM tickets
            WHERE guild_id = ${guildId}
              AND closed_at >= ${fromStart}
              AND closed_at <= ${toEnd}
            GROUP BY day`
      );
      const closedRows = dailyClosedRes.rows ?? (dailyClosedRes as any) ?? [];
      for (const r of closedRows) {
        const item = dailyMap.get(r.day);
        if (item) item.closed = Number(r.count);
      }

      const daily = Array.from(dailyMap.values());

      // 8. by_category: [{ category_id, name, opened }]
      const byCatRes = await db.execute<{ category_id: string; name: string; opened: string | number }>(
        sql`SELECT
              c.id AS category_id,
              c.name AS name,
              COUNT(t.id)::int AS opened
            FROM categories c
            LEFT JOIN tickets t ON t.category_id = c.id
              AND t.created_at >= ${fromStart}
              AND t.created_at <= ${toEnd}
            WHERE c.guild_id = ${guildId}
            GROUP BY c.id, c.name
            ORDER BY opened DESC, c.name ASC`
      );
      const catRows = byCatRes.rows ?? (byCatRes as any) ?? [];
      const by_category = catRows.map((r: any) => ({
        category_id: r.category_id,
        categoryId: r.category_id,
        name: r.name,
        opened: Number(r.opened),
      }));

      // 9. staff: [{ user_id, claimed, closed, rating_avg }]
      const staffTicketsRes = await db.execute<{
        user_id: string;
        claimed: string | number;
        closed: string | number;
      }>(
        sql`SELECT
              t.claimer_id AS user_id,
              COUNT(t.id)::int AS claimed,
              COUNT(CASE WHEN t.status = 'closed' OR t.closed_at IS NOT NULL THEN 1 END)::int AS closed
            FROM tickets t
            WHERE t.guild_id = ${guildId}
              AND t.claimer_id IS NOT NULL
              AND (
                (t.created_at >= ${fromStart} AND t.created_at <= ${toEnd})
                OR (t.closed_at >= ${fromStart} AND t.closed_at <= ${toEnd})
              )
            GROUP BY t.claimer_id`
      );

      const staffRatingsRes = await db.execute<{
        user_id: string;
        avg_score: string | number | null;
      }>(
        sql`SELECT
              r.staff_id AS user_id,
              AVG(r.score)::float AS avg_score
            FROM ratings r
            WHERE r.guild_id = ${guildId}
              AND r.staff_id IS NOT NULL
              AND r.created_at >= ${fromStart}
              AND r.created_at <= ${toEnd}
            GROUP BY r.staff_id`
      );

      const staffRatingsMap = new Map<string, number>();
      for (const r of (staffRatingsRes.rows ?? (staffRatingsRes as any) ?? [])) {
        if (r.avg_score != null) {
          staffRatingsMap.set(r.user_id, Math.round(Number(r.avg_score) * 100) / 100);
        }
      }

      const staffMap = new Map<string, { user_id: string; claimed: number; closed: number; rating_avg: number | null }>();
      for (const r of (staffTicketsRes.rows ?? (staffTicketsRes as any) ?? [])) {
        staffMap.set(r.user_id, {
          user_id: r.user_id,
          claimed: Number(r.claimed),
          closed: Number(r.closed),
          rating_avg: staffRatingsMap.get(r.user_id) ?? null,
        });
      }
      for (const [userId, avgScore] of staffRatingsMap.entries()) {
        if (!staffMap.has(userId)) {
          staffMap.set(userId, {
            user_id: userId,
            claimed: 0,
            closed: 0,
            rating_avg: avgScore,
          });
        }
      }

      const staff = Array.from(staffMap.values()).map((s) => ({
        user_id: s.user_id,
        userId: s.user_id,
        claimed: s.claimed,
        closed: s.closed,
        rating_avg: s.rating_avg,
        ratingAverage: s.rating_avg,
      }));

      return reply.send({
        opened,
        closed,
        open_now,
        openNow: open_now,
        median_first_response_s,
        medianFirstResponseSeconds: median_first_response_s,
        median_close_s,
        medianResolutionSeconds: median_close_s,
        rating_avg,
        ratingAverage: rating_avg,
        rating_count,
        ratingCount: rating_count,
        daily,
        by_category,
        byCategory: by_category,
        staff,
        byStaff: staff,
      });
    }
  );
}
