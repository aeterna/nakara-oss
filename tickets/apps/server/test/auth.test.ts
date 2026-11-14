import { describe, it, expect, vi, beforeEach } from 'vitest';
import Fastify from 'fastify';
import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash, createHmac } from 'node:crypto';
import * as dbSchema from '@nakara-tickets/db';
import { sessions } from '@nakara-tickets/db';
import { installSession } from '../src/session.js';
import routes from '../src/routes/index.js';
import type { TicketsConfig } from '../src/config.js';

async function createTestDb() {
  const pglite = new PGlite();
  const migrationPath = resolve(import.meta.dirname, '../../../packages/db/migrations/0000_init.sql');
  const sql = readFileSync(migrationPath, 'utf8');
  for (const statement of sql.split('--> statement-breakpoint')) {
    const trimmed = statement.trim();
    if (trimmed) {
      await pglite.query(trimmed);
    }
  }
  return drizzle(pglite, { schema: dbSchema });
}

describe('auth acceptance tests', () => {
  const mockConfig: TicketsConfig = {
    ROLE: 'all',
    PORT: 8080,
    DATABASE_URL: 'postgres://localhost:5432/mock',
    TICKETS_DATA_KEY: Buffer.alloc(32, 2),
    DISCORD_TOKEN: 'mock-bot-token',
    DISCORD_APP_ID: '123456789012345678',
    DISCORD_CLIENT_SECRET: 'mock-client-secret',
    PUBLIC_ORIGIN: 'http://localhost:8080',
    ALLOWED_GUILD_IDS: ['111111111111111111'],
    STORAGE_DIR: '/tmp/tickets',
  };

  let testDb: any;
  let app: ReturnType<typeof Fastify>;

  beforeEach(async () => {
    testDb = await createTestDb();
    app = Fastify();
    app.decorate('config', mockConfig);
    app.decorate('db', testDb);
    await installSession(app, { config: mockConfig, db: testDb });
    await app.register(routes);
    await app.ready();
  });

  it('GET /auth/login redirects to Discord with state and PKCE S256', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/auth/login',
    });

    expect(res.statusCode).toBe(302);
    const location = res.headers.location;
    expect(location).toBeDefined();

    const redirectUrl = new URL(location!, 'http://localhost');
    expect(redirectUrl.origin).toBe('https://discord.com');
    expect(redirectUrl.pathname).toBe('/oauth2/authorize');
    expect(redirectUrl.searchParams.get('client_id')).toBe('123456789012345678');
    expect(redirectUrl.searchParams.get('response_type')).toBe('code');
    expect(redirectUrl.searchParams.get('scope')).toBe('identify guilds');
    expect(redirectUrl.searchParams.get('code_challenge_method')).toBe('S256');
    expect(redirectUrl.searchParams.get('state')).toBeTruthy();
    expect(redirectUrl.searchParams.get('code_challenge')).toBeTruthy();

    const cookies = res.headers['set-cookie'];
    expect(cookies).toBeDefined();
    const cookieHeader = Array.isArray(cookies) ? cookies.join('; ') : String(cookies);
    expect(cookieHeader).toContain('nt_oauth=');
  });

  it('(a6) callback rejects a wrong state', async () => {
    // 1. First get a valid login cookie
    const loginRes = await app.inject({
      method: 'GET',
      url: '/auth/login',
    });
    const setCookie = loginRes.headers['set-cookie'];
    const cookieHeader = Array.isArray(setCookie) ? setCookie[0] : String(setCookie);
    const oauthCookie = cookieHeader.split(';')[0]; // nt_oauth=...

    // 2. Callback with wrong state -> 400
    const resWrongState = await app.inject({
      method: 'GET',
      url: '/auth/callback?code=somecode&state=wrong-state-value',
      headers: {
        cookie: oauthCookie,
      },
    });
    expect(resWrongState.statusCode).toBe(400);
    expect(resWrongState.json().code).toBe('invalid');

    // 3. Callback with missing cookie -> 400
    const resNoCookie = await app.inject({
      method: 'GET',
      url: '/auth/callback?code=somecode&state=somestate',
    });
    expect(resNoCookie.statusCode).toBe(400);

    // 4. Callback with missing code or state -> 400
    const resNoParams = await app.inject({
      method: 'GET',
      url: '/auth/callback',
      headers: {
        cookie: oauthCookie,
      },
    });
    expect(resNoParams.statusCode).toBe(400);
  });

  it('(a7) callback stores only the token hash (row does not contain the cookie value)', async () => {
    // 1. Call login to obtain the state and verifier in nt_oauth
    const loginRes = await app.inject({
      method: 'GET',
      url: '/auth/login',
    });
    const location = new URL(loginRes.headers.location!, 'http://localhost');
    const state = location.searchParams.get('state')!;
    const setCookie = loginRes.headers['set-cookie'];
    const cookieHeader = Array.isArray(setCookie) ? setCookie[0] : String(setCookie);
    const oauthCookie = cookieHeader.split(';')[0];

    // 2. Stub fetch for Discord token exchange and user info
    const userId = '888888888888888888';
    vi.stubGlobal('fetch', vi.fn().mockImplementation(async (url: string) => {
      const urlStr = String(url);
      if (urlStr.includes('/oauth2/token')) {
        return {
          ok: true,
          status: 200,
          json: async () => ({
            access_token: 'mock-discord-access-token',
            token_type: 'Bearer',
            expires_in: 604800,
            scope: 'identify guilds',
          }),
        };
      }
      if (urlStr.includes('/users/@me')) {
        return {
          ok: true,
          status: 200,
          json: async () => ({
            id: userId,
            username: 'discorduser',
            avatar: 'avatar_hash_123',
          }),
        };
      }
      return { ok: false, status: 404, json: async () => ({}) };
    }));

    // 3. Complete callback
    const callbackRes = await app.inject({
      method: 'GET',
      url: `/auth/callback?code=valid-discord-code&state=${state}`,
      headers: {
        cookie: oauthCookie,
      },
    });

    expect(callbackRes.statusCode).toBe(302);
    expect(callbackRes.headers.location).toBe('/');

    // 4. Extract nt_session cookie value
    const cookies = callbackRes.headers['set-cookie'];
    expect(cookies).toBeDefined();
    const cookieStr = Array.isArray(cookies) ? cookies.join('; ') : String(cookies);
    expect(cookieStr).toContain('nt_session=');

    const match = cookieStr.match(/nt_session=([^;]+)/);
    expect(match).toBeTruthy();
    const cookieToken = match![1];

    // 5. Query the database session row
    const sessionRows = await testDb.select().from(sessions);
    expect(sessionRows.length).toBe(1);
    const row = sessionRows[0];

    // The row must store token_hash equal to sha256(cookieToken)
    const expectedHash = createHash('sha256').update(cookieToken).digest('hex');
    expect(row.token_hash).toBe(expectedHash);
    expect(row.token_hash).not.toBe(cookieToken);

    // The database row must NOT contain the plaintext cookie value in any field
    const rowJson = JSON.stringify(row);
    expect(rowJson).not.toContain(cookieToken);
  });

  it('POST /auth/logout deletes the session and clears cookie', async () => {
    // 1. Create a session directly in DB
    const sessionToken = 'logout-test-token-base64url';
    const tokenHash = createHash('sha256').update(sessionToken).digest('hex');
    await testDb.insert(sessions).values({
      user_id: '999999999999999999',
      token_hash: tokenHash,
      csrf_hash: 'logout-csrf',
      expires_at: new Date(Date.now() + 86400000),
    });

    const preRows = await testDb.select().from(sessions);
    expect(preRows.length).toBe(1);

    // 2. Call logout
    const logoutRes = await app.inject({
      method: 'POST',
      url: '/auth/logout',
      headers: {
        cookie: `nt_session=${sessionToken}`,
      },
    });

    expect(logoutRes.statusCode).toBe(204);

    // 3. Check DB - session row is deleted
    const postRows = await testDb.select().from(sessions);
    expect(postRows.length).toBe(0);

    // 4. Check cookie cleared
    const setCookie = logoutRes.headers['set-cookie'];
    const cookieStr = Array.isArray(setCookie) ? setCookie.join('; ') : String(setCookie);
    expect(cookieStr).toContain('nt_session=;');
  });
});
