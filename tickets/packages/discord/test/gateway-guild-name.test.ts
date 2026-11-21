import { describe, it, expect, vi, beforeAll, beforeEach, afterAll } from 'vitest';
import { EventEmitter } from 'node:events';
import { eq } from 'drizzle-orm';
import { openTestDb, type TestDbHandle } from '@nakara-tickets/db/test-support';
import { guilds } from '@nakara-tickets/db';
import { startGateway } from '../src/gateway.js';

describe('gateway guild name sync (guildUpdate renames)', () => {
  let env: TestDbHandle;
  const ID = '111111111111111111';
  const BAD_ID = '222222222222222222';

  beforeAll(async () => { env = await openTestDb(); });
  afterAll(async () => { await env.close(); });
  beforeEach(async () => { await env.reset(); });

  it('guildUpdate renames allowed guild and ignores unauthorized guild', async () => {
    await env.db.insert(guilds).values({ guild_id: ID, name: 'Original Name' });

    class MockClient extends EventEmitter {
      guilds = { cache: new Map([[ID, { id: ID, name: 'Ready Name' }]]) };
      login = vi.fn().mockResolvedValue('ok');
      destroy = vi.fn().mockResolvedValue(undefined);
    }
    const client = new MockClient();

    const gateway = await startGateway({
      token: 'tok', appId: 'app', allowedGuildIds: [ID], db: env.db,
      pool: { connect: vi.fn().mockResolvedValue({ query: vi.fn().mockResolvedValue({ rows: [{ locked: true }] }), release: vi.fn() }) } as any,
      dataKey: Buffer.alloc(32, 9), client: client as any,
      log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    });

    // 1. clientReady stores cached allowed guild name
    client.emit('clientReady');
    await new Promise((r) => setTimeout(r, 20));
    const [readyRow] = await env.db.select().from(guilds).where(eq(guilds.guild_id, ID));
    expect(readyRow.name).toBe('Ready Name');

    // 2. guildUpdate renames allowed guild
    client.emit('guildUpdate', { id: ID, name: 'Ready Name' }, { id: ID, name: 'Renamed Guild' });
    await new Promise((r) => setTimeout(r, 20));
    const [row] = await env.db.select().from(guilds).where(eq(guilds.guild_id, ID));
    expect(row.name).toBe('Renamed Guild');

    // 3. guildUpdate ignores unauthorized guild
    client.emit('guildUpdate', { id: BAD_ID, name: 'Bad' }, { id: BAD_ID, name: 'Hacked' });
    await new Promise((r) => setTimeout(r, 20));
    const badRows = await env.db.select().from(guilds).where(eq(guilds.guild_id, BAD_ID));
    expect(badRows).toHaveLength(0);

    await gateway.stop();
  });
});
