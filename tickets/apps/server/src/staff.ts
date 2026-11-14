import { isStaff } from '@nakara-tickets/core';

export interface CheckStaffOptions {
  token?: string;
  fetchImpl?: typeof fetch;
}

interface CacheEntry {
  result: boolean;
  expiresAt: number;
}

const CACHE_TTL_MS = 60_000;
const staffCache = new Map<string, CacheEntry>();

export function clearStaffCache(): void {
  staffCache.clear();
}

export async function checkStaff(
  options: CheckStaffOptions,
  guildId: string,
  userId: string,
  staffRoleIds: readonly string[] = []
): Promise<boolean> {
  const token = options?.token;
  if (!token) {
    return false;
  }

  const cacheKey = `${guildId}:${userId}`;
  const now = Date.now();
  const cached = staffCache.get(cacheKey);
  if (cached && now < cached.expiresAt) {
    return cached.result;
  }

  const fetchImpl = options.fetchImpl ?? fetch;

  try {
    const [memberRes, rolesRes] = await Promise.all([
      fetchImpl(`https://discord.com/api/v10/guilds/${guildId}/members/${userId}`, {
        headers: { Authorization: `Bot ${token}` },
      }),
      fetchImpl(`https://discord.com/api/v10/guilds/${guildId}/roles`, {
        headers: { Authorization: `Bot ${token}` },
      }),
    ]);

    if (!memberRes.ok || !rolesRes.ok) {
      staffCache.set(cacheKey, { result: false, expiresAt: now + CACHE_TTL_MS });
      return false;
    }

    const member = (await memberRes.json()) as { roles?: string[] };
    const roles = (await rolesRes.json()) as Array<{ id: string; permissions: string }>;

    let permissions = 0n;
    if (Array.isArray(roles)) {
      const everyone = roles.find((r) => r.id === guildId);
      if (everyone?.permissions) {
        permissions |= BigInt(everyone.permissions);
      }

      const memberRoles = member.roles ?? [];
      for (const roleId of memberRoles) {
        const role = roles.find((r) => r.id === roleId);
        if (role?.permissions) {
          permissions |= BigInt(role.permissions);
        }
      }
    }

    const result = isStaff({
      permissions,
      roleIds: member.roles ?? [],
      staffRoleIds: Array.from(staffRoleIds),
    });

    staffCache.set(cacheKey, { result, expiresAt: now + CACHE_TTL_MS });
    return result;
  } catch {
    staffCache.set(cacheKey, { result: false, expiresAt: now + CACHE_TTL_MS });
    return false;
  }
}
