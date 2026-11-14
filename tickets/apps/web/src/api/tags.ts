import { request } from '../api.js';

export interface TagInput {
  name: string;
  content: string;
  body?: string;
}

export interface Tag extends TagInput {
  id: string;
}

export interface BlockInput {
  userId: string;
  user_id?: string;
  reason?: string | null;
  expiresAt?: string | null;
  expires_at?: string | null;
}

export interface Block extends BlockInput {
  id?: string;
  createdBy?: string;
  created_by?: string;
  createdAt: string;
  created_at?: string;
}

export async function getTags(guildId: string): Promise<Tag[]> {
  return request<Tag[]>(`/api/v1/guilds/${encodeURIComponent(guildId)}/tags`);
}

export async function createTag(guildId: string, input: TagInput): Promise<Tag> {
  const content = input.content ?? input.body ?? '';
  const payload = {
    name: input.name,
    content,
    body: content,
  };
  return request<Tag>(`/api/v1/guilds/${encodeURIComponent(guildId)}/tags`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function updateTag(guildId: string, tagId: string, input: TagInput): Promise<Tag> {
  const content = input.content ?? input.body ?? '';
  const payload = {
    name: input.name,
    content,
    body: content,
  };
  return request<Tag>(`/api/v1/guilds/${encodeURIComponent(guildId)}/tags/${encodeURIComponent(tagId)}`, {
    method: 'PUT',
    body: JSON.stringify(payload),
  });
}

export async function deleteTag(guildId: string, tagId: string): Promise<void> {
  return request<void>(`/api/v1/guilds/${encodeURIComponent(guildId)}/tags/${encodeURIComponent(tagId)}`, {
    method: 'DELETE',
  });
}

export async function getBlocks(guildId: string): Promise<Block[]> {
  return request<Block[]>(`/api/v1/guilds/${encodeURIComponent(guildId)}/blocks`);
}

export async function createBlock(guildId: string, input: BlockInput): Promise<Block> {
  const payload = {
    userId: input.userId ?? input.user_id,
    reason: input.reason ?? null,
    expiresAt: input.expiresAt ?? input.expires_at ?? null,
  };
  return request<Block>(`/api/v1/guilds/${encodeURIComponent(guildId)}/blocks`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function deleteBlock(guildId: string, userId: string): Promise<void> {
  return request<void>(`/api/v1/guilds/${encodeURIComponent(guildId)}/blocks/${encodeURIComponent(userId)}`, {
    method: 'DELETE',
  });
}

export const tagsApi = {
  getTags,
  createTag,
  updateTag,
  deleteTag,
  getBlocks,
  createBlock,
  deleteBlock,
};
