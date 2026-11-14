import { eq, and } from 'drizzle-orm';
import * as schema from './schema.js';

export * from './schema.js';

export function guildScoped(db: any, guildId: string) {
  return {
    tickets: {
      list: () => db.select().from(schema.tickets).where(eq(schema.tickets.guild_id, guildId)),
      get: (id: string) =>
        db
          .select()
          .from(schema.tickets)
          .where(and(eq(schema.tickets.guild_id, guildId), eq(schema.tickets.id, id))),
    },
    categories: {
      list: () => db.select().from(schema.categories).where(eq(schema.categories.guild_id, guildId)),
    },
    panels: {
      list: () => db.select().from(schema.panels).where(eq(schema.panels.guild_id, guildId)),
    },
    tags: {
      list: () => db.select().from(schema.tags).where(eq(schema.tags.guild_id, guildId)),
    },
    blocks: {
      list: () => db.select().from(schema.blocks).where(eq(schema.blocks.guild_id, guildId)),
    },
    gameServers: {
      list: () => db.select().from(schema.gameServers).where(eq(schema.gameServers.guild_id, guildId)),
    },
    gameActions: {
      list: () => db.select().from(schema.gameActions).where(eq(schema.gameActions.guild_id, guildId)),
    },
  };
}
