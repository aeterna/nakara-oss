import { describe, it, expect, beforeAll, beforeEach, afterAll } from 'vitest';
import { openTestDb, type TestDbHandle } from '@nakara-tickets/db/test-support';
import { guilds, categories, tickets, ratings } from '@nakara-tickets/db';
import { buildApp } from '../src/app.js';
import type { FastifyInstance } from 'fastify';

describe('stats route (acceptance tests s1, s2)', () => {
  let testDb: TestDbHandle;
  let app: FastifyInstance;

  beforeAll(async () => {
    testDb = await openTestDb();
    app = buildApp({ db: testDb.db });
    // Stub requireStaff for testing
    app.decorate('requireStaff', async (req: any) => {
      req.guildId = req.params?.guildId || 'guild-1';
      req.user = { id: 'staff-1', username: 'staff1', avatar: null };
    });
    await app.ready();
  });

  afterAll(async () => {
    await app.close();
    await testDb.close();
  });

  beforeEach(async () => {
    await testDb.reset();
  });

  it('s1: medians correct for odd/even counts, zero-filled days, other guild excluded', async () => {
    const db = testDb.db;
    const guildId = 'guild-1';
    const otherGuildId = 'guild-other';

    // Seed guilds
    await db.insert(guilds).values([
      { guild_id: guildId, name: 'Main Guild' },
      { guild_id: otherGuildId, name: 'Other Guild' },
    ]);

    // Seed categories
    const [cat1] = await db
      .insert(categories)
      .values([
        {
          guild_id: guildId,
          name: 'General Support',
          parent_channel_id: '111',
          mode: 'thread',
        },
      ])
      .returning();

    const [cat2] = await db
      .insert(categories)
      .values([
        {
          guild_id: guildId,
          name: 'Billing',
          parent_channel_id: '112',
          mode: 'thread',
        },
      ])
      .returning();

    const [otherCat] = await db
      .insert(categories)
      .values([
        {
          guild_id: otherGuildId,
          name: 'Other Guild Category',
          parent_channel_id: '999',
          mode: 'thread',
        },
      ])
      .returning();

    // Range: 2026-11-01 to 2026-11-05 (5 days)
    // We will place tickets on 2026-11-02 and 2026-11-04, leaving 2026-11-01, 2026-11-03, 2026-11-05 with zero opened
    const t1Created = new Date('2026-11-02T10:00:00Z');
    const t1Resp = new Date('2026-11-02T10:01:00Z'); // 60s
    const t1Closed = new Date('2026-11-02T10:01:40Z'); // 100s

    const t2Created = new Date('2026-11-02T11:00:00Z');
    const t2Resp = new Date('2026-11-02T11:02:00Z'); // 120s
    const t2Closed = new Date('2026-11-02T11:03:20Z'); // 200s

    const t3Created = new Date('2026-11-04T12:00:00Z');
    const t3Resp = new Date('2026-11-04T12:05:00Z'); // 300s
    const t3Closed = new Date('2026-11-04T12:05:00Z'); // 300s

    const t4Created = new Date('2026-11-04T13:00:00Z');
    // t4 has no first response yet (open ticket)
    const t4Closed = new Date('2026-11-04T13:06:40Z'); // 400s

    // Insert 4 tickets into guild-1
    // Odd count (3) for first response times: 60s, 120s, 300s -> median = 120s
    // Even count (4) for close times: 100s, 200s, 300s, 400s -> median = (200 + 300) / 2 = 250s
    const [t1, t2, t3, t4] = await db
      .insert(tickets)
      .values([
        {
          guild_id: guildId,
          number: 1,
          category_id: cat1.id,
          opener_id: 'user-1',
          claimer_id: 'staff-a',
          channel_id: 'chan-1',
          status: 'closed',
          created_at: t1Created,
          first_response_at: t1Resp,
          closed_at: t1Closed,
        },
        {
          guild_id: guildId,
          number: 2,
          category_id: cat1.id,
          opener_id: 'user-2',
          claimer_id: 'staff-a',
          channel_id: 'chan-2',
          status: 'closed',
          created_at: t2Created,
          first_response_at: t2Resp,
          closed_at: t2Closed,
        },
        {
          guild_id: guildId,
          number: 3,
          category_id: cat2.id,
          opener_id: 'user-3',
          claimer_id: 'staff-b',
          channel_id: 'chan-3',
          status: 'closed',
          created_at: t3Created,
          first_response_at: t3Resp,
          closed_at: t3Closed,
        },
        {
          guild_id: guildId,
          number: 4,
          category_id: cat2.id,
          opener_id: 'user-4',
          claimer_id: 'staff-b',
          channel_id: 'chan-4',
          status: 'closed',
          created_at: t4Created,
          first_response_at: null,
          closed_at: t4Closed,
        },
      ])
      .returning();

    // Insert currently open ticket in guild-1
    await db.insert(tickets).values({
      guild_id: guildId,
      number: 5,
      category_id: cat1.id,
      opener_id: 'user-5',
      channel_id: 'chan-5',
      status: 'open',
      created_at: new Date('2026-11-04T15:00:00Z'),
    });

    // Insert ratings for guild-1
    await db.insert(ratings).values([
      {
        guild_id: guildId,
        ticket_id: t1.id,
        user_id: 'user-1',
        staff_id: 'staff-a',
        score: 5,
        feedback: 'Excellent',
        created_at: new Date('2026-11-02T10:05:00Z'),
      },
      {
        guild_id: guildId,
        ticket_id: t2.id,
        user_id: 'user-2',
        staff_id: 'staff-a',
        score: 4,
        feedback: 'Good',
        created_at: new Date('2026-11-02T11:10:00Z'),
      },
      {
        guild_id: guildId,
        ticket_id: t3.id,
        user_id: 'user-3',
        staff_id: 'staff-b',
        score: 3,
        feedback: 'Average',
        created_at: new Date('2026-11-04T12:10:00Z'),
      },
    ]);

    // Insert conflicting tickets & ratings into OTHER guild (should be strictly excluded)
    await db.insert(tickets).values([
      {
        guild_id: otherGuildId,
        number: 1,
        category_id: otherCat.id,
        opener_id: 'user-other',
        claimer_id: 'staff-other',
        channel_id: 'chan-other',
        status: 'closed',
        created_at: new Date('2026-11-01T10:00:00Z'),
        first_response_at: new Date('2026-11-01T10:00:10Z'), // 10s
        closed_at: new Date('2026-11-01T10:00:20Z'), // 20s
      },
    ]);
    await db.insert(ratings).values([
      {
        guild_id: otherGuildId,
        ticket_id: t1.id,
        user_id: 'user-other',
        staff_id: 'staff-other',
        score: 1,
        created_at: new Date('2026-11-01T10:05:00Z'),
      },
    ]);

    // Request stats for guild-1
    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${guildId}/stats?from=2026-11-01&to=2026-11-05`,
    });

    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body);

    // Opened: 5 tickets opened in guild-1 during range
    expect(body.opened).toBe(5);
    // Closed: 4 tickets closed
    expect(body.closed).toBe(4);
    // Open now: 1 ticket currently open
    expect(body.open_now).toBe(1);

    // Medians:
    // Odd count (3 items: 60, 120, 300) -> 120
    expect(body.median_first_response_s).toBe(120);
    // Even count (4 items: 100, 200, 300, 400) -> 250
    expect(body.median_close_s).toBe(250);

    // Ratings: 3 ratings (5, 4, 3) -> avg = 4.0, count = 3
    expect(body.rating_count).toBe(3);
    expect(body.rating_avg).toBe(4);

    // Zero-filled days verification:
    // Range is 2026-11-01 to 2026-11-05: 5 distinct days
    expect(body.daily).toHaveLength(5);
    expect(body.daily.map((d: any) => d.date)).toEqual([
      '2026-11-01',
      '2026-11-02',
      '2026-11-03',
      '2026-11-04',
      '2026-11-05',
    ]);

    // 2026-11-01 had 0 tickets in guild-1
    const day1 = body.daily.find((d: any) => d.date === '2026-11-01');
    expect(day1.opened).toBe(0);
    expect(day1.closed).toBe(0);

    // 2026-11-02 had 2 opened, 2 closed
    const day2 = body.daily.find((d: any) => d.date === '2026-11-02');
    expect(day2.opened).toBe(2);
    expect(day2.closed).toBe(2);

    // 2026-11-03 had 0 opened, 0 closed
    const day3 = body.daily.find((d: any) => d.date === '2026-11-03');
    expect(day3.opened).toBe(0);
    expect(day3.closed).toBe(0);

    // 2026-11-04 had 3 opened (t3, t4, t5), 2 closed (t3, t4)
    const day4 = body.daily.find((d: any) => d.date === '2026-11-04');
    expect(day4.opened).toBe(3);
    expect(day4.closed).toBe(2);

    // 2026-11-05 had 0 opened, 0 closed
    const day5 = body.daily.find((d: any) => d.date === '2026-11-05');
    expect(day5.opened).toBe(0);
    expect(day5.closed).toBe(0);

    // Categories: cat1 has 3 opened, cat2 has 2 opened
    expect(body.by_category).toHaveLength(2);
    const cat1Stats = body.by_category.find((c: any) => c.category_id === cat1.id);
    expect(cat1Stats.opened).toBe(3);
    const cat2Stats = body.by_category.find((c: any) => c.category_id === cat2.id);
    expect(cat2Stats.opened).toBe(2);

    // Staff stats:
    // staff-a: claimed 2, closed 2, ratings: 5 & 4 -> avg 4.5
    // staff-b: claimed 2, closed 2, ratings: 3 -> avg 3.0
    const staffA = body.staff.find((s: any) => s.user_id === 'staff-a');
    expect(staffA).toBeDefined();
    expect(staffA.claimed).toBe(2);
    expect(staffA.closed).toBe(2);
    expect(staffA.rating_avg).toBe(4.5);

    const staffB = body.staff.find((s: any) => s.user_id === 'staff-b');
    expect(staffB).toBeDefined();
    expect(staffB.claimed).toBe(2);
    expect(staffB.closed).toBe(2);
    expect(staffB.rating_avg).toBe(3);
  });

  it('s2: range > 366 days → 400', async () => {
    // 2025-01-01 to 2026-01-03 is 368 days > 366 days
    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/guilds/guild-1/stats?from=2025-01-01&to=2026-01-03',
    });

    expect(res.statusCode).toBe(400);
    const body = JSON.parse(res.body);
    expect(body.code).toBeDefined();

    // Negative control: valid range <= 366 days returns 200
    const validRes = await app.inject({
      method: 'GET',
      url: '/api/v1/guilds/guild-1/stats?from=2026-01-01&to=2026-01-30',
    });
    expect(validRes.statusCode).toBe(200);

    // Invalid date formats return 400
    const invalidRes = await app.inject({
      method: 'GET',
      url: '/api/v1/guilds/guild-1/stats?from=not-a-date&to=2026-01-30',
    });
    expect(invalidRes.statusCode).toBe(400);

    // 'to' before 'from' returns 400
    const reverseRes = await app.inject({
      method: 'GET',
      url: '/api/v1/guilds/guild-1/stats?from=2026-02-01&to=2026-01-01',
    });
    expect(reverseRes.statusCode).toBe(400);
  });
});
