import pg from 'pg';
import { drizzle } from 'drizzle-orm/node-postgres';
import { migrate as defaultMigrate } from 'drizzle-orm/node-postgres/migrator';

const { Pool } = pg;

export interface MigrateOptions {
  pool?: pg.Pool;
  db?: any;
  migrator?: (db: any, config: { migrationsFolder: string }) => Promise<void>;
}

export interface MigrateResult {
  applied: number;
}

/**
 * Runs Drizzle migrations against the target Postgres database.
 * Never logs the database URL or credentials.
 * Logs the number of applied migrations upon completion.
 */
export async function runMigrations(
  databaseUrl: string,
  migrationsFolder: string,
  options?: MigrateOptions,
): Promise<MigrateResult> {
  const pool = options?.pool ?? new Pool({ connectionString: databaseUrl });
  const db = options?.db ?? drizzle(pool);
  const migrator = options?.migrator ?? defaultMigrate;

  try {
    let beforeCount = 0;
    try {
      const res = await pool.query<{ count: string }>(
        'SELECT count(*)::int as count FROM "drizzle"."__drizzle_migrations"'
      );
      beforeCount = parseInt(res.rows[0]?.count ?? '0', 10);
    } catch {
      // The drizzle migration journal table does not exist on first run
      beforeCount = 0;
    }

    await migrator(db, { migrationsFolder });

    let afterCount = 0;
    try {
      const res = await pool.query<{ count: string }>(
        'SELECT count(*)::int as count FROM "drizzle"."__drizzle_migrations"'
      );
      afterCount = parseInt(res.rows[0]?.count ?? '0', 10);
    } catch {
      afterCount = 0;
    }

    const applied = Math.max(0, afterCount - beforeCount);
    console.log(`Applied ${applied} migration(s)`);
    return { applied };
  } catch {
    console.error('Migration failed');
    throw new Error('Migration failed');
  } finally {
    await pool.end();
  }
}
