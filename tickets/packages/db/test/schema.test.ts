import { describe, it, expect } from 'vitest';
import { getTableConfig } from 'drizzle-orm/pg-core';
import { drizzle } from 'drizzle-orm/node-postgres';
import * as schema from '../src/schema.js';
import { inGuild } from '../src/index.js';

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

function findForeignKey(table: any, colName: string) {
  const fks = getTableConfig(table).foreignKeys;
  return fks.find((fk: any) => {
    const cols = typeof fk.reference === 'function' ? fk.reference().columns : (fk.columns ?? []);
    return cols.some((c: any) => c.name === colName);
  });
}

function findIndex(table: any, columnNames: string[], isUnique: boolean) {
  const config = getTableConfig(table);
  return config.indexes.find((idx: any) => {
    const cols = idx.config.columns.map((c: any) => c.name);
    const sameCols = cols.length === columnNames.length && cols.every((c: string, i: number) => c === columnNames[i]);
    return idx.config.unique === isUnique && sameCols;
  });
}

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

  it('(f1) each FK in item 3 exists with its delete rule', () => {
    const cases = [
      { table: schema.tickets, col: 'category_id', onDelete: 'restrict' },
      { table: schema.ticketMembers, col: 'ticket_id', onDelete: 'cascade' },
      { table: schema.messages, col: 'ticket_id', onDelete: 'cascade' },
      { table: schema.attachments, col: 'ticket_id', onDelete: 'cascade' },
      { table: schema.ratings, col: 'ticket_id', onDelete: 'cascade' },
      { table: schema.gameActions, col: 'ticket_id', onDelete: 'cascade' },
      { table: schema.gameActions, col: 'server_id', onDelete: 'cascade' },
      { table: schema.bridgeNonces, col: 'server_id', onDelete: 'cascade' },
      { table: schema.categories, col: 'game_server_id', onDelete: 'set null' },
      { table: schema.guildSettings, col: 'guild_id', onDelete: 'cascade' },
    ];

    for (const c of cases) {
      const fk = findForeignKey(c.table, c.col);
      expect(fk, `FK on ${getTableConfig(c.table).name}.${c.col} must exist`).toBeDefined();
      expect(fk!.onDelete, `FK on ${getTableConfig(c.table).name}.${c.col} onDelete`).toBe(c.onDelete);
    }
  });

  it('(f2) each index in item 4 exists with the right columns and uniqueness', () => {
    const expectedIndexes = [
      { table: schema.gameActions, cols: ['server_id', 'status'], unique: false },
      { table: schema.tickets, cols: ['guild_id', 'status'], unique: false },
      { table: schema.messages, cols: ['ticket_id'], unique: false },
      { table: schema.pairCodes, cols: ['code_hash'], unique: true },
      { table: schema.bridgeNonces, cols: ['expires_at'], unique: false },
      { table: schema.ratings, cols: ['ticket_id', 'user_id'], unique: true },
      { table: schema.ticketMembers, cols: ['ticket_id', 'user_id'], unique: true },
      { table: schema.tags, cols: ['guild_id', 'name'], unique: true },
      { table: schema.blocks, cols: ['guild_id', 'user_id'], unique: true },
    ];

    for (const item of expectedIndexes) {
      const idx = findIndex(item.table, item.cols, item.unique);
      expect(
        idx,
        `Index on ${getTableConfig(item.table).name}(${item.cols.join(', ')}) [unique=${item.unique}] must exist`
      ).toBeDefined();
    }
  });

  it('(f3) sessions.id is uuid, token_hash not null + unique; no column named token or cookie anywhere', () => {
    const sessionCols = getTableConfig(schema.sessions).columns;
    const idCol = sessionCols.find((c) => c.name === 'id');
    expect(idCol, 'sessions.id must exist').toBeDefined();
    expect(idCol!.columnType, 'sessions.id must be PgUUID').toBe('PgUUID');

    const tokenHashCol = sessionCols.find((c) => c.name === 'token_hash');
    expect(tokenHashCol, 'sessions.token_hash must exist').toBeDefined();
    expect(tokenHashCol!.notNull, 'sessions.token_hash must be not null').toBe(true);

    const csrfHashCol = sessionCols.find((c) => c.name === 'csrf_hash');
    expect(csrfHashCol, 'sessions.csrf_hash must exist').toBeDefined();
    expect(csrfHashCol!.notNull, 'sessions.csrf_hash must be not null').toBe(true);

    const tokenHashIdx = findIndex(schema.sessions, ['token_hash'], true);
    expect(tokenHashIdx, 'sessions must have unique index on token_hash').toBeDefined();

    const forbidden = ['token', 'cookie'];
    for (const table of tables) {
      const { name, columns } = getTableConfig(table);
      for (const col of columns) {
        expect(forbidden, `table ${name} has forbidden column ${col.name}`).not.toContain(col.name);
      }
    }
  });

  it('(f4) attachments.storage_key, game_servers.protocol (not null, default 1), pair_codes.used_at exist', () => {
    const attachmentCols = getTableConfig(schema.attachments).columns;
    const storageKey = attachmentCols.find((c) => c.name === 'storage_key');
    expect(storageKey, 'attachments.storage_key must exist').toBeDefined();
    expect(storageKey!.notNull, 'attachments.storage_key must be nullable').toBe(false);

    const serverCols = getTableConfig(schema.gameServers).columns;
    const protocol = serverCols.find((c) => c.name === 'protocol');
    expect(protocol, 'game_servers.protocol must exist').toBeDefined();
    expect(protocol!.notNull, 'game_servers.protocol must be not null').toBe(true);
    expect(protocol!.default, 'game_servers.protocol default must be 1').toBe(1);

    const pairCols = getTableConfig(schema.pairCodes).columns;
    const usedAt = pairCols.find((c) => c.name === 'used_at');
    expect(usedAt, 'pair_codes.used_at must exist').toBeDefined();
  });

  it('(f5) inGuild(schema.tickets, "g1") used in db.select().from(tickets).where(...).toSQL() has where and param g1', () => {
    const db = drizzle({ query: () => {} } as any);
    const query = db.select().from(schema.tickets).where(inGuild(schema.tickets, 'g1'));
    const { sql, params } = query.toSQL();
    expect(sql.toLowerCase()).toContain('where');
    expect(sql.toLowerCase()).toContain('guild_id');
    expect(params).toContain('g1');
  });

  it('(c1) control: asserting messages has a column content fails (catching schema bug)', () => {
    const msgCols = getTableConfig(schema.messages).columns.map((c) => c.name);
    expect(() => {
      expect(msgCols).toContain('content');
    }).toThrow();
    expect(msgCols).not.toContain('content');
  });
});
