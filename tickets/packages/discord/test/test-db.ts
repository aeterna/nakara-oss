import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import * as schema from '@nakara-tickets/db';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { TicketsDb } from '@nakara-tickets/db';

export async function createTestDb(): Promise<{ client: PGlite; db: TicketsDb }> {
  const client = new PGlite();
  const here = dirname(fileURLToPath(import.meta.url));
  const migrationPath = resolve(here, '../../../db/migrations/0000_init.sql');
  const sql = readFileSync(migrationPath, 'utf-8');

  // Split on drizzle statement-breakpoint comments
  const statements = sql.split('--> statement-breakpoint');
  for (const stmt of statements) {
    const trimmed = stmt.trim();
    if (trimmed) {
      await client.exec(trimmed);
    }
  }

  const db = drizzle(client, { schema }) as unknown as TicketsDb;
  return { client, db };
}
