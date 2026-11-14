import { eq, type SQL } from 'drizzle-orm';
import type { AnyPgTable, AnyPgColumn } from 'drizzle-orm/pg-core';

export * from './schema.js';

export function inGuild<T extends AnyPgTable & { guild_id: AnyPgColumn }>(table: T, guildId: string): SQL {
  return eq(table.guild_id, guildId);
}
