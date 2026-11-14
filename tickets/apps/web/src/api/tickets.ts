import { request } from '../api.js';

export interface TicketFilters {
  status?: string;
  categoryId?: string;
  openerId?: string;
  claimerId?: string;
  cursor?: string;
  limit?: number;
  search?: string;
}

export interface AttachmentItem {
  id: string;
  filename: string;
  contentType: string | null;
  size: number;
  sha256: string;
  stored: boolean;
}

export interface MessageItem {
  id: string;
  authorId: string;
  authorName: string;
  isStaff: boolean;
  isSystem: boolean;
  content: string;
  embeds?: any[];
  attachments?: AttachmentItem[];
  editedAt: string | null;
  createdAt: string;
}

export interface TicketItem {
  id: string;
  number: number;
  guildId: string;
  categoryId: string;
  status: 'open' | 'claimed' | 'closed';
  openerId: string;
  claimerId: string | null;
  channelId: string;
  answers?: Record<string, any>;
  firstResponseAt: string | null;
  lastActivityAt: string | null;
  closedAt: string | null;
  closeReason: string | null;
  reopenedCount: number;
  createdAt: string;
}

export interface TicketListResponse {
  items: TicketItem[];
  next: string | null;
}

export const ticketsApi = {
  async getTickets(guildId: string, filters?: TicketFilters): Promise<TicketListResponse> {
    const params = new URLSearchParams();
    if (filters?.status) params.set('status', filters.status);
    if (filters?.categoryId) params.set('categoryId', filters.categoryId);
    if (filters?.openerId) params.set('openerId', filters.openerId);
    if (filters?.claimerId) params.set('claimerId', filters.claimerId);
    if (filters?.cursor) params.set('cursor', filters.cursor);
    if (filters?.limit) params.set('limit', String(filters.limit));
    if (filters?.search) params.set('search', filters.search);

    const qs = params.toString() ? `?${params.toString()}` : '';
    return request<TicketListResponse>(`/api/v1/guilds/${encodeURIComponent(guildId)}/tickets${qs}`);
  },

  async getTicket(guildId: string, ticketId: string): Promise<TicketItem> {
    return request<TicketItem>(
      `/api/v1/guilds/${encodeURIComponent(guildId)}/tickets/${encodeURIComponent(ticketId)}`
    );
  },

  async getTicketMessages(
    guildId: string,
    ticketId: string
  ): Promise<{ items: MessageItem[]; next: string | null }> {
    return request<{ items: MessageItem[]; next: string | null }>(
      `/api/v1/guilds/${encodeURIComponent(guildId)}/tickets/${encodeURIComponent(ticketId)}/messages`
    );
  },

  async transitionTicket(
    guildId: string,
    ticketId: string,
    transition: 'claim' | 'unclaim' | 'transfer' | 'close' | 'reopen',
    body?: { toUserId?: string; reason?: string }
  ): Promise<TicketItem> {
    return request<TicketItem>(
      `/api/v1/guilds/${encodeURIComponent(guildId)}/tickets/${encodeURIComponent(ticketId)}/${encodeURIComponent(transition)}`,
      {
        method: 'POST',
        body: body ? JSON.stringify(body) : undefined,
      }
    );
  },
};
