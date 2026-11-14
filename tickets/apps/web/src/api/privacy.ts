import { request } from '../api.js';

export interface DeleteDataCounts {
  messages: number;
  attachments: number;
  ratings: number;
  tickets: number;
}

export interface DeleteDataResponse {
  ok?: boolean;
  kind?: string;
  status?: string;
  createdAt?: string;
  counts?: DeleteDataCounts;
  messages?: number;
  attachments?: number;
  ratings?: number;
  tickets?: number;
}

export async function deleteMyData(): Promise<DeleteDataResponse> {
  return request<DeleteDataResponse>('/api/v1/me/data', {
    method: 'DELETE',
  });
}

export async function exportGuildData(guildId: string): Promise<any> {
  return request<any>(`/api/v1/guilds/${encodeURIComponent(guildId)}/export`);
}
