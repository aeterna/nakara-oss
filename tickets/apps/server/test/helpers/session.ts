import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { sessions, type TicketsDb } from '@nakara-tickets/db';
import { deriveCsrfToken, userCache } from '../../src/session.js';
import type { TicketsConfig } from '../../src/config.js';

export interface TestSessionOptions {
  userId: string;
  username: string;
}

export interface TestSession {
  /** Ready-to-use `cookie` request header value, e.g. `nt_session=<token>`. */
  cookie: string;
  /** Plain CSRF token to send in `x-csrf-token` on non-GET requests. */
  csrf: string;
}

/**
 * Inserts a session row the same way `session.ts` reads it back:
 * `token_hash` = sha256(token), `csrf_hash` = sha256(csrf), and the plain
 * CSRF token is derived from the session id via `deriveCsrfToken`.
 */
export async function createTestSession(
  db: TicketsDb,
  config: Pick<TicketsConfig, 'TICKETS_DATA_KEY'>,
  { userId, username }: TestSessionOptions
): Promise<TestSession> {
  const sessionId = randomUUID();
  const token = randomBytes(32).toString('base64url');
  const csrf = deriveCsrfToken(config.TICKETS_DATA_KEY, sessionId);

  await db.insert(sessions).values({
    id: sessionId,
    user_id: userId,
    token_hash: createHash('sha256').update(token).digest('hex'),
    csrf_hash: createHash('sha256').update(csrf).digest('hex'),
    expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
  });

  // Seed the profile cache so the session resolves to `username` without a Discord lookup.
  userCache.set(userId, { id: userId, username, avatar: null });

  return { cookie: `nt_session=${token}`, csrf };
}
