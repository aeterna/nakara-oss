import pg from 'pg';
import { drizzle } from 'drizzle-orm/node-postgres';
import * as schema from '@nakara-tickets/db';
import type { TicketsDb } from '@nakara-tickets/db';

const { Pool } = pg;

export type { TicketsDb };

export interface DatabaseHandle {
  db: TicketsDb;
  pool: pg.Pool;
  close: () => Promise<void>;
}

export function createDb(url: string): DatabaseHandle {
  const pool = new Pool({ connectionString: url });
  const db = drizzle(pool, { schema }) as unknown as TicketsDb;
  return {
    db,
    pool,
    async close() {
      await pool.end();
    },
  };
}
