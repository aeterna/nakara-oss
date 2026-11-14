import { request } from '../api.js';

export interface PanelEmbed {
  title: string;
  description?: string | null;
  color?: number | null;
  imageUrl?: string | null;
  footer?: string | null;
}

export interface PanelButton {
  categoryId: string;
  label: string;
  emoji?: string | null;
  style: 'primary' | 'secondary' | 'success' | 'danger';
}

export interface PanelInput {
  channelId: string;
  embed: PanelEmbed;
  kind: 'buttons' | 'select';
  buttons: PanelButton[];
}

export interface Panel extends PanelInput {
  id: string;
  messageId: string | null;
  createdAt?: string;
}

export async function getPanels(guildId: string): Promise<Panel[]> {
  return request<Panel[]>(`/api/v1/guilds/${encodeURIComponent(guildId)}/panels`);
}

export async function createPanel(guildId: string, input: PanelInput): Promise<Panel> {
  return request<Panel>(`/api/v1/guilds/${encodeURIComponent(guildId)}/panels`, {
    method: 'POST',
    body: JSON.stringify(input),
  });
}

export async function updatePanel(guildId: string, panelId: string, input: PanelInput): Promise<Panel> {
  return request<Panel>(`/api/v1/guilds/${encodeURIComponent(guildId)}/panels/${encodeURIComponent(panelId)}`, {
    method: 'PUT',
    body: JSON.stringify(input),
  });
}

export async function deletePanel(guildId: string, panelId: string): Promise<void> {
  return request<void>(`/api/v1/guilds/${encodeURIComponent(guildId)}/panels/${encodeURIComponent(panelId)}`, {
    method: 'DELETE',
  });
}

export async function sendPanel(guildId: string, panelId: string): Promise<Panel> {
  return request<Panel>(`/api/v1/guilds/${encodeURIComponent(guildId)}/panels/${encodeURIComponent(panelId)}/send`, {
    method: 'POST',
  });
}

export const panelsApi = {
  getPanels,
  createPanel,
  updatePanel,
  deletePanel,
  sendPanel,
};
