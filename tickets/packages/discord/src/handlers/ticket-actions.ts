import type { DiscordPort } from '../types.js';
import type { TicketsDb } from '@nakara-tickets/db';
import { getCategory, getSettings, getTicket, getTicketByChannel, transitionTicket } from '../db-bridge.js';
import { isStaff } from '../core-bridge.js';
import { t } from '../i18n.js';

function extractMemberInfo(interaction: any): { permissions: bigint; roleIds: string[] } {
  let permissions = 0n;
  if (typeof interaction.memberPermissions === 'bigint') {
    permissions = interaction.memberPermissions;
  } else if (interaction.memberPermissions != null) {
    try {
      permissions = BigInt(interaction.memberPermissions);
    } catch {
      permissions = 0n;
    }
  } else if (interaction.member?.permissions?.bitfield != null) {
    try {
      permissions = BigInt(interaction.member.permissions.bitfield);
    } catch {
      permissions = 0n;
    }
  }

  let roleIds: string[] = [];
  if (Array.isArray(interaction.memberRoleIds)) {
    roleIds = interaction.memberRoleIds;
  } else if (Array.isArray(interaction.member?.roles)) {
    roleIds = interaction.member.roles;
  } else if (interaction.member?.roles?.cache) {
    roleIds = Array.from(interaction.member.roles.cache.keys()) as string[];
  }

  return { permissions, roleIds };
}

async function resolveTicketAndCategory(db: TicketsDb, interaction: any, ticketId?: string) {
  const guildId = interaction.guildId;
  const ticket = ticketId
    ? await getTicket(db, guildId, ticketId)
    : await getTicketByChannel(db, guildId, interaction.channelId ?? interaction.channel?.id);

  if (!ticket) return { ticket: null, category: null };

  const category = await getCategory(db, guildId, ticket.category_id);
  return { ticket, category };
}

export async function handleClaim(
  port: DiscordPort,
  db: TicketsDb,
  interaction: any,
  ticketId?: string
): Promise<void> {
  const guildId = interaction.guildId;
  const settings = await getSettings(db, guildId);
  const locale = settings?.locale ?? 'th';

  const { ticket, category } = await resolveTicketAndCategory(db, interaction, ticketId);
  if (!ticket || !category) {
    await port.replyEphemeral(interaction, t(locale, 'ticket_not_found'));
    return;
  }

  const memberInfo = extractMemberInfo(interaction);
  const staffRoleIds = (category.staff_role_ids ?? []) as string[];
  const userIsStaff = isStaff({
    permissions: memberInfo.permissions,
    roleIds: memberInfo.roleIds,
    staffRoleIds,
  });

  if (!userIsStaff) {
    await port.replyEphemeral(interaction, t(locale, 'staff_only'));
    return;
  }

  await port.deferReply(interaction, { ephemeral: true });

  const actorId = interaction.user?.id ?? interaction.member?.user?.id;
  await transitionTicket(db, guildId, ticket.id, 'claim', actorId);

  const sysMsg = t(locale, 'ticket_claimed', { user: `<@${actorId}>` });
  await port.sendMessage(ticket.channel_id, { content: sysMsg });
  await port.editReply(interaction, { content: sysMsg });
}

export async function handleClose(
  port: DiscordPort,
  db: TicketsDb,
  interaction: any,
  ticketId?: string,
  reason?: string
): Promise<void> {
  const guildId = interaction.guildId;
  const settings = await getSettings(db, guildId);
  const locale = settings?.locale ?? 'th';

  const { ticket, category } = await resolveTicketAndCategory(db, interaction, ticketId);
  if (!ticket || !category) {
    await port.replyEphemeral(interaction, t(locale, 'ticket_not_found'));
    return;
  }

  const memberInfo = extractMemberInfo(interaction);
  const staffRoleIds = (category.staff_role_ids ?? []) as string[];
  const userIsStaff = isStaff({
    permissions: memberInfo.permissions,
    roleIds: memberInfo.roleIds,
    staffRoleIds,
  });

  if (!userIsStaff) {
    await port.replyEphemeral(interaction, t(locale, 'staff_only'));
    return;
  }

  await port.deferReply(interaction, { ephemeral: true });

  const actorId = interaction.user?.id ?? interaction.member?.user?.id;
  await transitionTicket(db, guildId, ticket.id, 'close', actorId, undefined, reason);

  let sysMsg = t(locale, 'ticket_closed', { user: `<@${actorId}>` });
  if (reason) {
    sysMsg += ` (${reason})`;
  }

  await port.sendMessage(ticket.channel_id, { content: sysMsg });
  await port.lockAndArchiveThread(ticket.channel_id);
  await port.editReply(interaction, { content: sysMsg });
}

export async function handleReopen(
  port: DiscordPort,
  db: TicketsDb,
  interaction: any,
  ticketId?: string
): Promise<void> {
  const guildId = interaction.guildId;
  const settings = await getSettings(db, guildId);
  const locale = settings?.locale ?? 'th';

  const { ticket, category } = await resolveTicketAndCategory(db, interaction, ticketId);
  if (!ticket || !category) {
    await port.replyEphemeral(interaction, t(locale, 'ticket_not_found'));
    return;
  }

  const memberInfo = extractMemberInfo(interaction);
  const staffRoleIds = (category.staff_role_ids ?? []) as string[];
  const userIsStaff = isStaff({
    permissions: memberInfo.permissions,
    roleIds: memberInfo.roleIds,
    staffRoleIds,
  });

  if (!userIsStaff) {
    await port.replyEphemeral(interaction, t(locale, 'staff_only'));
    return;
  }

  await port.deferReply(interaction, { ephemeral: true });

  const actorId = interaction.user?.id ?? interaction.member?.user?.id;
  await transitionTicket(db, guildId, ticket.id, 'reopen', actorId);

  const sysMsg = t(locale, 'ticket_reopened', { user: `<@${actorId}>` });
  await port.sendMessage(ticket.channel_id, { content: sysMsg });
  await port.editReply(interaction, { content: sysMsg });
}
