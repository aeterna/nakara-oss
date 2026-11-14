import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import * as schema from '@nakara-tickets/db';
import { readFileSync, readdirSync } from 'node:fs';
import type { TicketsDb } from '@nakara-tickets/db';

export async function createTestDb(): Promise<{ client: PGlite; db: TicketsDb }> {
  const client = new PGlite();
  const migrationsDir = new URL('../../db/migrations/', import.meta.url);
  const files = readdirSync(migrationsDir)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  for (const file of files) {
    const sql = readFileSync(new URL(file, migrationsDir), 'utf-8');
    const statements = sql.split('--> statement-breakpoint');
    for (const stmt of statements) {
      const trimmed = stmt.trim();
      if (trimmed) {
        await client.exec(trimmed);
      }
    }
  }

  const db = drizzle(client, { schema }) as unknown as TicketsDb;
  return { client, db };
}
