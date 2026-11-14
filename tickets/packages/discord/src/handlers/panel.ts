import type { DiscordPort } from '../types.js';
import type { TicketsDb } from '@nakara-tickets/db';
import { panels } from '@nakara-tickets/db';
import { getCategory, getSettings } from '../db-bridge.js';
import { isStaff, MANAGE_GUILD, ADMINISTRATOR } from '../core-bridge.js';
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

export async function handlePanelSend(
  port: DiscordPort,
  db: TicketsDb,
  interaction: any,
  categoryIds: string[],
  targetChannelId: string
): Promise<void> {
  const guildId = interaction.guildId;
  const settings = await getSettings(db, guildId);
  const locale = settings?.locale ?? 'th';

  const memberInfo = extractMemberInfo(interaction);
  const hasManageServer =
    (memberInfo.permissions & MANAGE_GUILD) === MANAGE_GUILD ||
    (memberInfo.permissions & ADMINISTRATOR) === ADMINISTRATOR;

  const validCategories = [];
  let userIsStaff = hasManageServer;

  for (const catId of categoryIds) {
    const cat = await getCategory(db, guildId, catId);
    if (cat) {
      validCategories.push(cat);
      if (!userIsStaff) {
        const staffRoles = (cat.staff_role_ids ?? []) as string[];
        if (isStaff({ permissions: memberInfo.permissions, roleIds: memberInfo.roleIds, staffRoleIds: staffRoles })) {
          userIsStaff = true;
        }
      }
    }
  }

  if (!userIsStaff) {
    await port.replyEphemeral(interaction, t(locale, 'staff_only'));
    return;
  }

  if (validCategories.length === 0) {
    await port.replyEphemeral(interaction, t(locale, 'ticket_not_found'));
    return;
  }

  await port.deferReply(interaction, { ephemeral: true });

  const embed = {
    title: t(locale, 'panel_title'),
    description: t(locale, 'panel_description'),
    color: 0x5865f2,
  };

  const buttonComponents = validCategories.map((cat) => ({
    type: 2, // Button
    style: 1, // Primary
    custom_id: `nt:open:${cat.id}`,
    customId: `nt:open:${cat.id}`,
    label: cat.name,
    emoji: cat.emoji ? { name: cat.emoji } : undefined,
  }));

  // Chunk buttons into ActionRows of max 5
  const rows: any[] = [];
  for (let i = 0; i < buttonComponents.length; i += 5) {
    rows.push({
      type: 1, // ActionRow
      components: buttonComponents.slice(i, i + 5),
    });
  }

  const msg = await port.sendMessage(targetChannelId, {
    embeds: [embed],
    components: rows,
  });

  await db.insert(panels).values({
    guild_id: guildId,
    channel_id: targetChannelId,
    message_id: msg.id,
    embed,
    kind: 'category',
    buttons: buttonComponents,
  });

  await port.editReply(interaction, { content: t(locale, 'panel_sent') });
}
