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

export interface DiscordMember {
  id: string;
  name: string;
}

export async function getGuildChannels(guildId: string): Promise<DiscordChannel[]> {
  return request<DiscordChannel[]>(`/api/v1/guilds/${encodeURIComponent(guildId)}/discord/channels`);
}

export async function getGuildRoles(guildId: string): Promise<DiscordRole[]> {
  return request<DiscordRole[]>(`/api/v1/guilds/${encodeURIComponent(guildId)}/discord/roles`);
}

export async function getGuildMembers(guildId: string, ids: string[]): Promise<DiscordMember[]> {
  const qs = new URLSearchParams({ ids: ids.join(',') });
  return request<DiscordMember[]>(`/api/v1/guilds/${encodeURIComponent(guildId)}/discord/members?${qs.toString()}`);
}
