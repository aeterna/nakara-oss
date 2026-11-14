import { describe, it, expect, beforeAll, beforeEach, afterAll } from 'vitest';
import * as schema from '@nakara-tickets/db';
import { signBridge, sealBytes } from '@nakara-tickets/core';
import { openTestDb } from '@nakara-tickets/db/test-support';
import { buildApp } from '../src/app.js';
import { installBridgeAuth } from '../src/bridge/auth.js';
import { sha256hex, normalizePairCode } from '../src/bridge/pair-code.js';
import type { TicketsConfig } from '../src/config.js';

describe('bridge API acceptance tests', () => {
  let testEnv: Awaited<ReturnType<typeof openTestDb>>;
  let pglite: any;
  let db: any;
  let config: TicketsConfig;
  const dataKey = Buffer.alloc(32, 5); // 32-byte test key
  const guildId = '123456789012345678';

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

  function createTestApp(overrideConfig?: Partial<TicketsConfig>) {
    const finalConfig = overrideConfig ? { ...config, ...overrideConfig } : config;
    const app = buildApp({ db, config: finalConfig });
    installBridgeAuth(app, { db, dataKey: finalConfig.TICKETS_DATA_KEY });
    return app;
  }

  it('(b1) pair with a valid code → serverId + secret, code unusable after', async () => {
    const app = createTestApp();
    const pairCodePlain = 'PAIRCODE10';
    const codeHash = sha256hex(normalizePairCode(pairCodePlain));

    await db.insert(schema.pairCodes).values({
      guild_id: guildId,
      code_hash: codeHash,
      server_name: 'Console Requested Server',
      expires_at: new Date(Date.now() + 10 * 60 * 1000),
    });

    const res = await app.inject({
      method: 'POST',
      url: '/bridge/v1/pair',
      payload: {
        code: pairCodePlain,
        serverName: 'Nakara RP #1',
        edition: 'gta5',
        resourceVersion: '0.1.0',
        protocol: 1,
      },
    });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.serverId).toBeDefined();
    expect(body.secret).toBeDefined();
    expect(typeof body.secret).toBe('string');
    expect(body.guildName).toBe('Test Guild');

    // Verify game_servers row in DB
    const [server] = await db
      .select()
      .from(schema.gameServers)
      .where(schema.inGuild(schema.gameServers, guildId));
    expect(server).toBeDefined();
    expect(server.id).toBe(body.serverId);
    expect(server.confirmed).toBe(false);
    expect(server.name).toBe('Nakara RP #1');

    // Code is marked as used
    const [updatedCode] = await db.select().from(schema.pairCodes);
    expect(updatedCode.used_at).not.toBeNull();

    // Trying to use the same code again should fail with 400 invalid
    const secondRes = await app.inject({
      method: 'POST',
      url: '/bridge/v1/pair',
      payload: {
        code: pairCodePlain,
        serverName: 'Nakara RP #1',
        edition: 'gta5',
        resourceVersion: '0.1.0',
        protocol: 1,
      },
    });
    expect(secondRes.statusCode).toBe(400);
    expect(secondRes.json().code).toBe('invalid');
  });

  it('(b2) expired code → 400', async () => {
    const app = createTestApp();
    const expiredCodePlain = 'EXPIRED100';
    const codeHash = sha256hex(normalizePairCode(expiredCodePlain));

    await db.insert(schema.pairCodes).values({
      guild_id: guildId,
      code_hash: codeHash,
      expires_at: new Date(Date.now() - 60 * 1000), // 1 min in past
    });

    const res = await app.inject({
      method: 'POST',
      url: '/bridge/v1/pair',
      payload: {
        code: expiredCodePlain,
        serverName: 'Nakara RP #1',
        edition: 'gta5',
        resourceVersion: '0.1.0',
        protocol: 1,
      },
    });

    expect(res.statusCode).toBe(400);
    expect(res.json().code).toBe('invalid');
  });

  it('(b3) signed heartbeat ok; wrong signature → 401; same nonce twice → second 401; skew 61 s → 401', async () => {
    const app = createTestApp();
    const rawSecret = Buffer.alloc(32, 9);
    const secretEnc = sealBytes(dataKey, rawSecret);

    const [server] = await db
      .insert(schema.gameServers)
      .values({
        guild_id: guildId,
        name: 'Test Server',
        secret_enc: secretEnc,
        confirmed: true,
      })
      .returning();

    const nowSec = Math.floor(Date.now() / 1000);
    const nonce1 = 'nonce-unique-1234567';
    const payload = JSON.stringify({ players: [{ playerId: 1, discordId: '123456789012345678' }] });

    const parts = {
      timestamp: nowSec,
      nonce: nonce1,
      method: 'POST',
      pathWithQuery: '/bridge/v1/heartbeat',
      body: payload,
    };
    const validSig = signBridge(rawSecret, parts);

    // 1. Valid request
    const res1 = await app.inject({
      method: 'POST',
      url: '/bridge/v1/heartbeat',
      headers: {
        'content-type': 'application/json',
        'x-tickets-server': server.id,
        'x-tickets-timestamp': String(nowSec),
        'x-tickets-nonce': nonce1,
        'x-tickets-signature': validSig,
        'x-tickets-protocol': '1',
      },
      payload,
    });
    expect(res1.statusCode).toBe(200);
    expect(res1.json()).toEqual({ ok: true });

    // 2. Wrong signature -> 401
    const badSig = '0'.repeat(64);
    const resBadSig = await app.inject({
      method: 'POST',
      url: '/bridge/v1/heartbeat',
      headers: {
        'content-type': 'application/json',
        'x-tickets-server': server.id,
        'x-tickets-timestamp': String(nowSec),
        'x-tickets-nonce': 'nonce-wrong-sig-test',
        'x-tickets-signature': badSig,
        'x-tickets-protocol': '1',
      },
      payload,
    });
    expect(resBadSig.statusCode).toBe(401);
    expect(resBadSig.json().code).toBe('unauthorized');

    // 3. Same nonce twice -> second 401 (replay attack protection)
    const resReplay = await app.inject({
      method: 'POST',
      url: '/bridge/v1/heartbeat',
      headers: {
        'content-type': 'application/json',
        'x-tickets-server': server.id,
        'x-tickets-timestamp': String(nowSec),
        'x-tickets-nonce': nonce1, // reused nonce1
        'x-tickets-signature': validSig,
        'x-tickets-protocol': '1',
      },
      payload,
    });
    expect(resReplay.statusCode).toBe(401);
    expect(resReplay.json().code).toBe('unauthorized');

    // 4. Skew 61 s -> 401
    const skewedTs = nowSec - 61;
    const skewedParts = {
      timestamp: skewedTs,
      nonce: 'nonce-skew-test-999',
      method: 'POST',
      pathWithQuery: '/bridge/v1/heartbeat',
      body: payload,
    };
    const skewedSig = signBridge(rawSecret, skewedParts);
    const resSkew = await app.inject({
      method: 'POST',
      url: '/bridge/v1/heartbeat',
      headers: {
        'content-type': 'application/json',
        'x-tickets-server': server.id,
        'x-tickets-timestamp': String(skewedTs),
        'x-tickets-nonce': 'nonce-skew-test-999',
        'x-tickets-signature': skewedSig,
        'x-tickets-protocol': '1',
      },
      payload,
    });
    expect(resSkew.statusCode).toBe(401);
    expect(resSkew.json().code).toBe('unauthorized');

    // 5. Malformed timestamp or nonce -> 401
    const resBadNonce = await app.inject({
      method: 'POST',
      url: '/bridge/v1/heartbeat',
      headers: {
        'content-type': 'application/json',
        'x-tickets-server': server.id,
        'x-tickets-timestamp': String(nowSec),
        'x-tickets-nonce': 'short', // less than 16 chars
        'x-tickets-signature': validSig,
        'x-tickets-protocol': '1',
      },
      payload,
    });
    expect(resBadNonce.statusCode).toBe(401);
  });

  it('(b4) actions: queued action leased once, second poll gets null, after lease expiry the same id comes back; unconfirmed server gets null', async () => {
    const app = createTestApp();
    const rawSecret = Buffer.alloc(32, 11);
    const secretEnc = sealBytes(dataKey, rawSecret);

    // Confirmed server
    const [server] = await db
      .insert(schema.gameServers)
      .values({
        guild_id: guildId,
        name: 'Confirmed Server',
        secret_enc: secretEnc,
        confirmed: true,
      })
      .returning();

    // Unconfirmed server
    const [unconfirmedServer] = await db
      .insert(schema.gameServers)
      .values({
        guild_id: guildId,
        name: 'Unconfirmed Server',
        secret_enc: secretEnc,
        confirmed: false,
      })
      .returning();

    // Setup category and ticket
    const [category] = await db
      .insert(schema.categories)
      .values({
        guild_id: guildId,
        name: 'Support',
        parent_channel_id: '123456789012345678',
        game_server_id: server.id,
      })
      .returning();

    const [ticket] = await db
      .insert(schema.tickets)
      .values({
        guild_id: guildId,
        number: 1,
        category_id: category.id,
        opener_id: '111122223333444455',
        channel_id: '123456789012345678',
      })
      .returning();

    // Insert queued action for confirmed server
    const [action] = await db
      .insert(schema.gameActions)
      .values({
        guild_id: guildId,
        ticket_id: ticket.id,
        server_id: server.id,
        action: 'player.info',
        params: {},
        status: 'queued',
        requested_by: 'staff-user',
        expires_at: new Date(Date.now() + 60 * 1000),
      })
      .returning();

    // Helper to send signed actions GET request
    const getActions = async (srvId: string, queryWait = 0) => {
      const nowSec = Math.floor(Date.now() / 1000);
      const nonce = 'nonce-' + Math.random().toString(36).slice(2).padEnd(16, '0');
      const pathWithQuery = `/bridge/v1/actions?wait=${queryWait}`;
      const sig = signBridge(rawSecret, {
        timestamp: nowSec,
        nonce,
        method: 'GET',
        pathWithQuery,
        body: '',
      });
      return app.inject({
        method: 'GET',
        url: pathWithQuery,
        headers: {
          'x-tickets-server': srvId,
          'x-tickets-timestamp': String(nowSec),
          'x-tickets-nonce': nonce,
          'x-tickets-signature': sig,
          'x-tickets-protocol': '1',
        },
      });
    };

    // 1. Unconfirmed server gets null (wait=0)
    const resUnconfirmed = await getActions(unconfirmedServer.id, 0);
    expect(resUnconfirmed.statusCode).toBe(200);
    expect(resUnconfirmed.json()).toEqual({ action: null });

    // 2. Confirmed server leases the action
    const res1 = await getActions(server.id, 0);
    expect(res1.statusCode).toBe(200);
    const body1 = res1.json();
    expect(body1.action).not.toBeNull();
    expect(body1.action.id).toBe(action.id);
    expect(body1.action.action).toBe('player.info');
    expect(body1.action.discordId).toBe('111122223333444455');
    expect(body1.action.requestedBy).toBe('staff-user');

    // 3. Second poll while leased gets null
    const res2 = await getActions(server.id, 0);
    expect(res2.statusCode).toBe(200);
    expect(res2.json()).toEqual({ action: null });

    // 4. Manually expire the lease in DB (lease_until < now)
    await db
      .update(schema.gameActions)
      .set({ lease_until: new Date(Date.now() - 5000) })
      .where(schema.inGuild(schema.gameActions, guildId));

    // 5. After lease expiry, same action comes back
    const res3 = await getActions(server.id, 0);
    expect(res3.statusCode).toBe(200);
    const body3 = res3.json();
    expect(body3.action).not.toBeNull();
    expect(body3.action.id).toBe(action.id);
  });

  it('(b5) result idempotent: same twice 200, different 409', async () => {
    const app = createTestApp();
    const rawSecret = Buffer.alloc(32, 13);
    const secretEnc = sealBytes(dataKey, rawSecret);

    const [server] = await db
      .insert(schema.gameServers)
      .values({
        guild_id: guildId,
        name: 'Confirmed Server',
        secret_enc: secretEnc,
        confirmed: true,
      })
      .returning();

    const [category] = await db
      .insert(schema.categories)
      .values({
        guild_id: guildId,
        name: 'Support',
        parent_channel_id: '123456789012345678',
        game_server_id: server.id,
      })
      .returning();

    const [ticket] = await db
      .insert(schema.tickets)
      .values({
        guild_id: guildId,
        number: 1,
        category_id: category.id,
        opener_id: '111122223333444455',
        channel_id: '123456789012345678',
      })
      .returning();

    const [action] = await db
      .insert(schema.gameActions)
      .values({
        guild_id: guildId,
        ticket_id: ticket.id,
        server_id: server.id,
        action: 'player.teleport',
        params: { spot: 'hospital' },
        status: 'leased',
        requested_by: 'staff-user',
        expires_at: new Date(Date.now() + 60 * 1000),
      })
      .returning();

    const postResult = async (resultObj: any) => {
      const nowSec = Math.floor(Date.now() / 1000);
      const nonce = 'nonce-' + Math.random().toString(36).slice(2).padEnd(16, '0');
      const pathWithQuery = `/bridge/v1/actions/${action.id}/result`;
      const payload = JSON.stringify(resultObj);
      const sig = signBridge(rawSecret, {
        timestamp: nowSec,
        nonce,
        method: 'POST',
        pathWithQuery,
        body: payload,
      });
      return app.inject({
        method: 'POST',
        url: pathWithQuery,
        headers: {
          'content-type': 'application/json',
          'x-tickets-server': server.id,
          'x-tickets-timestamp': String(nowSec),
          'x-tickets-nonce': nonce,
          'x-tickets-signature': sig,
          'x-tickets-protocol': '1',
        },
        payload,
      });
    };

    const firstResult = { ok: true, code: 'done', data: { spot: 'hospital' } };

    // 1. First result -> 200, status becomes done
    const res1 = await postResult(firstResult);
    expect(res1.statusCode).toBe(200);
    expect(res1.json()).toEqual({ ok: true });

    const [dbAction] = await db
      .select()
      .from(schema.gameActions)
      .where(schema.inGuild(schema.gameActions, guildId));
    expect(dbAction.status).toBe('done');
    expect(dbAction.result).toEqual(firstResult);

    // Audit log was recorded
    const [auditEntry] = await db
      .select()
      .from(schema.auditLog)
      .where(schema.inGuild(schema.auditLog, guildId));
    expect(auditEntry).toBeDefined();
    expect(auditEntry.kind).toBe('action.result');

    // 2. Same result again -> 200 (idempotent via deep equality)
    const res2 = await postResult(firstResult);
    expect(res2.statusCode).toBe(200);
    expect(res2.json()).toEqual({ ok: true });

    // 3. Different result -> 409 conflict
    const differentResult = { ok: false, code: 'error', message: 'failed on replay' };
    const res3 = await postResult(differentResult);
    expect(res3.statusCode).toBe(409);
    expect(res3.json().code).toBe('conflict');

    // 4. Invalid result schema (extra key) -> 400
    const invalidResult = { ok: true, code: 'done', extraField: 'bad' };
    const res4 = await postResult(invalidResult);
    expect(res4.statusCode).toBe(400);
  });

  it('(b7) pair → sign exactly as the resource does → API accepts', async () => {
    const app = createTestApp();
    const rawPairCode = 'CROCKFORD01';
    const codeHash = sha256hex(normalizePairCode(rawPairCode));

    await db.insert(schema.pairCodes).values({
      guild_id: guildId,
      code_hash: codeHash,
      server_name: 'Nakara RP #7',
      expires_at: new Date(Date.now() + 10 * 60 * 1000),
    });

    // 1. Pair request with unnormalized code (e.g. lowercase with Crockford 'o')
    const pairRes = await app.inject({
      method: 'POST',
      url: '/bridge/v1/pair',
      payload: {
        code: 'crockford01',
        serverName: 'Nakara RP #7',
        edition: 'gta5',
        resourceVersion: '0.1.0',
        protocol: 1,
      },
    });
    expect(pairRes.statusCode).toBe(200);
    const { serverId, secret, guildName } = pairRes.json();
    expect(serverId).toBeDefined();
    expect(secret).toBeDefined();
    expect(typeof secret).toBe('string');
    expect(guildName).toBe('Test Guild');

    // Confirm server
    await db
      .update(schema.gameServers)
      .set({ confirmed: true })
      .where(schema.inGuild(schema.gameServers, guildId));

    // 2. Resource signs with Buffer.from(secret, 'base64url')
    const decodedKey = Buffer.from(secret, 'base64url');
    const nowSec = Math.floor(Date.now() / 1000);
    const nonce = 'nonce-b7-test-unique123';
    const payload = JSON.stringify({ players: [{ playerId: 1, discordId: '123456789012345678' }] });
    const parts = {
      timestamp: nowSec,
      nonce,
      method: 'POST',
      pathWithQuery: '/bridge/v1/heartbeat',
      body: payload,
    };
    const sig = signBridge(decodedKey, parts);

    const heartbeatRes = await app.inject({
      method: 'POST',
      url: '/bridge/v1/heartbeat',
      headers: {
        'content-type': 'application/json',
        'x-tickets-server': serverId,
        'x-tickets-timestamp': String(nowSec),
        'x-tickets-nonce': nonce,
        'x-tickets-signature': sig,
        'x-tickets-protocol': '1',
      },
      payload,
    });

    expect(heartbeatRes.statusCode).toBe(200);
    expect(heartbeatRes.json()).toEqual({ ok: true });
  });

  it('pair fails with 500 misconfigured when TICKETS_DATA_KEY is missing', async () => {
    const appWithoutKey = createTestApp({ TICKETS_DATA_KEY: null as any });
    const pairCodePlain = 'KEYTEST100';
    const codeHash = sha256hex(normalizePairCode(pairCodePlain));

    await db.insert(schema.pairCodes).values({
      guild_id: guildId,
      code_hash: codeHash,
      server_name: 'Key Test Server',
      expires_at: new Date(Date.now() + 10 * 60 * 1000),
    });

    const res = await appWithoutKey.inject({
      method: 'POST',
      url: '/bridge/v1/pair',
      payload: {
        code: pairCodePlain,
        serverName: 'Key Test Server',
        edition: 'gta5',
        resourceVersion: '0.1.0',
        protocol: 1,
      },
    });

    expect(res.statusCode).toBe(500);
    expect(res.json().code).toBe('misconfigured');
  });
});
