export const ADMINISTRATOR = 1n << 3n;
export const MANAGE_GUILD = 1n << 5n;

export interface IsStaffParams {
  permissions: bigint;
  roleIds: string[];
  staffRoleIds: string[];
}

export function isStaff({ permissions, roleIds, staffRoleIds }: IsStaffParams): boolean {
  if ((permissions & ADMINISTRATOR) === ADMINISTRATOR) {
    return true;
  }
  if ((permissions & MANAGE_GUILD) === MANAGE_GUILD) {
    return true;
  }
  const staffSet = new Set(staffRoleIds);
  return roleIds.some((r) => staffSet.has(r));
}

export interface CanViewTicketParams {
  userId: string;
  staff: boolean;
  openerId: string;
  memberIds?: string[];
}

export function canViewTicket({ userId, staff, openerId, memberIds }: CanViewTicketParams): boolean {
  if (staff) {
    return true;
  }
  if (userId === openerId) {
    return true;
  }
  if (memberIds && memberIds.includes(userId)) {
    return true;
  }
  return false;
}
