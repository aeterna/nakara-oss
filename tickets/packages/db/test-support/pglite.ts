import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import { readdirSync, readFileSync } from 'node:fs';
import * as schema from '../src/schema.js';
import type { TicketsDb } from '../src/index.js';

export interface TestDbHandle {
  db: TicketsDb;
  pg: PGlite;
  client?: PGlite;
  reset: () => Promise<void>;
  close: () => Promise<void>;
}

const ALL_TABLES = [
  'attachments',
  'audit_log',
  'blocks',
  'bridge_nonces',
  'categories',
  'data_requests',
  'game_actions',
  'game_servers',
  'guild_settings',
  'guilds',
  'messages',
  'pair_codes',
  'panels',
  'ratings',
  'sessions',
  'tags',
  'ticket_members',
  'tickets',
];

const TRUNCATE_SQL = `TRUNCATE ${ALL_TABLES.join(', ')} RESTART IDENTITY CASCADE;`;

export async function openTestDb(): Promise<TestDbHandle> {
  const pg = new PGlite();
  const migrationsDir = new URL('../migrations/', import.meta.url);
  const files = readdirSync(migrationsDir)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  for (const file of files) {
    const sql = readFileSync(new URL(file, migrationsDir), 'utf-8');
    const statements = sql
      .split('--> statement-breakpoint')
      .map((s) => s.trim())
      .filter((s) => s.length > 0);
    for (const stmt of statements) {
      await pg.exec(stmt);
    }
  }

  const db = drizzle(pg, { schema }) as TicketsDb;

  return {
    db,
    pg,
    get client() {
      return pg;
    },
    async reset() {
      await pg.exec(TRUNCATE_SQL);
    },
    async close() {
      await pg.close();
    },
  };
}
