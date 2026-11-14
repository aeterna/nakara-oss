import { describe, it, expect, beforeAll, beforeEach, afterAll, vi } from 'vitest';
import { randomBytes } from 'node:crypto';
import * as schema from '@nakara-tickets/db';
import { signBridge, sealBytes } from '@nakara-tickets/core';
import { openTestDb } from '@nakara-tickets/db/test-support';
import { buildApp } from '../src/app.js';
import { installBridgeAuth } from '../src/bridge/auth.js';
import type { TicketsConfig } from '../src/config.js';

describe('bridge result acceptance tests (g3)', () => {
  let testEnv: Awaited<ReturnType<typeof openTestDb>>;
  let db: any;
  let config: TicketsConfig;
  const dataKey = Buffer.alloc(32, 9);
  const guildId = '123456789012345678';
  const ticketChannelId = '987654321098765432';
  let serverId: string;
  let rawSecret: string;

  beforeAll(async () => {
    testEnv = await openTestDb();
    db = testEnv.db;
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

    await db.insert(schema.guilds).values({
      guild_id: guildId,
      name: 'Test Guild',
    });

    rawSecret = randomBytes(32).toString('base64url');
    const secretEnc = sealBytes(dataKey, Buffer.from(rawSecret, 'base64url'));

    const [server] = await db
      .insert(schema.gameServers)
      .values({
        guild_id: guildId,
        name: 'Game Server 1',
        secret_enc: secretEnc,
        confirmed: true,
      })
      .returning();
    serverId = server.id;

    const [category] = await db
      .insert(schema.categories)
      .values({
        guild_id: guildId,
        name: 'Support',
        parent_channel_id: '123456789012345678',
        game_server_id: server.id,
      })
      .returning();

    await db
      .insert(schema.tickets)
      .values({
        id: '11111111-1111-1111-1111-111111111111',
        guild_id: guildId,
        number: 1,
        category_id: category.id,
        opener_id: '111122223333444455',
        channel_id: ticketChannelId,
      });
  });

  afterAll(async () => {
    await testEnv.close();
  });

  function createTestApp(discordMock?: any) {
    const app = buildApp({ db, config, discord: discordMock });
    installBridgeAuth(app, { db, dataKey: config.TICKETS_DATA_KEY });
    return app;
  }

  it('(g3) result posts a channel line with icon, action, code and requested_by', async () => {
    let sentMessage: { channelId: string; body: any } | null = null;
    const discordMock = {
      sendMessage: vi.fn().mockImplementation(async (channelId: string, body: any) => {
        sentMessage = { channelId, body };
        return { id: 'msg-1' };
      }),
      editMessage: vi.fn(),
      deleteMessage: vi.fn(),
      createDM: vi.fn(),
    };

    const app = createTestApp(discordMock);

    const [action] = await db
      .insert(schema.gameActions)
      .values({
        guild_id: guildId,
        ticket_id: '11111111-1111-1111-1111-111111111111',
        server_id: serverId,
        action: 'player.revive',
        params: {},
        status: 'leased',
        requested_by: 'staff-mod-1',
        expires_at: new Date(Date.now() + 60 * 1000),
      })
      .returning();

    const nowSec = Math.floor(Date.now() / 1000);
    const nonce = 'nonce-test-g3-ok';
    const pathWithQuery = `/bridge/v1/actions/${action.id}/result`;
    const payload = JSON.stringify({ ok: true, code: 'done' });
    const sig = signBridge(rawSecret, {
      timestamp: nowSec,
      nonce,
      method: 'POST',
      pathWithQuery,
      body: payload,
    });

    const res = await app.inject({
      method: 'POST',
      url: pathWithQuery,
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

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true });

    // Verify discord message was sent
    expect(discordMock.sendMessage).toHaveBeenCalledTimes(1);
    expect(sentMessage).not.toBeNull();
    expect(sentMessage!.channelId).toBe(ticketChannelId);
    expect(sentMessage!.body.content).toContain('✅');
    expect(sentMessage!.body.content).toContain('player.revive');
    expect(sentMessage!.body.content).toContain('done');
    expect(sentMessage!.body.content).toContain('staff-mod-1');
  });

  it('(g3) discord throwing still returns 200', async () => {
    const discordMock = {
      sendMessage: vi.fn().mockRejectedValue(new Error('Discord API unavailable (503)')),
      editMessage: vi.fn(),
      deleteMessage: vi.fn(),
      createDM: vi.fn(),
    };

    const app = createTestApp(discordMock);

    const [action] = await db
      .insert(schema.gameActions)
      .values({
        guild_id: guildId,
        ticket_id: '11111111-1111-1111-1111-111111111111',
        server_id: serverId,
        action: 'player.give_item',
        params: { item: 'bandage', count: 1 },
        status: 'leased',
        requested_by: 'staff-admin',
        expires_at: new Date(Date.now() + 60 * 1000),
      })
      .returning();

    const nowSec = Math.floor(Date.now() / 1000);
    const nonce = 'nonce-test-g3-throw';
    const pathWithQuery = `/bridge/v1/actions/${action.id}/result`;
    const payload = JSON.stringify({ ok: false, code: 'error', message: 'Item transfer failed' });
    const sig = signBridge(rawSecret, {
      timestamp: nowSec,
      nonce,
      method: 'POST',
      pathWithQuery,
      body: payload,
    });

    const res = await app.inject({
      method: 'POST',
      url: pathWithQuery,
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

    // Discord throwing must never fail the result endpoint
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true });

    // Result must still be saved in DB
    const [saved] = await db
      .select()
      .from(schema.gameActions)
      .where(schema.eq(schema.gameActions.id, action.id));
    expect(saved.status).toBe('failed');
    expect(saved.result).toEqual({ ok: false, code: 'error', message: 'Item transfer failed' });
  });
});
