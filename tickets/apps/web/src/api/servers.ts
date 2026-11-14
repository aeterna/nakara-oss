import { request } from '../api.js';

export interface GameServer {
  id: string;
  name: string;
  confirmed: boolean;
  edition: string | null;
  resourceVersion: string | null;
  playersOnline: number | null;
  lastSeenAt: string | null;
  revoked: boolean;
}

export interface PairCode {
  code: string;
  expiresAt: string;
}

export interface ActionResult {
  ok: boolean;
  code: string;
  message?: string;
  data?: Record<string, unknown>;
}

export interface GameAction {
  id: string;
  ticketId: string;
  serverId: string;
  action: string;
  params?: Record<string, unknown>;
  status: 'queued' | 'leased' | 'done' | 'failed' | 'expired';
  requestedBy: string;
  result?: ActionResult | null;
  createdAt: string;
  expiresAt: string;
}

export interface ActionRequest {
  action: string;
  params?: Record<string, unknown>;
  confirmRepeat?: boolean;
}

export async function getGameServers(guildId: string): Promise<GameServer[]> {
  return request<GameServer[]>(`/api/v1/guilds/${encodeURIComponent(guildId)}/game-servers`);
}

export async function createPairCode(guildId: string): Promise<PairCode> {
  return request<PairCode>(`/api/v1/guilds/${encodeURIComponent(guildId)}/game-servers/pair-codes`, {
    method: 'POST',
  });
}

export async function patchGameServer(
  guildId: string,
  serverId: string,
  data: { name?: string; confirmed?: boolean }
): Promise<GameServer> {
  return request<GameServer>(
    `/api/v1/guilds/${encodeURIComponent(guildId)}/game-servers/${encodeURIComponent(serverId)}`,
    {
      method: 'PATCH',
      body: JSON.stringify(data),
    }
  );
}

export async function deleteGameServer(guildId: string, serverId: string): Promise<void> {
  return request<void>(
    `/api/v1/guilds/${encodeURIComponent(guildId)}/game-servers/${encodeURIComponent(serverId)}`,
    {
      method: 'DELETE',
    }
  );
}

export async function getTicketActions(guildId: string, ticketId: string): Promise<GameAction[]> {
  return request<GameAction[]>(
    `/api/v1/guilds/${encodeURIComponent(guildId)}/tickets/${encodeURIComponent(ticketId)}/actions`
  );
}

export async function postTicketAction(
  guildId: string,
  ticketId: string,
  data: ActionRequest
): Promise<GameAction> {
  return request<GameAction>(
    `/api/v1/guilds/${encodeURIComponent(guildId)}/tickets/${encodeURIComponent(ticketId)}/actions`,
    {
      method: 'POST',
      body: JSON.stringify(data),
    }
  );
}
