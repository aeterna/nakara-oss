import { describe, it, expect, beforeAll, beforeEach, afterAll } from 'vitest';
import { eq } from 'drizzle-orm';
import { openTestDb, type TestDbHandle } from '../test-support/pglite.js';
import { ensureGuild, guilds } from '../src/index.js';

describe('ensureGuild (placeholder never overwrites a real name)', () => {
  let env: TestDbHandle;
  const ID = '123456789012345678';

  beforeAll(async () => { env = await openTestDb(); });
  afterAll(async () => { await env.close(); });
  beforeEach(async () => { await env.reset(); });

  it('placeholder never overwrites a real name, but real name updates', async () => {
    // 1. Initial insert with real name
    await ensureGuild(env.db, ID, 'Official Server');

    // 2. Placeholder attempts (Guild <id> or literal "Guild <id>") do not overwrite
    const p1 = await ensureGuild(env.db, ID, `Guild ${ID}`);
    expect(p1.name).toBe('Official Server');
    const p2 = await ensureGuild(env.db, ID, 'Guild <id>');
    expect(p2.name).toBe('Official Server');

    const [row1] = await env.db.select().from(guilds).where(eq(guilds.guild_id, ID));
    expect(row1.name).toBe('Official Server');

    // 3. Updating with a new real name succeeds
    const u = await ensureGuild(env.db, ID, 'Renamed Server');
    expect(u.name).toBe('Renamed Server');
    const [row2] = await env.db.select().from(guilds).where(eq(guilds.guild_id, ID));
    expect(row2.name).toBe('Renamed Server');
  });

  it('updates placeholder with real name', async () => {
    await ensureGuild(env.db, ID, `Guild ${ID}`);
    const u = await ensureGuild(env.db, ID, 'Nakara City');
    expect(u.name).toBe('Nakara City');
    const [row] = await env.db.select().from(guilds).where(eq(guilds.guild_id, ID));
    expect(row.name).toBe('Nakara City');
  });
});
