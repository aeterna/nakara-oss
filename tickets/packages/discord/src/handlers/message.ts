import type { TicketsDb } from '@nakara-tickets/db';
import { getCategory, getTicketByChannel, appendMessage } from '../db-bridge.js';
import { isStaff } from '../core-bridge.js';

function extractMemberInfo(member: any): { permissions: bigint; roleIds: string[] } {
  let permissions = 0n;
  if (typeof member?.permissions === 'bigint') {
    permissions = member.permissions;
  } else if (member?.permissions != null) {
    try {
      permissions = BigInt(member.permissions);
    } catch {
      permissions = 0n;
    }
  } else if (member?.permissions?.bitfield != null) {
    try {
      permissions = BigInt(member.permissions.bitfield);
    } catch {
      permissions = 0n;
    }
  }

  let roleIds: string[] = [];
  if (Array.isArray(member?.roleIds)) {
    roleIds = member.roleIds;
  } else if (Array.isArray(member?.roles)) {
    roleIds = member.roles;
  } else if (member?.roles?.cache) {
    roleIds = Array.from(member.roles.cache.keys()) as string[];
  }

  return { permissions, roleIds };
}

export async function handleMessageCreate(
  db: TicketsDb,
  dataKey: Buffer,
  message: {
    id: string;
    guildId?: string;
    channelId?: string;
    content?: string;
    author?: { id: string; username?: string; bot?: boolean };
    member?: any;
    guild?: { id: string };
    channel?: { id: string };
  }
): Promise<void> {
  if (message.author?.bot) {
    return;
  }

  const guildId = message.guildId ?? message.guild?.id;
  const channelId = message.channelId ?? message.channel?.id;
  if (!guildId || !channelId) {
    return;
  }

  const ticket = await getTicketByChannel(db, guildId, channelId);
  if (!ticket) {
    return;
  }

  const category = await getCategory(db, guildId, ticket.category_id);
  const staffRoleIds = (category?.staff_role_ids ?? []) as string[];

  const memberInfo = extractMemberInfo(message.member);
  const userIsStaff = isStaff({
    permissions: memberInfo.permissions,
    roleIds: memberInfo.roleIds,
    staffRoleIds,
  });

  await appendMessage(db, dataKey, {
    guildId,
    ticketId: ticket.id,
    id: message.id,
    authorId: message.author?.id ?? 'unknown',
    authorName: message.author?.username ?? 'User',
    isStaff: userIsStaff,
    isSystem: false,
    content: message.content ?? '',
  });
}
