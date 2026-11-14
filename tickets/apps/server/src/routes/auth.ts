import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { randomBytes, randomUUID, createHash, createHmac, timingSafeEqual } from 'node:crypto';
import { eq } from 'drizzle-orm';
import { sessions } from '@nakara-tickets/db';
import { getSessionCookieOptions, userCache } from '../session.js';
import type { TicketsConfig } from '../config.js';

function getOAuthKey(key: Buffer): Buffer {
  return createHmac('sha256', key).update('oauth-cookie').digest();
}

function signOAuthPayload(payload: object, key: Buffer): string {
  const derivedKey = getOAuthKey(key);
  const payloadB64 = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const sig = createHmac('sha256', derivedKey).update(payloadB64).digest('base64url');
  return `${payloadB64}.${sig}`;
}

function verifyOAuthCookie(
  rawCookie: string,
  key: Buffer
): { state: string; codeVerifier: string; exp?: number } | null {
  const dotIndex = rawCookie.lastIndexOf('.');
  if (dotIndex === -1) {
    return null;
  }
  const payloadB64 = rawCookie.slice(0, dotIndex);
  const sig = rawCookie.slice(dotIndex + 1);

  const derivedKey = getOAuthKey(key);
  const expectedSig = createHmac('sha256', derivedKey).update(payloadB64).digest('base64url');
  const sigBuf = Buffer.from(sig);
  const expectedBuf = Buffer.from(expectedSig);

  if (sigBuf.length !== expectedBuf.length || !timingSafeEqual(sigBuf, expectedBuf)) {
    return null;
  }

  try {
    const data = JSON.parse(Buffer.from(payloadB64, 'base64url').toString('utf8'));
    if (data.exp && typeof data.exp === 'number') {
      const nowSec = Math.floor(Date.now() / 1000);
      if (data.exp < nowSec) {
        return null;
      }
    }
    return data;
  } catch {
    return null;
  }
}

export default async function (app: FastifyInstance) {
  app.get('/auth/login', async (req: FastifyRequest, reply: FastifyReply) => {
    const config = req.server.config as TicketsConfig | null;
    if (!config?.DISCORD_APP_ID || !config?.TICKETS_DATA_KEY) {
      return reply.code(500).send({ code: 'config_error', message: 'Discord app configuration missing' });
    }

    const state = randomBytes(32).toString('base64url');
    const codeVerifier = randomBytes(32).toString('base64url');
    const codeChallenge = createHash('sha256').update(codeVerifier).digest('base64url');
    const exp = Math.floor(Date.now() / 1000) + 600; // 10 minutes

    const signedCookie = signOAuthPayload({ state, codeVerifier, exp }, config.TICKETS_DATA_KEY);
    const isLocalhost = config.PUBLIC_ORIGIN.startsWith('http://localhost');

    reply.setCookie('nt_oauth', signedCookie, {
      path: '/auth',
      httpOnly: true,
      secure: !isLocalhost,
      sameSite: 'lax',
      maxAge: 600, // 10 minutes
    });

    const params = new URLSearchParams({
      client_id: config.DISCORD_APP_ID,
      response_type: 'code',
      redirect_uri: `${config.PUBLIC_ORIGIN}/auth/callback`,
      scope: 'identify guilds',
      state,
      code_challenge: codeChallenge,
      code_challenge_method: 'S256',
    });

    return reply.redirect(`https://discord.com/oauth2/authorize?${params.toString()}`);
  });

  app.get('/auth/callback', async (req: FastifyRequest, reply: FastifyReply) => {
    const query = req.query as Record<string, string | undefined>;
    const code = query.code;
    const state = query.state;

    if (!code || !state) {
      return reply.code(400).send({ code: 'invalid', message: 'Missing code or state query parameter' });
    }

    const rawOauthCookie = req.cookies?.nt_oauth;
    if (!rawOauthCookie) {
      return reply.code(400).send({ code: 'invalid', message: 'Missing OAuth session cookie' });
    }

    const config = req.server.config as TicketsConfig | null;
    const db = req.server.db;
    if (!config?.DISCORD_APP_ID || !config?.DISCORD_CLIENT_SECRET || !config?.TICKETS_DATA_KEY || !db) {
      return reply.code(500).send({ code: 'server_error', message: 'Server configuration or database missing' });
    }

    const oauthData = verifyOAuthCookie(rawOauthCookie, config.TICKETS_DATA_KEY);
    if (!oauthData) {
      return reply.code(400).send({ code: 'invalid', message: 'Invalid or expired OAuth session cookie' });
    }

    if (oauthData.state !== state) {
      return reply.code(400).send({ code: 'invalid', message: 'State mismatch' });
    }

    // Exchange authorization code for token
    const tokenParams = new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      redirect_uri: `${config.PUBLIC_ORIGIN}/auth/callback`,
      code_verifier: oauthData.codeVerifier,
    });

    const basicAuth = Buffer.from(`${config.DISCORD_APP_ID}:${config.DISCORD_CLIENT_SECRET}`).toString('base64');
    let tokenData: { access_token: string };
    try {
      const tokenRes = await fetch('https://discord.com/api/v10/oauth2/token', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          Authorization: `Basic ${basicAuth}`,
        },
        body: tokenParams.toString(),
        signal: AbortSignal.timeout(10_000),
      });

      if (!tokenRes.ok) {
        return reply.code(400).send({ code: 'oauth_failed', message: 'Failed to exchange authorization code' });
      }
      tokenData = (await tokenRes.json()) as { access_token: string };
    } catch {
      return reply.code(400).send({ code: 'oauth_failed', message: 'Failed to contact OAuth token endpoint' });
    }

    // Read user identity with access token
    let userData: { id: string; username: string; avatar?: string | null };
    try {
      const userRes = await fetch('https://discord.com/api/v10/users/@me', {
        headers: {
          Authorization: `Bearer ${tokenData.access_token}`,
        },
        signal: AbortSignal.timeout(10_000),
      });

      if (!userRes.ok) {
        return reply.code(400).send({ code: 'oauth_failed', message: 'Failed to fetch user profile' });
      }
      userData = (await userRes.json()) as { id: string; username: string; avatar?: string | null };
    } catch {
      return reply.code(400).send({ code: 'oauth_failed', message: 'Failed to contact Discord user endpoint' });
    }

    // Discard Discord access token (never stored)
    // Create new session row with SHA-256 token hash and SHA-256 CSRF hash
    const sessionId = randomUUID();
    const sessionToken = randomBytes(32).toString('base64url');
    const tokenHash = createHash('sha256').update(sessionToken).digest('hex');
    const plainCsrf = createHmac('sha256', config.TICKETS_DATA_KEY)
      .update(`csrf:${sessionId}`)
      .digest('hex');
    const csrfHash = createHash('sha256').update(plainCsrf).digest('hex');
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

    await db.insert(sessions).values({
      id: sessionId,
      user_id: userData.id,
      token_hash: tokenHash,
      csrf_hash: csrfHash,
      expires_at: expiresAt,
    });

    userCache.set(userData.id, {
      id: userData.id,
      username: userData.username,
      avatar: userData.avatar ?? null,
    });

    reply.clearCookie('nt_oauth', { path: '/auth' });
    reply.setCookie('nt_session', sessionToken, getSessionCookieOptions(config));

    return reply.redirect('/');
  });

  app.post(
    '/auth/logout',
    {
      preHandler: [
        async (req: FastifyRequest, reply: FastifyReply) => {
          if (typeof req.server.requireUser === 'function') {
            await req.server.requireUser(req, reply);
          } else {
            reply.code(401).send({ code: 'unauthorized', message: 'Authentication required' });
          }
        },
      ],
    },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const db = req.server.db;
      if (req.session?.id && db) {
        try {
          await db.delete(sessions).where(eq(sessions.id, req.session.id));
        } catch {
          // proceed to clear cookie
        }
      }

      reply.clearCookie('nt_session', { path: '/' });
      return reply.code(204).send();
    }
  );
}
