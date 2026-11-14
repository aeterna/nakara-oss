import { eq } from 'drizzle-orm';
export * from './schema.js';
export function inGuild(table, guildId) {
    return eq(table.guild_id, guildId);
}
export * from './queries/errors.js';
export * from './queries/guilds.js';
export * from './queries/categories.js';
export * from './queries/tickets.js';
export * from './queries/messages.js';
//# sourceMappingURL=index.js.map