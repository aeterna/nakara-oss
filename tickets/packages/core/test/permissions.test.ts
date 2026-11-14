import { describe, it, expect } from 'vitest';
import {
  MANAGE_GUILD,
  ADMINISTRATOR,
  isStaff,
  canViewTicket,
} from '../src/permissions.js';

describe('permissions acceptance tests', () => {
  describe('isStaff', () => {
    it('returns true when user has MANAGE_GUILD permission', () => {
      const result = isStaff({
        permissions: MANAGE_GUILD,
        roleIds: ['role_regular'],
        staffRoleIds: ['role_staff'],
      });
      expect(result).toBe(true);
    });

    it('returns true when user has ADMINISTRATOR permission', () => {
      const result = isStaff({
        permissions: ADMINISTRATOR,
        roleIds: [],
        staffRoleIds: ['role_staff'],
      });
      expect(result).toBe(true);
    });

    it('returns true when user permissions include combined flags with MANAGE_GUILD or ADMINISTRATOR', () => {
      const combined = (1n << 0n) | MANAGE_GUILD | (1n << 10n);
      expect(isStaff({ permissions: combined, roleIds: [], staffRoleIds: [] })).toBe(true);

      const combinedAdmin = (1n << 1n) | ADMINISTRATOR;
      expect(isStaff({ permissions: combinedAdmin, roleIds: [], staffRoleIds: [] })).toBe(true);
    });

    it('returns true when user has a role listed in staffRoleIds', () => {
      const result = isStaff({
        permissions: 0n,
        roleIds: ['role_other', 'role_moderator'],
        staffRoleIds: ['role_support', 'role_moderator'],
      });
      expect(result).toBe(true);
    });

    it('returns false when user has neither permissions nor matching staff roles (negative control)', () => {
      const result = isStaff({
        permissions: 1n << 0n, // some unrelated permission
        roleIds: ['role_member', 'role_vip'],
        staffRoleIds: ['role_moderator', 'role_admin'],
      });
      expect(result).toBe(false);
    });
  });

  describe('canViewTicket', () => {
    it('allows staff to view ticket', () => {
      expect(
        canViewTicket({
          userId: 'user_1',
          staff: true,
          openerId: 'user_opener',
          memberIds: ['user_opener'],
        }),
      ).toBe(true);
    });

    it('allows the ticket opener to view ticket', () => {
      expect(
        canViewTicket({
          userId: 'user_opener',
          staff: false,
          openerId: 'user_opener',
          memberIds: ['user_opener'],
        }),
      ).toBe(true);
    });

    it('allows an added ticket member to view ticket', () => {
      expect(
        canViewTicket({
          userId: 'user_added_member',
          staff: false,
          openerId: 'user_opener',
          memberIds: ['user_opener', 'user_added_member'],
        }),
      ).toBe(true);
    });

    it('refuses users who are not staff, not the opener, and not members', () => {
      expect(
        canViewTicket({
          userId: 'user_outsider',
          staff: false,
          openerId: 'user_opener',
          memberIds: ['user_opener'],
        }),
      ).toBe(false);
    });
  });
});
