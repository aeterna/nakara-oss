import type { CloseHookContext, DiscordPort } from '../types.js';
import type { TicketsDb } from '@nakara-tickets/db';

export async function ratingOnClose(ctx: CloseHookContext): Promise<void> {
  // Stub close hook: do nothing
}

export async function handleRatingButton(
  port: DiscordPort,
  db: TicketsDb,
  interaction: any,
  deps?: any
): Promise<void> {
  if (typeof interaction?.deferReply === 'function' && !interaction.deferred) {
    await interaction.deferReply({ ephemeral: true });
  } else if (port?.deferReply) {
    try {
      await port.deferReply(interaction, { ephemeral: true });
    } catch {}
  }

  if (typeof interaction?.editReply === 'function') {
    await interaction.editReply({ content: 'not available yet' });
  } else if (port?.editReply) {
    await port.editReply(interaction, { content: 'not available yet' });
  } else if (typeof interaction?.reply === 'function' && !interaction.replied) {
    await interaction.reply({ content: 'not available yet', ephemeral: true });
  }
}

export async function handleRatingModal(
  port: DiscordPort,
  db: TicketsDb,
  interaction: any,
  deps?: any
): Promise<void> {
  if (typeof interaction?.deferReply === 'function' && !interaction.deferred) {
    await interaction.deferReply({ ephemeral: true });
  } else if (port?.deferReply) {
    try {
      await port.deferReply(interaction, { ephemeral: true });
    } catch {}
  }

  if (typeof interaction?.editReply === 'function') {
    await interaction.editReply({ content: 'not available yet' });
  } else if (port?.editReply) {
    await port.editReply(interaction, { content: 'not available yet' });
  } else if (typeof interaction?.reply === 'function' && !interaction.replied) {
    await interaction.reply({ content: 'not available yet', ephemeral: true });
  }
}
