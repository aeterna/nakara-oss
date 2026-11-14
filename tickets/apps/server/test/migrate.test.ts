import { describe, it, expect, vi } from 'vitest';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import { migrate } from 'drizzle-orm/pglite/migrator';
import { runMigrations } from '../src/migrate.js';

const EXPECTED_TABLES = [
  'guilds',
  'guild_settings',
  'categories',
  'panels',
  'tickets',
  'ticket_members',
  'messages',
  'attachments',
  'ratings',
  'tags',
  'blocks',
  'game_servers',
  'pair_codes',
  'bridge_nonces',
  'game_actions',
  'data_requests',
  'audit_log',
  'sessions',
] as const;

describe('migrate acceptance tests', () => {
  const migrationsFolder = fileURLToPath(new URL('../../../packages/db/migrations', import.meta.url));

  it('(m1) all 18 tables exist after migrating with pglite, and migrating twice is a no-op', async () => {
    const client = new PGlite();
    const db = drizzle(client);

    // Negative control: before migration, tables do not exist
    const preCheck = await client.query<{ table_name: string }>(
      "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';"
    );
    const preTables = preCheck.rows.map((r) => r.table_name);
    for (const table of EXPECTED_TABLES) {
      expect(preTables).not.toContain(table);
    }

    // First migration run: creates all 18 tables
    await migrate(db, { migrationsFolder });

    const postCheck = await client.query<{ table_name: string }>(
      "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';"
    );
    const postTables = postCheck.rows.map((r) => r.table_name);

    expect(postTables.length).toBeGreaterThanOrEqual(18);
    for (const table of EXPECTED_TABLES) {
      expect(postTables, `table ${table} must exist after migration`).toContain(table);
    }

    const firstJournal = await client.query<{ count: string }>(
      'SELECT count(*)::int as count FROM "drizzle"."__drizzle_migrations";'
    );
    const migrationCountAfterFirst = parseInt(firstJournal.rows[0]?.count ?? '0', 10);
    expect(migrationCountAfterFirst).toBeGreaterThan(0);

    // Second migration run: must be a no-op and succeed without throwing
    await migrate(db, { migrationsFolder });

    const secondJournal = await client.query<{ count: string }>(
      'SELECT count(*)::int as count FROM "drizzle"."__drizzle_migrations";'
    );
    const migrationCountAfterSecond = parseInt(secondJournal.rows[0]?.count ?? '0', 10);

    expect(migrationCountAfterSecond).toBe(migrationCountAfterFirst);

    // Verify all 18 tables are still present and intact
    const finalCheck = await client.query<{ table_name: string }>(
      "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';"
    );
    const finalTables = finalCheck.rows.map((r) => r.table_name);
    for (const table of EXPECTED_TABLES) {
      expect(finalTables).toContain(table);
    }
  });

  it('runMigrations never logs database URL, passwords, or secrets', async () => {
    const sensitiveUrl = 'postgres://admin_user:super_secret_pw_98765@db.example.internal:5432/nakara_tickets';
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

    try {
      // Mock pool that simulates migration error to verify error handling never logs the URL
      const mockPool = {
        query: vi.fn().mockRejectedValue(new Error('connection failure')),
        end: vi.fn().mockResolvedValue(undefined),
      };

      await expect(
        runMigrations(sensitiveUrl, migrationsFolder, { pool: mockPool as any })
      ).rejects.toThrow();

      // Check all console output: sensitive URL and password must NEVER appear
      for (const call of [...logSpy.mock.calls, ...errorSpy.mock.calls]) {
        const text = call.map((c) => String(c)).join(' ');
        expect(text).not.toContain(sensitiveUrl);
        expect(text).not.toContain('super_secret_pw_98765');
        expect(text).not.toContain('admin_user');
      }
    } finally {
      logSpy.mockRestore();
      errorSpy.mockRestore();
    }
  });

  it('runMigrations logs applied count upon successful execution', async () => {
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

    try {
      let queryCalls = 0;
      const mockPool = {
        query: vi.fn().mockImplementation(async () => {
          queryCalls++;
          // First call: beforeCount = 0
          // Second call: afterCount = 1
          return { rows: [{ count: queryCalls === 1 ? '0' : '1' }] };
        }),
        end: vi.fn().mockResolvedValue(undefined),
      };

      const mockDb = {} as any;
      const mockMigrator = vi.fn().mockResolvedValue(undefined);

      const result = await runMigrations(
        'postgres://mock:mock@localhost:5432/mock',
        migrationsFolder,
        { pool: mockPool as any, db: mockDb, migrator: mockMigrator }
      );

      expect(result).toEqual({ applied: 1 });

      const logOutput = logSpy.mock.calls.map((c) => c.join(' ')).join('\n');
      expect(logOutput).toMatch(/applied 1 migration/i);
    } finally {
      logSpy.mockRestore();
      errorSpy.mockRestore();
    }
  });
});
