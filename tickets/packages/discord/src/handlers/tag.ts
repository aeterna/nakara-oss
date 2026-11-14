import type { DiscordPort } from '../types.js';
import type { TicketsDb } from '@nakara-tickets/db';
import {
  getCategory,
  getSettings,
  getTicketByChannel,
  tags,
  guilds,
  inGuild,
} from '@nakara-tickets/db';
import { and, eq, asc } from 'drizzle-orm';
import { isStaff } from '@nakara-tickets/core';
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

export async function handleTagCommand(
  port: DiscordPort,
  db: TicketsDb,
  interaction: any,
  _deps?: any
): Promise<void> {
  if (typeof interaction?.deferReply === 'function' && !interaction.deferred) {
    await interaction.deferReply({ ephemeral: true });
  } else if (port?.deferReply) {
    try {
      await port.deferReply(interaction, { ephemeral: true });
    } catch {}
  }

  const guildId = interaction.guildId;
  const channelId = interaction.channelId ?? interaction.channel?.id;

  let locale = 'th';
  try {
    const settings = await getSettings(db, guildId);
    if (settings?.locale) {
      locale = settings.locale;
    }
  } catch {}

  const replyError = async (content: string) => {
    if (typeof interaction?.editReply === 'function') {
      await interaction.editReply({ content });
    } else if (port?.editReply) {
      await port.editReply(interaction, { content });
    } else if (typeof interaction?.reply === 'function' && !interaction.replied) {
      await interaction.reply({ content, ephemeral: true });
    }
  };

  let ticket: any = null;
  let category: any = null;

  try {
    if (channelId) {
      ticket = await getTicketByChannel(db, guildId, channelId);
      if (ticket) {
        category = await getCategory(db, guildId, ticket.category_id);
      }
    }
  } catch {}

  const memberInfo = extractMemberInfo(interaction);
  const staffRoleIds = (category?.staff_role_ids ?? []) as string[];
  const userIsStaff = isStaff({
    permissions: memberInfo.permissions,
    roleIds: memberInfo.roleIds,
    staffRoleIds,
  });

  if (!userIsStaff) {
    await replyError(t(locale, 'staff_only'));
    return;
  }

  if (!ticket) {
    await replyError(t(locale, 'ticket_not_found'));
    return;
  }

  const tagName = (
    typeof interaction.options?.getString === 'function'
      ? interaction.options.getString('name')
      : interaction.options?.get?.('name')?.value ?? interaction.options?.name
  )?.trim()?.toLowerCase();

  if (!tagName) {
    await replyError(t(locale, 'tag_not_found'));
    return;
  }

  const [tag] = await db
    .select()
    .from(tags)
    .where(and(inGuild(tags, guildId), eq(tags.name, tagName)))
    .limit(1);

  if (!tag) {
    await replyError(t(locale, 'tag_not_found'));
    return;
  }

  const invokerId = interaction.user?.id ?? interaction.member?.user?.id ?? interaction.member?.id;
  let guildName = interaction.guild?.name;
  if (!guildName) {
    try {
      const [g] = await db
        .select({ name: guilds.name })
        .from(guilds)
        .where(eq(guilds.guild_id, guildId))
        .limit(1);
      if (g) guildName = g.name;
    } catch {}
  }
  guildName = guildName ?? 'Server';

  const vars: Record<string, string> = {
    user: `<@${ticket.opener_id}>`,
    staff: `<@${invokerId}>`,
    ticket: String(ticket.number),
    server: guildName,
  };

  const renderedBody = tag.body.replace(/\{([a-zA-Z0-9_-]+)\}/g, (match: string, key: string) => {
    if (key in vars) {
      return vars[key];
    }
    return match;
  });

  const payload = {
    content: renderedBody,
    allowed_mentions: { users: [ticket.opener_id] },
    allowedMentions: { users: [ticket.opener_id] },
  };

  if (typeof port?.sendMessage === 'function') {
    await port.sendMessage(ticket.channel_id, payload);
  }

  const successMsg = t(locale, 'tag_sent');
  if (typeof interaction?.editReply === 'function') {
    await interaction.editReply({ content: successMsg });
  } else if (port?.editReply) {
    await port.editReply(interaction, { content: successMsg });
  }
}

export async function handleTagAutocomplete(
  db: TicketsDb,
  interaction: any
): Promise<void> {
  const guildId = interaction.guildId;
  let query = '';
  if (typeof interaction.options?.getFocused === 'function') {
    const focused = interaction.options.getFocused();
    query = typeof focused === 'string' ? focused : focused?.value ?? '';
  } else if (typeof interaction.options?.get === 'function') {
    const opt = interaction.options.get('name');
    query = opt?.value ?? '';
  }
  query = (query || '').toLowerCase();

  const tagRows = await db
    .select({ name: tags.name })
    .from(tags)
    .where(inGuild(tags, guildId))
    .orderBy(asc(tags.name));

  const matching = tagRows
    .filter((t) => t.name.toLowerCase().startsWith(query))
    .slice(0, 25);

  const choices = matching.map((t) => ({ name: t.name, value: t.name }));

  if (typeof interaction?.respond === 'function') {
    await interaction.respond(choices);
  }
}
