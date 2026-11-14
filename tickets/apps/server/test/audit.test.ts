import { describe, it, expect, beforeAll, beforeEach, afterAll } from 'vitest';
import { openTestDb, type TestDbHandle } from '@nakara-tickets/db/test-support';
import { guilds, auditLog } from '@nakara-tickets/db';
import { buildApp } from '../src/app.js';
import type { FastifyInstance } from 'fastify';

describe('audit route (acceptance test s5)', () => {
  let testDb: TestDbHandle;
  let app: FastifyInstance;

  beforeAll(async () => {
    testDb = await openTestDb();
    app = buildApp({ db: testDb.db });
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

  it('s5: audit pagination and action filtering', async () => {
    const db = testDb.db;
    const guildId = 'guild-1';
    const otherGuildId = 'guild-other';

    await db.insert(guilds).values([
      { guild_id: guildId, name: 'Main Guild' },
      { guild_id: otherGuildId, name: 'Other Guild' },
    ]);

    // Insert 12 audit records with distinct timestamps into guild-1
    // Base time: 2026-11-01T10:00:00Z, each subsequent entry 1 minute later
    const entries = [];
    for (let i = 1; i <= 12; i++) {
      const isClose = i % 3 === 0;
      const isClaim = i % 3 === 1;
      const kind = isClose ? 'ticket.close' : isClaim ? 'ticket.claim' : 'settings.update';
      const time = new Date(new Date('2026-11-01T10:00:00Z').getTime() + i * 60000);

      entries.push({
        guild_id: guildId,
        actor_id: `actor-${i}`,
        kind,
        target: `target-${i}`,
        detail: { index: i },
        created_at: time,
      });
    }

    await db.insert(auditLog).values(entries);

    // Insert entry in other guild to ensure guild separation
    await db.insert(auditLog).values({
      guild_id: otherGuildId,
      actor_id: 'actor-other',
      kind: 'ticket.close',
      target: 'target-other',
      created_at: new Date('2026-11-01T12:00:00Z'),
    });

    // Page 1: limit 5
    const res1 = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${guildId}/audit?limit=5`,
    });

    expect(res1.statusCode).toBe(200);
    const body1 = JSON.parse(res1.body);
    expect(body1.items).toHaveLength(5);
    // Newest first: indexes should be 12, 11, 10, 9, 8
    expect(body1.items[0].detail.index).toBe(12);
    expect(body1.items[4].detail.index).toBe(8);
    expect(body1.next).toBeTruthy();

    // Page 2: pass cursor from page 1
    const res2 = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${guildId}/audit?limit=5&cursor=${encodeURIComponent(body1.next)}`,
    });

    expect(res2.statusCode).toBe(200);
    const body2 = JSON.parse(res2.body);
    expect(body2.items).toHaveLength(5);
    // Indexes: 7, 6, 5, 4, 3
    expect(body2.items[0].detail.index).toBe(7);
    expect(body2.items[4].detail.index).toBe(3);
    expect(body2.next).toBeTruthy();

    // Verify no overlap between page 1 and page 2
    const page1Ids = new Set(body1.items.map((it: any) => it.id));
    for (const item of body2.items) {
      expect(page1Ids.has(item.id)).toBe(false);
    }

    // Page 3: final page
    const res3 = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${guildId}/audit?limit=5&cursor=${encodeURIComponent(body2.next)}`,
    });

    expect(res3.statusCode).toBe(200);
    const body3 = JSON.parse(res3.body);
    expect(body3.items).toHaveLength(2);
    // Indexes: 2, 1
    expect(body3.items[0].detail.index).toBe(2);
    expect(body3.items[1].detail.index).toBe(1);
    expect(body3.next).toBeNull();

    // Verify filter by action ('ticket.close')
    // Out of 12 items, indexes 3, 6, 9, 12 are 'ticket.close' (4 items)
    const resFilter = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${guildId}/audit?action=ticket.close`,
    });

    expect(resFilter.statusCode).toBe(200);
    const bodyFilter = JSON.parse(resFilter.body);
    expect(bodyFilter.items).toHaveLength(4);
    for (const item of bodyFilter.items) {
      expect(item.kind).toBe('ticket.close');
    }
    // Newest first: 12, 9, 6, 3
    expect(bodyFilter.items.map((i: any) => i.detail.index)).toEqual([12, 9, 6, 3]);

    // Negative control: non-existent action returns empty items
    const resEmpty = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${guildId}/audit?action=non.existent`,
    });
    expect(resEmpty.statusCode).toBe(200);
    const bodyEmpty = JSON.parse(resEmpty.body);
    expect(bodyEmpty.items).toHaveLength(0);
    expect(bodyEmpty.next).toBeNull();
  });
});
