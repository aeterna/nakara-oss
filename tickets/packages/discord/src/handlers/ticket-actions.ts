import type { DiscordPort, CloseHookContext } from '../types.js';
import type { TicketsDb } from '@nakara-tickets/db';
import { getCategory, getSettings, getTicket, getTicketByChannel, transitionTicket, TicketError } from '@nakara-tickets/db';
import { isStaff } from '@nakara-tickets/core';
import { t, type TranslationKey, type SupportedLocale, translations } from '../i18n.js';
import { runCloseHooks } from './close-hooks.js';

function formatErrorMessage(locale: string, err: any): string {
  const normLocale = (locale === 'th' ? 'th' : 'en') as SupportedLocale;
  if (err instanceof TicketError || err?.name === 'TicketError' || err?.code) {
    const codeKey = `ticket_${err.code}` as TranslationKey;
    if (codeKey in translations[normLocale]) {
      return t(locale, codeKey);
    }
    if (codeKey in translations.en) {
      return t(locale, codeKey);
    }
  }
  return t(locale, 'error');
}

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
  const channelId = interaction.channelId ?? interaction.channel?.id;
  let ticket: any = null;
  try {
    ticket = ticketId
      ? await getTicket(db, guildId, ticketId)
      : (channelId ? await getTicketByChannel(db, guildId, channelId) : null);
  } catch (err: any) {
    if (err instanceof TicketError || err?.name === 'TicketError' || err?.code === 'not_found') {
      return { ticket: null, category: null };
    }
    throw err;
  }

  if (!ticket) return { ticket: null, category: null };

  let category: any = null;
  try {
    category = await getCategory(db, guildId, ticket.category_id);
  } catch (err: any) {
    if (err instanceof TicketError || err?.name === 'TicketError' || err?.code === 'not_found') {
      return { ticket, category: null };
    }
    throw err;
  }

  return { ticket, category };
}

export async function handleClaim(
  port: DiscordPort,
  db: TicketsDb,
  interaction: any,
  ticketId?: string
): Promise<void> {
  await port.deferReply(interaction, { ephemeral: true });

  const guildId = interaction.guildId;
  let locale = 'th';
  try {
    const settings = await getSettings(db, guildId);
    if (settings?.locale) locale = settings.locale;
  } catch {}

  try {
    const { ticket, category } = await resolveTicketAndCategory(db, interaction, ticketId);
    if (!ticket || !category) {
      await port.editReply(interaction, { content: t(locale, 'ticket_not_found') });
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
      await port.editReply(interaction, { content: t(locale, 'staff_only') });
      return;
    }

    const actorId = interaction.user?.id ?? interaction.member?.user?.id;
    await transitionTicket(db, guildId, ticket.id, 'claim', actorId);

    const sysMsg = t(locale, 'ticket_claimed', { user: `<@${actorId}>` });
    await port.sendMessage(ticket.channel_id, { content: sysMsg });
    await port.editReply(interaction, { content: sysMsg });
  } catch (err: any) {
    if (err instanceof TicketError || err?.name === 'TicketError' || err?.code) {
      await port.editReply(interaction, { content: formatErrorMessage(locale, err) });
      return;
    }
    console.error('Error handling claim:', err);
    await port.editReply(interaction, { content: t(locale, 'error') });
  }
}

export async function handleClose(
  port: DiscordPort,
  db: TicketsDb,
  interaction: any,
  ticketId?: string,
  reason?: string,
  deps?: { dataKey?: Buffer; log?: any } | any
): Promise<void> {
  await port.deferReply(interaction, { ephemeral: true });

  const guildId = interaction.guildId;
  let locale = 'th';
  let settings: any = null;
  try {
    settings = await getSettings(db, guildId);
    if (settings?.locale) locale = settings.locale;
  } catch {}

  try {
    const { ticket, category } = await resolveTicketAndCategory(db, interaction, ticketId);
    if (!ticket || !category) {
      await port.editReply(interaction, { content: t(locale, 'ticket_not_found') });
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
      await port.editReply(interaction, { content: t(locale, 'staff_only') });
      return;
    }

    const actorId = interaction.user?.id ?? interaction.member?.user?.id;
    await transitionTicket(db, guildId, ticket.id, 'close', actorId, undefined, reason);

    let sysMsg = t(locale, 'ticket_closed', { user: `<@${actorId}>` });
    if (reason) {
      sysMsg += ` (${reason})`;
    }

    await port.sendMessage(ticket.channel_id, { content: sysMsg });
    await port.lockAndArchiveThread(ticket.channel_id);
    await port.editReply(interaction, { content: sysMsg });

    // Call close hooks without blocking reply
    const hookCtx: CloseHookContext = {
      port,
      db,
      dataKey: deps?.dataKey ?? Buffer.alloc(32),
      ticket,
      category,
      guildSettings: settings,
      actorId,
      log: deps?.log ?? console,
    };

    runCloseHooks(hookCtx).catch((err) => {
      (deps?.log ?? console).error?.('Unhandled error in close hooks:', err);
    });
  } catch (err: any) {
    if (err instanceof TicketError || err?.name === 'TicketError' || err?.code) {
      await port.editReply(interaction, { content: formatErrorMessage(locale, err) });
      return;
    }
    console.error('Error handling close:', err);
    await port.editReply(interaction, { content: t(locale, 'error') });
  }
}

export async function handleReopen(
  port: DiscordPort,
  db: TicketsDb,
  interaction: any,
  ticketId?: string
): Promise<void> {
  await port.deferReply(interaction, { ephemeral: true });

  const guildId = interaction.guildId;
  let locale = 'th';
  try {
    const settings = await getSettings(db, guildId);
    if (settings?.locale) locale = settings.locale;
  } catch {}

  try {
    const { ticket, category } = await resolveTicketAndCategory(db, interaction, ticketId);
    if (!ticket || !category) {
      await port.editReply(interaction, { content: t(locale, 'ticket_not_found') });
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
      await port.editReply(interaction, { content: t(locale, 'staff_only') });
      return;
    }

    const actorId = interaction.user?.id ?? interaction.member?.user?.id;
    await transitionTicket(db, guildId, ticket.id, 'reopen', actorId);

    const sysMsg = t(locale, 'ticket_reopened', { user: `<@${actorId}>` });
    await port.sendMessage(ticket.channel_id, { content: sysMsg });
    await port.editReply(interaction, { content: sysMsg });
  } catch (err: any) {
    if (err instanceof TicketError || err?.name === 'TicketError' || err?.code) {
      await port.editReply(interaction, { content: formatErrorMessage(locale, err) });
      return;
    }
    console.error('Error handling reopen:', err);
    await port.editReply(interaction, { content: t(locale, 'error') });
  }
}
