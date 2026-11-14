import { describe, it, expect } from 'vitest';
import { getTableConfig } from 'drizzle-orm/pg-core';
import { drizzle } from 'drizzle-orm/node-postgres';
import * as schema from '../src/schema.js';
import { guildScoped } from '../src/index.js';

const tables = [
  schema.guilds,
  schema.guildSettings,
  schema.categories,
  schema.panels,
  schema.tickets,
  schema.ticketMembers,
  schema.messages,
  schema.attachments,
  schema.ratings,
  schema.tags,
  schema.blocks,
  schema.gameServers,
  schema.pairCodes,
  schema.bridgeNonces,
  schema.gameActions,
  schema.dataRequests,
  schema.auditLog,
  schema.sessions,
];

describe('db schema acceptance tests', () => {
  it('(s1) all 18 table names exist in the exported schema', () => {
    const expected = [
      'guilds', 'guild_settings', 'categories', 'panels', 'tickets',
      'ticket_members', 'messages', 'attachments', 'ratings', 'tags',
      'blocks', 'game_servers', 'pair_codes', 'bridge_nonces', 'game_actions',
      'data_requests', 'audit_log', 'sessions',
    ];
    const names = tables.map((t) => getTableConfig(t).name);
    expect(names).toHaveLength(18);
    for (const name of expected) {
      expect(names).toContain(name);
    }
  });

  it('(s2) every table except sessions and bridge_nonces has a non-null guild_id column', () => {
    for (const table of tables) {
      const { name, columns } = getTableConfig(table);
      if (name === 'sessions' || name === 'bridge_nonces') {
        const guildCol = columns.find((c) => c.name === 'guild_id');
        expect(guildCol).toBeUndefined();
      } else {
        const guildCol = columns.find((c) => c.name === 'guild_id');
        expect(guildCol, `table ${name} must have guild_id`).toBeDefined();
        expect(guildCol!.notNull, `table ${name} guild_id must be not null`).toBe(true);
      }
    }
  });

  it('(s3) tickets has unique index over (guild_id, number) and bridge_nonces composite pk', () => {
    const ticketConfig = getTableConfig(schema.tickets);
    const hasUnique = ticketConfig.indexes.some((idx) => {
      const cols = idx.config.columns.map((c: any) => c.name);
      return idx.config.unique && cols.includes('guild_id') && cols.includes('number');
    });
    expect(hasUnique, 'tickets must have unique index on (guild_id, number)').toBe(true);

    const nonceConfig = getTableConfig(schema.bridgeNonces);
    const pkCols = nonceConfig.primaryKeys.flatMap((pk) => pk.columns.map((c: any) => c.name));
    expect(pkCols).toContain('server_id');
    expect(pkCols).toContain('nonce');
  });

  it('(s4) no column named secret, code, content or token exists in any table', () => {
    const forbidden = ['secret', 'code', 'content', 'token'];
    for (const table of tables) {
      const { name, columns } = getTableConfig(table);
      for (const col of columns) {
        expect(forbidden, `table ${name} has forbidden column ${col.name}`).not.toContain(col.name);
      }
    }
    const serverCols = getTableConfig(schema.gameServers).columns.map((c) => c.name);
    expect(serverCols).toContain('secret_enc');
    const msgCols = getTableConfig(schema.messages).columns.map((c) => c.name);
    expect(msgCols).toContain('content_enc');
    const pairCols = getTableConfig(schema.pairCodes).columns.map((c) => c.name);
    expect(pairCols).toContain('code_hash');
  });

  it('(s5) guildScoped(db, g1).tickets.list() builds SQL with guild_id where-clause', () => {
    const db = drizzle({ query: () => {} } as any);
    const query = guildScoped(db, 'g1').tickets.list();
    const { sql, params } = query.toSQL();
    expect(sql.toLowerCase()).toContain('guild_id');
    expect(params).toContain('g1');
  });

  it('(c1) control: a test asserting a table does_not_exist exists fails', () => {
    const names = tables.map((t) => getTableConfig(t).name);
    expect(() => {
      expect(names).toContain('does_not_exist');
    }).toThrow();
    expect(names).not.toContain('does_not_exist');
  });
});
