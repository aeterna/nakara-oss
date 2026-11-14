import { request } from '../api.js';

export interface StatsDaily {
  date: string;
  opened: number;
  closed: number;
}

export interface StatsByCategory {
  category_id: string;
  categoryId?: string;
  name: string;
  opened: number;
}

export interface StatsStaff {
  user_id: string;
  userId?: string;
  claimed: number;
  closed: number;
  rating_avg: number | null;
  ratingAverage?: number | null;
}

export interface StatsResponse {
  opened: number;
  closed: number;
  open_now: number;
  openNow?: number;
  median_first_response_s: number | null;
  medianFirstResponseSeconds?: number | null;
  median_close_s: number | null;
  medianResolutionSeconds?: number | null;
  rating_avg: number | null;
  ratingAverage?: number | null;
  rating_count: number;
  ratingCount?: number;
  daily: StatsDaily[];
  by_category: StatsByCategory[];
  byCategory?: StatsByCategory[];
  staff: StatsStaff[];
  byStaff?: StatsStaff[];
}

export interface AuditEntry {
  id: string;
  actorId: string;
  actor_id?: string;
  kind: string;
  target: string | null;
  detail: Record<string, any> | null;
  createdAt: string;
  created_at?: string;
}

export interface AuditResponse {
  items: AuditEntry[];
  next: string | null;
}

export async function getStats(guildId: string, from?: string, to?: string): Promise<StatsResponse> {
  const query = new URLSearchParams();
  if (from) query.set('from', from);
  if (to) query.set('to', to);
  const qStr = query.toString();
  const url = `/api/v1/guilds/${encodeURIComponent(guildId)}/stats${qStr ? `?${qStr}` : ''}`;
  return request<StatsResponse>(url);
}

export async function getAudit(
  guildId: string,
  params?: { cursor?: string | null; limit?: number; action?: string }
): Promise<AuditResponse> {
  const query = new URLSearchParams();
  if (params?.cursor) query.set('cursor', params.cursor);
  if (params?.limit) query.set('limit', String(params.limit));
  if (params?.action) query.set('action', params.action);
  const qStr = query.toString();
  const url = `/api/v1/guilds/${encodeURIComponent(guildId)}/audit${qStr ? `?${qStr}` : ''}`;
  return request<AuditResponse>(url);
}
