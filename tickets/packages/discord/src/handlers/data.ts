import type { DiscordPort } from '../types.js';
import type { TicketsDb } from '@nakara-tickets/db';
import { deleteUserData, getSettings } from '@nakara-tickets/db';
import { t } from '../i18n.js';

export async function handleDeleteMyData(
  port: DiscordPort,
  db: TicketsDb,
  interaction: any,
  deps?: any,
): Promise<void> {
  const guildId = interaction.guildId;
  const userId = interaction.user?.id ?? interaction.member?.user?.id;
  if (!guildId || !userId) return;

  let locale = 'th';
  try {
    const settings = await getSettings(db, guildId);
    if (settings?.locale) locale = settings.locale;
  } catch {}

  const isButton = Boolean(interaction.isButton && interaction.isButton());
  const customId = interaction.customId ?? '';

  if (isButton && (customId === 'nt:delme:confirm' || customId.startsWith('nt:delme:confirm'))) {
    if (typeof interaction.deferReply === 'function' && !interaction.deferred && !interaction.replied) {
      await interaction.deferReply({ ephemeral: true });
    } else if (port?.deferReply) {
      try {
        await port.deferReply(interaction, { ephemeral: true });
      } catch {}
    }

    const storage = deps?.storage ?? null;
    const counts = await deleteUserData(db, guildId, userId, storage);

    const successMsg = t(locale, 'delete_data_success', {
      messages: String(counts.messages),
      attachments: String(counts.attachments),
      ratings: String(counts.ratings),
      tickets: String(counts.tickets),
    });

    if (typeof interaction.editReply === 'function') {
      await interaction.editReply({ content: successMsg, components: [] });
    } else if (port?.editReply) {
      await port.editReply(interaction, { content: successMsg, components: [] });
    } else if (typeof interaction.reply === 'function' && !interaction.replied) {
      await interaction.reply({ content: successMsg, ephemeral: true });
    }
  } else {
    const confirmButtonRow = {
      type: 1, // ActionRow
      components: [
        {
          type: 2, // Button
          style: 4, // Danger
          custom_id: 'nt:delme:confirm',
          customId: 'nt:delme:confirm',
          label: t(locale, 'delete_data_confirm_button'),
        },
      ],
    };

    const promptMsg = t(locale, 'delete_data_prompt');

    if (port?.replyEphemeral) {
      await port.replyEphemeral(interaction, {
        content: promptMsg,
        components: [confirmButtonRow],
      });
    } else if (typeof interaction.reply === 'function' && !interaction.replied) {
      await interaction.reply({
        content: promptMsg,
        components: [confirmButtonRow],
        ephemeral: true,
      });
    } else if (typeof interaction.editReply === 'function') {
      await interaction.editReply({
        content: promptMsg,
        components: [confirmButtonRow],
      });
    }
  }
}
