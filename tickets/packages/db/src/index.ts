import { eq, type SQL } from 'drizzle-orm';
import type { AnyPgTable, AnyPgColumn, PgDatabase, PgQueryResultHKT } from 'drizzle-orm/pg-core';
import * as schema from './schema.js';

export * from './schema.js';

export type TicketsDb = PgDatabase<PgQueryResultHKT, typeof schema>;

export function inGuild<T extends AnyPgTable & { guild_id: AnyPgColumn }>(table: T, guildId: string): SQL {
  return eq(table.guild_id, guildId);
}
