import * as corePkg from '@nakara-tickets/core';

export const MANAGE_GUILD = 1n << 5n;
export const ADMINISTRATOR = 1n << 3n;

export interface IsStaffInput {
  permissions: bigint;
  roleIds: string[];
  staffRoleIds: string[];
}

export function isStaff(input: IsStaffInput): boolean {
  if (typeof (corePkg as any).isStaff === 'function') {
    return (corePkg as any).isStaff(input);
  }

  const { permissions, roleIds, staffRoleIds } = input;
  if ((permissions & MANAGE_GUILD) === MANAGE_GUILD || (permissions & ADMINISTRATOR) === ADMINISTRATOR) {
    return true;
  }
  return roleIds.some((r) => staffRoleIds.includes(r));
}
