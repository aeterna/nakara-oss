import {
  type Client,
  ChannelType,
  type TextChannel,
  type ThreadChannel,
} from 'discord.js';
import type { DiscordPort } from './types.js';

export function createDiscordPort(client: Client): DiscordPort {
  return {
    async createPrivateThread(channelId: string, name: string) {
      const channel = (await client.channels.fetch(channelId)) as TextChannel;
      if (!channel || !channel.threads) {
        throw new Error(`Channel ${channelId} not found or cannot host threads`);
      }
      const thread = await channel.threads.create({
        name,
        type: ChannelType.PrivateThread,
        autoArchiveDuration: 1440,
      });
      return { id: thread.id, name: thread.name };
    },

    async addMember(threadId: string, userId: string) {
      const channel = (await client.channels.fetch(threadId)) as ThreadChannel;
      if (channel?.members) {
        await channel.members.add(userId);
      }
    },

    async sendMessage(channelId: string, payload: any) {
      const channel = (await client.channels.fetch(channelId)) as TextChannel | ThreadChannel;
      if (!channel) {
        throw new Error(`Channel ${channelId} not found`);
      }
      const msg = await channel.send(payload);
      return { id: msg.id };
    },

    async editMessage(channelId: string, messageId: string, payload: any) {
      const channel = (await client.channels.fetch(channelId)) as TextChannel | ThreadChannel;
      if (!channel) return;
      const msg = await channel.messages.fetch(messageId);
      if (msg) {
        await msg.edit(payload);
      }
    },

    async showModal(interaction: any, modal: any) {
      await interaction.showModal(modal);
    },

    async replyEphemeral(interaction: any, message: any) {
      const payload =
        typeof message === 'string'
          ? { content: message, ephemeral: true }
          : { ...message, ephemeral: true };

      if (interaction.deferred) {
        await interaction.editReply(payload);
      } else if (interaction.replied) {
        await interaction.followUp(payload);
      } else {
        await interaction.reply(payload);
      }
    },

    async deferReply(interaction: any, opts?: { ephemeral?: boolean }) {
      if (!interaction.deferred && !interaction.replied) {
        await interaction.deferReply({ ephemeral: opts?.ephemeral ?? true });
      }
    },

    async editReply(interaction: any, message: any) {
      await interaction.editReply(message);
    },

    async lockAndArchiveThread(threadId: string) {
      const channel = (await client.channels.fetch(threadId)) as ThreadChannel;
      if (channel) {
        if (typeof channel.setLocked === 'function') {
          await channel.setLocked(true);
        }
        if (typeof channel.setArchived === 'function') {
          await channel.setArchived(true);
        }
      }
    },
  };
}
