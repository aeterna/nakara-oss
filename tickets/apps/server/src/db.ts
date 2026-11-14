import pg from 'pg';
import { drizzle, type NodePgDatabase } from 'drizzle-orm/node-postgres';
import * as schema from '@nakara-tickets/db';

const { Pool } = pg;

export type TicketsDb = NodePgDatabase<typeof schema>;

export interface DatabaseHandle {
  db: TicketsDb;
  pool: pg.Pool;
  close: () => Promise<void>;
}

export function createDb(url: string): DatabaseHandle {
  const pool = new Pool({ connectionString: url });
  const db = drizzle(pool, { schema });
  return {
    db,
    pool,
    async close() {
      await pool.end();
    },
  };
}
