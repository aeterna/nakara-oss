import { request } from '../api.js';

export interface DiscordChannel {
  id: string;
  name: string;
  type: number;
  parentId: string | null;
  position: number;
}

export interface DiscordRole {
  id: string;
  name: string;
  color: number;
  position: number;
}

export async function getGuildChannels(guildId: string): Promise<DiscordChannel[]> {
  return request<DiscordChannel[]>(`/api/v1/guilds/${encodeURIComponent(guildId)}/discord/channels`);
}

export async function getGuildRoles(guildId: string): Promise<DiscordRole[]> {
  return request<DiscordRole[]>(`/api/v1/guilds/${encodeURIComponent(guildId)}/discord/roles`);
}
