import { describe, it, expect, beforeAll, beforeEach, afterAll } from 'vitest';
import * as schema from '@nakara-tickets/db';
import { sealBytes } from '@nakara-tickets/core';
import { openTestDb } from '@nakara-tickets/db/test-support';
import { buildApp } from '../src/app.js';
import { sha256hex, normalizePairCode } from '../src/bridge/pair-code.js';
import type { TicketsConfig } from '../src/config.js';

describe('game-servers and actions API acceptance tests', () => {
  let testEnv: Awaited<ReturnType<typeof openTestDb>>;
  let pglite: any;
  let db: any;
  let config: TicketsConfig;
  const dataKey = Buffer.alloc(32, 7);
  const guildId = '123456789012345678';
  const staffUserId = '987654321098765432';

  beforeAll(async () => {
    testEnv = await openTestDb();
    db = testEnv.db;
    pglite = testEnv.pg;
  });

  beforeEach(async () => {
    await testEnv.reset();

    config = {
      ROLE: 'all',
      PORT: 8080,
      DATABASE_URL: 'postgres://test',
      TICKETS_DATA_KEY: dataKey,
      DISCORD_TOKEN: 'test-token',
      DISCORD_APP_ID: '123456789012345678',
      DISCORD_CLIENT_SECRET: 'test-secret',
      PUBLIC_ORIGIN: 'http://localhost:8080',
      ALLOWED_GUILD_IDS: [guildId],
      STORAGE_DIR: '/data/files',
    };

    // Insert test guild
    await db.insert(schema.guilds).values({
      guild_id: guildId,
      name: 'Test Guild',
    });
  });

  afterAll(async () => {
    await testEnv.close();
  });

  function createTestApp() {
    const app = buildApp({ db, config });
    // Staff auth decorator for test
    app.decorate('requireStaff', async (req: any) => {
      req.guildId = req.params?.guildId;
      req.user = { id: staffUserId, username: 'StaffMember' };
    });
    return app;
  }

  it('(b6) staff creates pair code, response has 10 chars, DB has only the hash', async () => {
    const app = createTestApp();

    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${guildId}/game-servers/pair-codes`,
    });

    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body.code).toBeDefined();
    expect(typeof body.code).toBe('string');
    expect(body.code.length).toBe(10);
    expect(body.expiresAt).toBeDefined();

    // Check DB has only the hash, never the plaintext code
    const codes = await db.select().from(schema.pairCodes);
    expect(codes.length).toBe(1);
    const stored = codes[0];
    expect(stored.code_hash).toBe(sha256hex(normalizePairCode(body.code)));
    expect(JSON.stringify(stored)).not.toContain(body.code);
  });

  it('staff can list, patch (rename/confirm), and revoke game servers', async () => {
    const app = createTestApp();
    const rawSecret = Buffer.alloc(32, 3);
    const secretEnc = sealBytes(dataKey, rawSecret);

    const [srv] = await db
      .insert(schema.gameServers)
      .values({
        guild_id: guildId,
        name: 'Initial Name',
        secret_enc: secretEnc,
        confirmed: false,
      })
      .returning();

    // GET /api/v1/guilds/:guildId/game-servers
    const listRes = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${guildId}/game-servers`,
    });
    expect(listRes.statusCode).toBe(200);
    const servers = listRes.json();
    expect(servers.length).toBe(1);
    expect(servers[0].id).toBe(srv.id);
    expect(servers[0].confirmed).toBe(false);

    // PATCH /api/v1/guilds/:guildId/game-servers/:serverId
    const patchRes = await app.inject({
      method: 'PATCH',
      url: `/api/v1/guilds/${guildId}/game-servers/${srv.id}`,
      payload: {
        name: 'Renamed Server',
        confirmed: true,
      },
    });
    expect(patchRes.statusCode).toBe(200);
    const patched = patchRes.json();
    expect(patched.name).toBe('Renamed Server');
    expect(patched.confirmed).toBe(true);

    // DELETE /api/v1/guilds/:guildId/game-servers/:serverId
    const deleteRes = await app.inject({
      method: 'DELETE',
      url: `/api/v1/guilds/${guildId}/game-servers/${srv.id}`,
    });
    expect(deleteRes.statusCode).toBe(204);

    const [afterDelete] = await db
      .select()
      .from(schema.gameServers)
      .where(schema.inGuild(schema.gameServers, guildId));
    expect(afterDelete.revoked).toBe(true);
  });

  it('postTicketAction queues action; 422 if category has no game server', async () => {
    const app = createTestApp();
    const rawSecret = Buffer.alloc(32, 4);
    const secretEnc = sealBytes(dataKey, rawSecret);

    const [srv] = await db
      .insert(schema.gameServers)
      .values({
        guild_id: guildId,
        name: 'Server 1',
        secret_enc: secretEnc,
        confirmed: true,
      })
      .returning();

    // Category with game server
    const [catWithServer] = await db
      .insert(schema.categories)
      .values({
        guild_id: guildId,
        name: 'Category With Server',
        parent_channel_id: '123456789012345678',
        game_server_id: srv.id,
      })
      .returning();

    // Category without game server
    const [catWithoutServer] = await db
      .insert(schema.categories)
      .values({
        guild_id: guildId,
        name: 'Category Without Server',
        parent_channel_id: '123456789012345678',
        game_server_id: null,
      })
      .returning();

    const [ticketWithServer] = await db
      .insert(schema.tickets)
      .values({
        guild_id: guildId,
        number: 1,
        category_id: catWithServer.id,
        opener_id: '111122223333444455',
        channel_id: '123456789012345678',
      })
      .returning();

    const [ticketWithoutServer] = await db
      .insert(schema.tickets)
      .values({
        guild_id: guildId,
        number: 2,
        category_id: catWithoutServer.id,
        opener_id: '111122223333444455',
        channel_id: '123456789012345679',
      })
      .returning();

    // 1. Post action to ticket whose category has NO server -> 422
    const resNoServer = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${guildId}/tickets/${ticketWithoutServer.id}/actions`,
      payload: {
        action: 'player.info',
      },
    });
    expect(resNoServer.statusCode).toBe(422);

    // 2. Post action to ticket whose category HAS a server -> 202 Queued
    const resQueued = await app.inject({
      method: 'POST',
      url: `/api/v1/guilds/${guildId}/tickets/${ticketWithServer.id}/actions`,
      payload: {
        action: 'player.info',
      },
    });
    expect(resQueued.statusCode).toBe(202);
    const actionBody = resQueued.json();
    expect(actionBody.id).toBeDefined();
    expect(actionBody.status).toBe('queued');
    expect(actionBody.action).toBe('player.info');
    expect(actionBody.serverId).toBe(srv.id);

    // 3. GET /api/v1/guilds/:guildId/tickets/:ticketId/actions lists them
    const resList = await app.inject({
      method: 'GET',
      url: `/api/v1/guilds/${guildId}/tickets/${ticketWithServer.id}/actions`,
    });
    expect(resList.statusCode).toBe(200);
    const actionList = resList.json();
    expect(actionList.length).toBe(1);
    expect(actionList[0].id).toBe(actionBody.id);
  });

  it('fails with 500 misconfigured when requireStaff decorator is missing (fail-open protection)', async () => {
    // App without requireStaff decorator
    const bareApp = buildApp({ db, config });

    const res = await bareApp.inject({
      method: 'GET',
      url: `/api/v1/guilds/${guildId}/game-servers`,
    });

    expect(res.statusCode).toBe(500);
    expect(res.json().code).toBe('misconfigured');
  });
});
