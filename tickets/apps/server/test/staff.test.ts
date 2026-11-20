import { describe, it, expect, vi, beforeEach } from 'vitest';
import { checkStaff, clearStaffCache } from '../src/staff.js';

const GUILD_ID = '111111111111111111';
const USER_ID = '222222222222222222';
const OTHER_USER_ID = '333333333333333333';
const ADMIN_ROLE_ID = '444444444444444444';
const MANAGE_ROLE_ID = '555555555555555555';

function jsonResponse(body: unknown, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  };
}

function mockFetch(overrides: {
  guild?: () => any;
  member?: () => any;
  roles?: () => any;
}) {
  return vi.fn(async (url: string) => {
    const urlStr = String(url);
    if (urlStr.endsWith(`/guilds/${GUILD_ID}/members/${USER_ID}`)) {
      return overrides.member ? overrides.member() : jsonResponse({ roles: [] });
    }
    if (urlStr.endsWith(`/guilds/${GUILD_ID}/roles`)) {
      return overrides.roles ? overrides.roles() : jsonResponse([{ id: GUILD_ID, permissions: '0' }]);
    }
    if (urlStr.endsWith(`/guilds/${GUILD_ID}`)) {
      return overrides.guild ? overrides.guild() : jsonResponse({ owner_id: OTHER_USER_ID });
    }
    throw new Error(`Unexpected URL: ${urlStr}`);
  });
}

describe('checkStaff guild owner and permissions', () => {
  beforeEach(() => {
    clearStaffCache();
  });

  it('returns true for the guild owner with zero roles', async () => {
    const fetchImpl = mockFetch({
      guild: () => jsonResponse({ id: GUILD_ID, owner_id: USER_ID }),
      member: () => jsonResponse({ roles: [] }),
      roles: () => jsonResponse([{ id: GUILD_ID, permissions: '0' }]),
    });

    const result = await checkStaff(
      { token: 'bot-token', fetchImpl: fetchImpl as any },
      GUILD_ID,
      USER_ID
    );

    expect(result).toBe(true);
  });

  it('returns false for a non-owner with no permissions and no staff roles', async () => {
    const fetchImpl = mockFetch({
      guild: () => jsonResponse({ id: GUILD_ID, owner_id: OTHER_USER_ID }),
      member: () => jsonResponse({ roles: [] }),
      roles: () => jsonResponse([{ id: GUILD_ID, permissions: '0' }]),
    });

    const result = await checkStaff(
      { token: 'bot-token', fetchImpl: fetchImpl as any },
      GUILD_ID,
      USER_ID
    );

    expect(result).toBe(false);
  });

  it('returns true for a non-owner with a MANAGE_GUILD role', async () => {
    const fetchImpl = mockFetch({
      guild: () => jsonResponse({ id: GUILD_ID, owner_id: OTHER_USER_ID }),
      member: () => jsonResponse({ roles: [MANAGE_ROLE_ID] }),
      roles: () =>
        jsonResponse([
          { id: GUILD_ID, permissions: '0' },
          { id: MANAGE_ROLE_ID, permissions: String(1n << 5n) },
        ]),
    });

    const result = await checkStaff(
      { token: 'bot-token', fetchImpl: fetchImpl as any },
      GUILD_ID,
      USER_ID
    );

    expect(result).toBe(true);
  });

  it('falls back to permissions when the guild endpoint returns 500', async () => {
    const fetchImpl = mockFetch({
      guild: () => jsonResponse({ message: 'Internal Server Error' }, 500),
      member: () => jsonResponse({ roles: [ADMIN_ROLE_ID] }),
      roles: () =>
        jsonResponse([
          { id: GUILD_ID, permissions: '0' },
          { id: ADMIN_ROLE_ID, permissions: String(1n << 3n) },
        ]),
    });

    const result = await checkStaff(
      { token: 'bot-token', fetchImpl: fetchImpl as any },
      GUILD_ID,
      USER_ID
    );

    expect(result).toBe(true);
  });

  it('returns false when the member endpoint returns 404, even for the guild owner', async () => {
    const fetchImpl = mockFetch({
      guild: () => jsonResponse({ id: GUILD_ID, owner_id: USER_ID }),
      member: () => jsonResponse({ message: 'Unknown Member' }, 404),
      roles: () => jsonResponse([{ id: GUILD_ID, permissions: '0' }]),
    });

    const result = await checkStaff(
      { token: 'bot-token', fetchImpl: fetchImpl as any },
      GUILD_ID,
      USER_ID
    );

    expect(result).toBe(false);
  });
});
